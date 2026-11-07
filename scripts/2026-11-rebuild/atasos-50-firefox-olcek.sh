#!/usr/bin/env bash
# Firefox (GTK) cift olcekleniyor: GDK_SCALE=2 + Xft.dpi=192. Grup B'de xrdb kurulunca Xft.dpi de uygulanmaya basladi
# -> yazilar 4x. GDK_DPI_SCALE=0.5 DPI'dan gelen ikinci buyutmeyi geri alir (GDK_SCALE=2 kalir).
# Kullanim: sudo bash /home/eren/atasos-50-firefox-olcek.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
trap 'cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"' EXIT
F=$A/home/eren/.config/plasma-workspace/env/atasos-olcek.sh
[ -f "$F" ] || { echo "HATA: ${F#$A} yok"; exit 1; }
echo "  --- once (${F#$A}) ---"; sed 's/^/    /' "$F"
cp -a "$F" "$F.yedek-$(date +%m%d-%H%M)"
if grep -q 'GDK_DPI_SCALE' "$F"; then sed -i 's/^export GDK_DPI_SCALE=.*/export GDK_DPI_SCALE=0.5/' "$F"
else echo 'export GDK_DPI_SCALE=0.5   # GDK_SCALE=2 + Xft.dpi=192 cift olceklemesini dengeler (Firefox/GTK)' >> "$F"; fi
echo "  --- sonra ---"; sed 's/^/    /' "$F"
echo "  --- Firefox kullanici ayari (devPixelsPerPx varsa ayrica olcekler) ---"
grep -h 'devPixelsPerPx' $A/home/eren/.mozilla/firefox/*/prefs.js $A/home/eren/.mozilla/firefox/*/user.js 2>/dev/null | sed 's/^/    /' || true
grep -rhs 'devPixelsPerPx' $A/home/eren/.mozilla/firefox/*/prefs.js $A/home/eren/.mozilla/firefox/*/user.js >/dev/null || echo "    yok (iyi)"
sync
echo "  Bitti. atasOS'ta oturumu kapatip ac (ya da yeniden baslat): Firefox normal boyuta donmeli."
