# icon/

Apple Bridge mark. Source of truth for art lives here.

| Kind | Path | Role |
|------|------|------|
| Preview | `previews/mark.jpg` | Raster source for the tracer |
| Vector | `vectors/mark.svg` | Potrace of the preview (`just gen-icon-svg`) |
| Icon Composer | `AppIcon.icon/` | Dock / app icon (authored; do not re-export). Copied to `AppleBridge/AppIcon.icon` for Xcode. |
| Menu bar | `AppleBridge/Assets.xcassets/MenuBarMark.imageset` | Template PNGs from the SVG (`just gen-menubar-icons`) |
| README | `mark.png`, `mark-dark.png` | Light / dark AppIcon tiles for the GitHub header |

Requires `magick` and `potrace` (`brew install imagemagick potrace`).
