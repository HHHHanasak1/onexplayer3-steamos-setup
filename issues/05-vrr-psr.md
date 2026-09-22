## Summary

With VRR (adaptive sync) enabled in the Quick Access menu, the internal panel never runs above ~74 fps, and after a few VRR/refresh-rate toggles it degrades to a flat 30 fps for every game until the next mode set. With VRR off the same games reach 144 fps. The fix pack does not touch VRR; this issue documents the behaviour so it can be reported upstream (xe / gamescope) and so users know to leave VRR off.

## Environment

- ONEXPLAYER 3, Intel Core Ultra (Panther Lake), Arc B390, driver `xe`
- SteamOS 3.10 (20260921.1000), kernel `7.2.4-valve1-1-neptune-72`, gamescope 3.16.26
- Panel Samsung AMS881KB01-0, 1920x1200, EDID range limits 30-144 Hz, `vrr_capable`
- PSR enabled (kernel default)

## Observations

1. **Every game** is capped at roughly half the refresh rate with VRR on (user-verified on screen with several titles: ~70-74 fps with VRR on, 144 with VRR off).
2. Measured with an instrumented Mesa WSI (`vkQueuePresentKHR` counter) while a game with XeSS frame generation presented in bursts of 4: presents complete in the pattern `6.94, 6.94, 6.94, 33.3 ms` -> 73.8 presents/s. `vkQueuePresentKHR` itself never blocks; all the waiting is `vkAcquireNextImageKHR` (gamescope releasing the previous scanout image), i.e. page-flip completion.
3. The 33.3 ms equals the panel's VRR floor (30 Hz). Flips that were queued before the frame reached vmin (6.94 ms) complete at vmin; a flip that arrives after vmin does not terminate the frame early but waits for vmax (33.3 ms). So adaptive sync is not actually adapting: the hardware only switches at vmin multiples or at vmax.
4. After several VRR on/off and 144/120 Hz switches (Quick Access menu), the panel got into a state where **every** flip waited 33.3 ms: 30 fps in all games, until a mode set (refresh-rate change or sleep/wake).
5. Every VRR toggle logs in the kernel:
   ```
   xe 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
   xe 0000:00:02.0: [drm] *ERROR* Timed out waiting PSR idle state   (x2-4)
   ```
   Occasionally the panel then freezes except for a strip at the top (PSR stuck in partial update). Recovery: sleep/wake or a refresh-rate change.
6. Nothing on the gamescope side changes the result: allow-tearing, `GAMESCOPE_FPS_LIMIT`, `drm_debug_disable_in_fence_fd`, `drm_debug_disable_explicit_sync`, `adaptive_sync_ignore_overlay`, more swapchain images, present mode overrides, an extra overlay client presenting at 144 Hz. The app's own pacing (XeSS-FG pacer) does not matter either.

## Workaround

Turn VRR off in the Quick Access menu and leave it off. Switch it only while no game is running (the switch itself trips the PSR timeout above). Do not toggle it from scripts at runtime.

## Notes for an upstream report

- Suspect: xe VRR flipline / push handling on Panther Lake (frames only end at vmin or vmax), plus VRR<->PSR transitions timing out.
- Reproducer: any Vulkan client presenting slower than the refresh rate under gamescope with VRR on; or a game with frame generation (bursty presents), measured with `ANV_WSI_FPS`-style present counting.
- `xe.enable_psr=0` was not tried (PSR intentionally kept on).
