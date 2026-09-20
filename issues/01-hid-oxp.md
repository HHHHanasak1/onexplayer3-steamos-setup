# hid-oxp: NULL pointer dereference in oxp_rgb_status_store() on driver rebind; LED sysfs is a no-op on ONEXPLAYER 3 (MCU 1a86:fe00 fw 1.55)

**Target:** Valve linux-neptune kernel 7.2.0-valve1-1-neptune-72 (`drivers/hid/hid-oxp.c`, author Derek J. Clark) / SteamOS 3.10 main 20260827.1000
**Device:** ONE-NETBOOK ONEXPLAYER 3 (Panther Lake, BIOS 5.09). MCU USB 1a86:fe00 bcdDevice 1.55, 3 HID interfaces (kbd, mouse, 64-byte vendor page 0xFF00). Gamepad enumerates separately as 045e:028e (xpad).

hid-oxp binds all three interfaces and exposes `/sys/class/leds/oxp:rgb:joystick_rings` (multicolor 0-100, `effect` list incl. `monocolor`, `enabled`, `speed`) plus `gamepad_mode` (xinput|debug), `button_*` mapping and `rumble_intensity`.

1. **LED writes have no effect.** `multi_intensity`, `brightness`, `enabled=true`, `effect=monocolor` are accepted (no error, nothing in dmesg) but the rings never change; `effect` reads back the firmware preset (`sea_foam`) after writing `monocolor`. The lights are lit by firmware, so the MCU's lighting works; the gen-2 RGB commands appear to be ignored by this firmware (or RGB lives on the gamepad MCU on this generation). `button_m1/m2` mapping attributes also show no visible effect.
2. **Reproducible Oops on rebind:** unbind `0003:1A86:FE00.0001/.0002/.0003` from hid-oxp, bind hid-generic, unbind, bind hid-oxp again ->
   `Oops: general protection fault, kernel NULL pointer dereference 0xa ... Workqueue: events oxp_rgb_queue_fn [hid_oxp] ... RIP: oxp_rgb_status_store+0x23/0x120 [hid_oxp]` followed by `BUG: unable to handle page fault ... #PF: supervisor write access`. The RGB work item seems to run before the per-device RGB state is initialised (or after it was freed). Full trace: `hid_oxp_oops_rebind.txt`.
3. Boot noise: `workqueue: work func oxp_mcu_init_fn [hid_oxp] enqueued on deprecated workqueue`.

Attachments: hid_oxp_oops_rebind.txt, rgb_mcu_usb_descriptor.txt, rgb_gamepad_usb.txt, LED sysfs test logs.
