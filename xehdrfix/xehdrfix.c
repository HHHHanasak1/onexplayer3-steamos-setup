#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/pci.h>
#include <linux/io.h>

/*
 * xe eDP fixes for PQ HDR on the ONEXPLAYER 3 OLED (Samsung AMS881KB01), transcoder A / DDI A only:
 *
 * - With Panel Replay active, the panel stops taking new frames when MSA MISC1 bit 6 (colorimetry
 *   in the VSC SDP) is set, which xe does for BT.2020. It keeps showing its stored frame (black or
 *   frozen). The panel reads the colorimetry from the VSC SDP either way, so clear the bit after
 *   intel_ddi_set_dp_msa() wrote it.
 *
 * - With PSR/Panel Replay off, the VSC SDP header that hsw_write_infoframe() writes while the DIP
 *   is disabled can keep a bad ECC (first HDR modeset after Panel Replay was active, resume) and
 *   the panel drops the SDP: black. Writing the header dword again once the DIP is enabled makes
 *   the hardware compute the ECC again.
 *
 * - With FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE set in DPCD 0x107, the panel often runs on its own
 *   timing while Panel Replay is active and shows new frames at its 30 Hz VRR minimum (until the
 *   next resume). Clear the bit when link training writes DP_DOWNSPREAD_CTRL on AUX A
 *   (intel_dp_link_training_set_mode() is inlined, so catch the drm_dp_dpcd_write() call). The
 *   source still sends the AS SDP.
 */

#define DISPLAY_WINDOW 0x60000		/* transcoder A registers */
#define TRANS_DDI_FUNC_CTL_A 0x0400
#define TRANS_MSA_MISC_A 0x0410
#define VIDEO_DIP_CTL_A 0x0200
#define VIDEO_DIP_VSC_DATA_A 0x0320
#define TGL_TRANS_DDI_PORT_MASK (0xf << 27)
#define TGL_TRANS_DDI_PORT_A (1 << 27)
#define DP_MSA_MISC_COLOR_VSC_SDP (1 << 14)
#define VIDEO_DIP_ENABLE_VSC (1 << 20)
#define DP_SDP_VSC 0x07
#define DP_DOWNSPREAD_CTRL 0x107
#define DP_FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE (1 << 6)

static void __iomem *regs;
static atomic_t msa_cleared = ATOMIC_INIT(0);
static atomic_t vsc_rewritten = ATOMIC_INIT(0);
static atomic_t as_sdp_cleared = ATOMIC_INIT(0);

static bool transcoder_a_is_edp(void)
{
	return (readl(regs + TRANS_DDI_FUNC_CTL_A) & TGL_TRANS_DDI_PORT_MASK) == TGL_TRANS_DDI_PORT_A;
}

static int msa_return(struct kretprobe_instance *ri, struct pt_regs *pt)
{
	u32 msa;

	if (!transcoder_a_is_edp())
		return 0;
	msa = readl(regs + TRANS_MSA_MISC_A);
	if (msa & DP_MSA_MISC_COLOR_VSC_SDP) {
		writel(msa & ~DP_MSA_MISC_COLOR_VSC_SDP, regs + TRANS_MSA_MISC_A);
		atomic_inc(&msa_cleared);
	}
	return 0;
}

static struct kretprobe msa_probe = {
	.kp.symbol_name = "intel_ddi_set_dp_msa",
	.handler = msa_return,
	.maxactive = 4,
};

struct infoframe_call {
	u32 header;
	bool vsc;
};

static int infoframe_entry(struct kretprobe_instance *ri, struct pt_regs *pt)
{
	struct infoframe_call *call = (struct infoframe_call *)ri->data;

	/* hsw_write_infoframe(encoder, crtc_state, type, frame, len) */
	call->vsc = (unsigned int)pt->dx == DP_SDP_VSC && pt->cx && (long)pt->r8 >= 4;
	if (call->vsc)
		call->header = *(const u32 *)pt->cx;
	return 0;
}

