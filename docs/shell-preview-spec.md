# Shell Preview Asset Spec

Reference assets for shell-layer previews. The current compact wizard loads the
small tile icons from `assets\shell\<layer>.png`; full preview screenshots are
kept only when they are actually consumed by validation or a future preview
surface.

## File locations

```
assets\shell\windhawk\preview.png
```

## Canvas

- **Size:** 960 × 540 px (half of 1920 × 1080, so a 1:1 screen capture at 1080p halved)
- **Background:** actual Windows 11 Bloom wallpaper on all four images
- **No open application windows** needed for Standard, Windhawk, or YASB — they modify shell chrome only, not window management

## Per-option composition

### Standard
Bloom wallpaper + default Windows 11 taskbar composited at bottom.
Taskbar chrome height in the asset: **72–80 px** (1.5–2× the ~40 px real height) so it reads clearly at thumbnail scale.

### Windhawk
Same as Standard but with the Windhawk-modified taskbar.
Same scale rule: 72–80 px tall in the asset.

### YASB (Yet Another Status Bar)
Bloom wallpaper + YASB status strip at top + default taskbar at bottom.
Both bars composited at 72–80 px tall in the asset.
No open windows needed.

### Komorebi
Bloom wallpaper + 3–4 tiled windows with visible gaps and borders filling ~70 % of the frame.
Wallpaper remains visible through the gaps — that's the point.
No bar-height scaling needed; the tiled windows are the visible feature.

## Authoring notes

Capture source at 1920 × 1080 (real desktop or exact-size Figma/PS canvas), then downscale to 960 × 540.
When compositing bars from a real screenshot they will be ~40 px; scale them up to ~72–80 px in the asset before flattening.
Export as PNG (lossless; the images are small).
