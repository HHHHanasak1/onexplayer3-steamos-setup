#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/slab.h>
#include <linux/mm.h>
#include <linux/string.h>
#include <linux/vmalloc.h>
#include <linux/llist.h>
#include <linux/workqueue.h>

#define XE_TILES 2
#define PT_OPS_BASE 48
#define PT_OPS_STRIDE 72
#define PT_OPS_NUM_OPS 56
#define PT_UPDATE_OP_SIZE 384

static const u8 alloc_signature[] = {
	0x48, 0x8d, 0xaf, 0xc0, 0x00, 0x00, 0x00,
	0x53,
	0x48, 0x8d, 0x5f, 0x30,
	0x8b, 0x43, 0x38,
	0x85, 0xc0,
	0x74, 0x1a,
	0x48, 0x8d, 0x3c, 0x40,
	0xbe, 0xc0, 0x6c, 0x00, 0x00,
	0x48, 0xc1, 0xe7, 0x07,
};
#define ALLOC_SIGNATURE_OFFSET 0x0f

static const u8 fini_free_signature[] = {
	0x48, 0x8b, 0x7d, 0x30, 0xe8,
};
#define FINI_FREE_SIGNATURE_OFFSET 0x77
static const u8 fini_free2_signature[] = {
	0x48, 0x8b, 0x7d, 0x78,
};
#define FINI_FREE2_SIGNATURE_OFFSET 0x80

static LLIST_HEAD(deferred_frees);

static void free_deferred(struct work_struct *work)
{
	struct llist_node *node, *next;

	llist_for_each_safe(node, next, llist_del_all(&deferred_frees))
		vfree(node);
}
static DECLARE_WORK(deferred_free_work, free_deferred);

static void **tile_ops(void *vops, int tile)
{
	return (void **)((u8 *)vops + PT_OPS_BASE + tile * PT_OPS_STRIDE);
}

static u32 tile_num_ops(void *vops, int tile)
{
	return *(u32 *)((u8 *)vops + PT_OPS_BASE + tile * PT_OPS_STRIDE + PT_OPS_NUM_OPS);
}

static atomic64_t large_allocations = ATOMIC64_INIT(0);
static atomic_t largest_num_ops = ATOMIC_INIT(0);

static noinline int xevmafix_ops_alloc(void *vops, bool array_of_binds)
{
	int tile;

	for (tile = 0; tile < XE_TILES; tile++) {
		u32 num_ops = tile_num_ops(vops, tile);
		void **ops = tile_ops(vops, tile);

		if (!num_ops)
			continue;
		if ((size_t)num_ops * PT_UPDATE_OP_SIZE > KMALLOC_MAX_CACHE_SIZE) {
			atomic64_inc(&large_allocations);
			if (num_ops > atomic_read(&largest_num_ops))
				atomic_set(&largest_num_ops, num_ops);
		}
		*ops = kvmalloc_array(num_ops, PT_UPDATE_OP_SIZE,
				      GFP_KERNEL | __GFP_RETRY_MAYFAIL | __GFP_NOWARN);
		if (!*ops)
			return array_of_binds ? -ENOBUFS : -ENOMEM;
	}
	return 0;
}

static int alloc_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	instruction_pointer_set(regs, (unsigned long)xevmafix_ops_alloc);
	return 1;
}

static int fini_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	void *vops = (void *)regs->di;
	bool queued = false;
	int tile;

	for (tile = 0; tile < XE_TILES; tile++) {
		void **ops = tile_ops(vops, tile);

		if (*ops && is_vmalloc_addr(*ops)) {
			llist_add((struct llist_node *)*ops, &deferred_frees);
			*ops = NULL;
			queued = true;
		}
	}
	if (queued)
		schedule_work(&deferred_free_work);
	return 0;
}

static struct kprobe alloc_probe = {
	.symbol_name = "xe_vma_ops_alloc",
	.pre_handler = alloc_pre_handler,
};

static struct kprobe fini_probe = {
	.symbol_name = "xe_vma_ops_fini",
	.pre_handler = fini_pre_handler,
};

static bool code_matches(unsigned long function, unsigned long offset, const u8 *expected, size_t length)
{
	return !memcmp((const void *)(function + offset), expected, length);
}

static bool is_endbr64(unsigned long address)
{
	static const u8 endbr64[] = { 0xf3, 0x0f, 0x1e, 0xfa };
	static const u8 sealed_endbr64[] = { 0x0f, 0x1f, 0x40, 0xd6 };

	return !memcmp((const void *)address, endbr64, sizeof(endbr64)) ||
	       !memcmp((const void *)address, sealed_endbr64, sizeof(sealed_endbr64));
}

static unsigned long resolve(const char *name)
{
	struct kprobe probe = { .symbol_name = name };
	unsigned long address;

	if (register_kprobe(&probe))
		return 0;
	address = (unsigned long)probe.addr;
	unregister_kprobe(&probe);
	if (!is_endbr64(address) && is_endbr64(address - 4))
		address -= 4;
	return address;
}

static int large_allocations_get(char *buffer, const struct kernel_param *kp)
{
	return sysfs_emit(buffer, "%lld %d\n", atomic64_read(&large_allocations),
			  atomic_read(&largest_num_ops));
}

static const struct kernel_param_ops large_allocations_ops = {
	.get = large_allocations_get,
};
module_param_cb(large_allocations, &large_allocations_ops, NULL, 0444);

static int __init xevmafix_init(void)
{
	unsigned long alloc_address = resolve("xe_vma_ops_alloc");
	unsigned long fini_address = resolve("xe_vma_ops_fini");
	int err;

	if (!alloc_address || !fini_address) {
		pr_err("xevmafix: xe functions not found\n");
		return -ENOENT;
	}
	if (!code_matches(alloc_address, ALLOC_SIGNATURE_OFFSET, alloc_signature, sizeof(alloc_signature)) ||
	    !code_matches(fini_address, FINI_FREE_SIGNATURE_OFFSET, fini_free_signature, sizeof(fini_free_signature)) ||
	    !code_matches(fini_address, FINI_FREE2_SIGNATURE_OFFSET, fini_free2_signature, sizeof(fini_free2_signature))) {
		pr_err("xevmafix: xe code does not match the expected build, refusing\n");
		return -EINVAL;
	}
	err = register_kprobe(&fini_probe);
	if (err)
		return err;
	err = register_kprobe(&alloc_probe);
	if (err) {
		unregister_kprobe(&fini_probe);
		return err;
	}
	pr_info("xevmafix: xe_vma_ops_alloc uses kvmalloc\n");
	return 0;
}

module_init(xevmafix_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("xe: allocate VMA rebind op arrays with kvmalloc");