static int infoframe_return(struct kretprobe_instance *ri, struct pt_regs *pt)
{
	struct infoframe_call *call = (struct infoframe_call *)ri->data;

	if (!call->vsc || !transcoder_a_is_edp())
		return 0;
	if (!(readl(regs + VIDEO_DIP_CTL_A) & VIDEO_DIP_ENABLE_VSC))
		return 0;
	if (readl(regs + VIDEO_DIP_VSC_DATA_A) != call->header)
		return 0;
	writel(call->header, regs + VIDEO_DIP_VSC_DATA_A);
	readl(regs + VIDEO_DIP_CTL_A);
	atomic_inc(&vsc_rewritten);
	return 0;
}

static struct kretprobe infoframe_probe = {
	.kp.symbol_name = "hsw_write_infoframe",
	.entry_handler = infoframe_entry,
	.handler = infoframe_return,
	.data_size = sizeof(struct infoframe_call),
	.maxactive = 4,
};

static int dpcd_write_entry(struct kprobe *p, struct pt_regs *pt)
{
	/* drm_dp_dpcd_write(aux, offset, buffer, size); aux->name is the first member */
	const char *name = *(const char **)pt->di;
	u8 *buf = (u8 *)pt->dx;

	if ((unsigned int)pt->si != DP_DOWNSPREAD_CTRL || !pt->cx || !buf)
		return 0;
	if (!name || strncmp(name, "AUX A/", 6))
		return 0;
	if (buf[0] & DP_FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE) {
		buf[0] &= ~DP_FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE;
		atomic_inc(&as_sdp_cleared);
	}
	return 0;
}

static struct kprobe dpcd_write_probe = {
	.symbol_name = "drm_dp_dpcd_write",
	.pre_handler = dpcd_write_entry,
};

static int counters_get(char *buffer, const struct kernel_param *kp)
{
	return sysfs_emit(buffer, "%d %d %d\n", atomic_read(&msa_cleared), atomic_read(&vsc_rewritten),
			  atomic_read(&as_sdp_cleared));
}

static const struct kernel_param_ops counters_ops = {
	.get = counters_get,
};
module_param_cb(counters, &counters_ops, NULL, 0444);
MODULE_PARM_DESC(counters, "MSA colorimetry bits cleared, VSC headers written again, AS SDP PR bits cleared");

static int __init xehdrfix_init(void)
{
	struct pci_dev *pdev = pci_get_domain_bus_and_slot(0, 0, PCI_DEVFN(2, 0));
	int err;

	if (!pdev || pdev->vendor != PCI_VENDOR_ID_INTEL ||
	    !(pci_resource_flags(pdev, 0) & IORESOURCE_MEM)) {
		pci_dev_put(pdev);
		pr_err("xehdrfix: no Intel GPU at 00:02.0\n");
		return -ENODEV;
	}
	regs = ioremap(pci_resource_start(pdev, 0) + DISPLAY_WINDOW, 0x1000);
	pci_dev_put(pdev);
	if (!regs)
		return -ENOMEM;
	err = register_kretprobe(&msa_probe);
	if (err)
		goto unmap;
	err = register_kretprobe(&infoframe_probe);
	if (err)
		goto unregister_msa;
	err = register_kprobe(&dpcd_write_probe);
	if (err)
		goto unregister_infoframe;
	pr_info("xehdrfix: eDP MSA colorimetry bit off, VSC header written again after DIP updates, no fixed vtotal AS SDP in PR active\n");
	return 0;

unregister_infoframe:
	unregister_kretprobe(&infoframe_probe);
unregister_msa:
	unregister_kretprobe(&msa_probe);
unmap:
	iounmap(regs);
	pr_err("xehdrfix: xe functions not found (%d)\n", err);
	return err;
}

static void __exit xehdrfix_exit(void)
{
	unregister_kprobe(&dpcd_write_probe);
	unregister_kretprobe(&infoframe_probe);
	unregister_kretprobe(&msa_probe);
	iounmap(regs);
}

module_init(xehdrfix_init);
module_exit(xehdrfix_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("xe eDP: PQ HDR with Panel Replay (MSA colorimetry bit, AS SDP timing) and VSC SDP ECC");
