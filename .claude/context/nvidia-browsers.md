# NVIDIA and browser problems

Relevant to any NVIDIA-only installer step. None of these fixes are in the
installer yet (see `backlog.md`).

## Never enable Chrome's Vulkan flag (Wayland + NVIDIA)

- Every Chrome window, including `--app` windows, renders transparent or
  blank. Chrome logs `'--ozone-platform=wayland' is not compatible with
  Vulkan`.
- Recovery: start `google-chrome-stable --no-experiments`, or, with Chrome
  closed, remove the entry from `browser.enabled_labs_experiments` in
  `~/.config/google-chrome/Local State`.

## Black video, audio plays (Chrome/Brave)

- NVIDIA has no VA-API, so Chrome decodes video in software, then copies the
  frames into GPU memory buffers. Those fail on NVIDIA under Wayland, so some
  sites (AV1 or H.264 through MSE) show black video.
- **Fix:** `--disable-gpu-memory-buffer-video-frames` in
  `~/.config/chrome-flags.conf` (Brave reads `~/.config/brave-flags.conf`).
  Check it in the Command Line row of `chrome://version`.
- XWayland (`--ozone-platform=x11`) also works.
  `--disable-features=WaylandOverlayDelegation` wasn't needed.

## WebKitGTK apps

- Apps such as the Modrinth App need `WEBKIT_DISABLE_DMABUF_RENDERER=1` on
  NVIDIA.
