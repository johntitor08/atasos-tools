# atasOS branding and desktop files

| Path | Installed to | Notes |
|------|--------------|-------|
| `logo/atasos.svg`, `logo/atasos-*.png` | `/usr/share/icons/hicolor/<size>/apps/atasos.png`, `scalable/apps/atasos.svg` | Icon name `atasos`; also `LOGO=atasos` in os-release |
| `sddm-atasOS/` | `/usr/share/sddm/themes/atasOS/` | Login theme: Turkish on-screen keyboard (Qt Virtual Keyboard, `tr_TR`), scales itself to 2x at 170 dpi or more, clock, reboot/power off |
| `calamares/show.qml` | `/etc/calamares/branding/atasos/show.qml` | Installer slideshow (Turkish) |
| `plasma/atasos-hidpi.sh` | `/etc/xdg/plasma-workspace/env/atasos-hidpi.sh` | Reads the panel's EDID; at 170 dpi or more sets Qt, GTK and cursor scale to 2x for X11 Plasma sessions. Skipped when the user picked a scale in System Settings. Override with `OLCEK=1`, `2` or `otomatik` in `~/.config/atasos-olcek` or `/etc/atasos/olcek`. |

| `wallpaper/atasOS/` (from `wallpaper/atasos-duvar.svg`) | `/usr/share/wallpapers/atasOS/` | Default desktop, lock screen and login background (8 sizes, JPEG). Made the default through the desktop themes' `plasmarc` (`defaultWallpaperTheme`) and the Breeze look-and-feel `defaults` (`[Wallpaper] Image`) |
| `grub-atasos/` | `/usr/share/grub/themes/atasos/` | GRUB theme; the `.pf2` fonts are generated on the target with `grub-mkfont` from DejaVu Sans |

The logo PNGs and wallpaper are rendered from the SVGs with librsvg.
