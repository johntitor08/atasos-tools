#!/usr/bin/env bash
# 1) Menude bos Firefox simgesi: ~/.local/share/applications/userapp-Firefox-*.desktop'ta Icon satiri yok -> Icon=firefox.
# 2) Arayuz Ingilizce: LANGUAGE=tr_TR.UTF-8 gecersiz (LANGUAGE yalniz dil adi alir) -> tr_TR:tr;
#    plasma-localerc: [Formats] LANG=tr_TR.UTF-8, [Translations] LANGUAGE=tr.
# Degisen her dosya once .yedek-<tarih> olarak kopyalanir.
# Kullanim: sudo bash /home/eren/atasos-54-firefox-simge-dil.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
A=/mnt/atasos; H=$A/home/eren; TS=$(date +%m%d-%H%M)
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
trap 'sync; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"' EXIT
yedek(){ cp -a "$1" "$1.yedek-$TS"; }

echo "########## 1/2  FIREFOX SIMGESI ##########"
for f in $H/.local/share/applications/userapp-*irefox*.desktop; do
    [ -f "$f" ] || continue
    if grep -q '^Icon=.' "$f"; then echo "  ${f#$A}: zaten $(grep -m1 '^Icon=' "$f")"; continue; fi
    yedek "$f"
    if grep -q '^Icon=' "$f"; then sed -i 's/^Icon=.*/Icon=firefox/' "$f"; else sed -i '/^\[Desktop Entry\]/a Icon=firefox' "$f"; fi
    echo "  ${f#$A}: Icon=firefox eklendi"
done
rm -f $H/.cache/ksycoca6_* $H/.cache/icon-cache.kcache 2>/dev/null

echo
echo "########## 2/2  DIL ##########"
for f in $H/.bash_profile $H/.profile $H/.bashrc $H/.config/plasma-workspace/env/*.sh $A/etc/profile.d/*.sh $A/etc/environment; do
    [ -f "$f" ] || continue; case "$f" in *.yedek-*) continue;; esac
    grep -qE '^\s*(export\s+)?LANGUAGE=' "$f" || continue
    echo "  ${f#$A}: $(grep -E '^\s*(export\s+)?LANGUAGE=' "$f" | head -1)"
    if grep -qE '^\s*(export\s+)?LANGUAGE=["]?[a-z][a-z]_[A-Z][A-Z]\.' "$f"; then
        yedek "$f"; sed -i -E 's/^(\s*(export\s+)?LANGUAGE=)["]?([a-z][a-z])_([A-Z][A-Z])\.[A-Za-z0-9-]+["]?/\1\3_\4:\3/' "$f"
        echo "     -> $(grep -E '^\s*(export\s+)?LANGUAGE=' "$f" | head -1)"
    fi
done
P=$H/.config/plasma-localerc
[ -f "$P" ] && yedek "$P"
python3 -I - "$P" <<'PY'
import sys,configparser,os
p=sys.argv[1]; c=configparser.RawConfigParser(); c.optionxform=str
if os.path.exists(p): c.read(p)
for s,k,v in (("Formats","LANG","tr_TR.UTF-8"),("Translations","LANGUAGE","tr")):
    if not c.has_section(s): c.add_section(s)
    c.set(s,k,v)
with open(p,"w") as f: c.write(f, space_around_delimiters=False)
PY
chown $(stat -c %u:%g $H) "$P"
echo "  plasma-localerc: $(tr '\n' ' ' < $P)"
echo
echo "  Bitti. atasOS'ta oturumu kapatip ac: arayuz Turkce, menude Firefox simgesi gorunmeli."
echo "  Ingilizce istersen: Sistem Ayarlari -> Bolge ve Dil."
