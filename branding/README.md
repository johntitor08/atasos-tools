# atasOS branding and desktop files

| Path | Installed to | Notes |
|------|--------------|-------|
| `logo/atasos.svg`, `logo/atasos-*.png` | `/usr/share/icons/hicolor/<size>/apps/atasos.png`, `scalable/apps/atasos.svg` | Icon name `atasos`; also `LOGO=atasos` in os-release |
| `sddm-atasOS/` | `/usr/share/sddm/themes/atasOS/` | Login theme: Turkish on-screen keyboard (Qt Virtual Keyboard, `tr_TR`), scales itself to 2x at 170 dpi or more, clock, reboot/power off |
| `calamares/show.qml` | `/etc/calamares/branding/atasos/show.qml` | Installer slideshow (Turkish) |
| `plasma/atasos-hidpi.sh` | `/etc/xdg/plasma-workspace/env/atasos-hidpi.sh` | Reads the panel's EDID; at 170 dpi or more sets Qt, GTK and cursor scale to 2x for X11 Plasma sessions. Skipped when the user picked a scale in System Settings. Override with `OLCEK=1`, `2` or `otomatik` in `~/.config/atasos-olcek` or `/etc/atasos/olcek`. |

The logo PNGs are rendered from `atasos.svg` with librsvg.
