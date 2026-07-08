# WinMint SVG Asset Set

## Contents

- `readme/winmint_hero_dark.svg` - GitHub README hero for dark mode.
- `readme/winmint_hero_light.svg` - GitHub README hero for light mode.
- `web/winmint_hero_dark.svg` - Responsive web lockup for dark backgrounds.
- `web/winmint_hero_light.svg` - Responsive web lockup for light backgrounds.
- `web/winmint_hero_adaptive.svg` - Single responsive SVG with internal `prefers-color-scheme` styling.
- `app/winmint_lockup_dark.svg` - In-app full lockup for dark surfaces.
- `app/winmint_lockup_light.svg` - In-app full lockup for light surfaces.
- `app/winmint_icon_color.svg` - Square full-color app icon SVG, 1024x1024 intrinsic size.
- `app/winmint_icon_mono_currentcolor.svg` - Monochrome icon using `currentColor` for toolbar/sidebar use.
- `app/winmint_icon_white.svg` - White icon for dark/chrome overlays.
- `source/winmint_hero_dark_source.svg` - readable source copy of the current dark hero.

## GitHub README usage

Use the two README files with a `<picture>` block:

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./assets/brand/readme/winmint_hero_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="./assets/brand/readme/winmint_hero_light.svg">
    <img src="./assets/brand/readme/winmint_hero_light.svg" alt="WinMint" width="720">
  </picture>
</p>
```

The fallback image is the light version because it is safest on a default white GitHub README background.

## Web usage

Recommended production web usage:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="/assets/brand/web/winmint_hero_dark.svg">
  <img class="brand-logo" src="/assets/brand/web/winmint_hero_light.svg" alt="WinMint">
</picture>
```

```css
.brand-logo {
  width: min(100%, 720px);
  height: auto;
}
```

You can also use `web/winmint_hero_adaptive.svg` as a single file, but separate light/dark SVGs are easier to debug and more reliable across markdown renderers.

## In-app / wizard notes

Use:

- `app/winmint_icon_color.svg` for app identity, splash/about surfaces, or places that need the full-color mark.
- `app/winmint_icon_mono_currentcolor.svg` for toolbar/sidebar icons when the UI theme should control the color.
- `app/winmint_lockup_dark.svg` on dark surfaces.
- `app/winmint_lockup_light.svg` on light surfaces.

For OS-level app icons, you will likely still generate platform raster/container assets from `app/winmint_icon_color.svg` later, such as PNG, ICO, and ICNS.
