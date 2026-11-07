#!/usr/bin/env bash
# Calamares menude "Install System"/"Sistemi Yukle" adiyla Sistem kategorisinde duruyordu (bulunmasi zor).
# Her dilde "atasOS Kur" (canli ortamdaki masaustu kisayoluyla ayni ad). Eski dosya yedeklenir.
# Kullanim: sudo bash /home/eren/atasos-55-calamares-menu.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
A=/mnt/atasos
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
trap 'sync; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"' EXIT
F=$A/usr/share/applications/calamares.desktop
[ -f "$F" ] || { echo "HATA: ${F#$A} yok"; exit 1; }
[ -x $A/usr/bin/calamares ] && echo "  /usr/bin/calamares: var ($(stat -c%s $A/usr/bin/calamares) bayt)" || echo "  /usr/bin/calamares: YOK <<<"
cp -a "$F" "$F.yedek-$(date +%m%d-%H%M)"
# tum Name/GenericName/Comment cevirilerini kaldir, tek ad birak
sed -i -E '/^(Name|GenericName|Comment)\[/d; s/^Name=.*/Name=atasOS Kur/; s/^GenericName=.*/GenericName=Kurulum Programı/; s/^Comment=.*/Comment=atasOS'"'"'u bu bilgisayara kur (Calamares)/' "$F"
grep -q '^Keywords=' "$F" && sed -i 's/^Keywords=.*/Keywords=calamares;kurulum;kur;install;installer;atasos;/' "$F"
echo "  $(grep -E '^(Name|GenericName|Exec|Icon|Categories|Keywords)=' "$F" | tr '\n' ' ')"
rm -f $A/home/eren/.cache/ksycoca6_* 2>/dev/null
echo "  Bitti. atasOS'ta oturumu yeniden acinca menude (Sistem) ve aramada 'atasOS Kur'."
