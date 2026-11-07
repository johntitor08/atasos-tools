#!/usr/bin/env bash
# PowerDevil kuruldu ama dogrulamada parlaklik yardimcisi (KAuth helper / D-Bus / polkit / systemd user unit) gorunmedi.
# 1) cmake'in install_manifest.txt'sinden paketin dosya listesini geri uretir (atasos-39 kaymasinda silindi).
# 2) Parlaklik icin gereken parcalarin NEREYE kuruldugunu gosterir. Sistem dosyalarina dokunmaz.
# Kullanim: sudo bash /home/eren/atasos-40-powerdevil-kontrol.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi calisiyor. O bitince tekrar calistir."; exit 1; }
A=/mnt/atasos
mkdir -p $A
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
trap 'umount $A 2>/dev/null' EXIT

M=$A/sources/atasos-B/powerdevil-6.3.4/build/install_manifest.txt
echo "########## 1/3  DOSYA LISTESI ##########"
if [ -f "$M" ]; then
    sed 's|^/tmp/stage-powerdevil||' "$M" | sort -u > $A/var/lib/atasos-paketler/powerdevil.list
    echo "  install_manifest'ten $(wc -l < $A/var/lib/atasos-paketler/powerdevil.list) dosya -> /var/lib/atasos-paketler/powerdevil.list"
    yok=0; while read -r f; do [ -e "$A$f" ] || [ -L "$A$f" ] || yok=$((yok+1)); done < $A/var/lib/atasos-paketler/powerdevil.list
    echo "  listede olup sistemde OLMAYAN: $yok"
else
    echo "  install_manifest.txt yok: $M"
fi
L=$A/var/lib/atasos-paketler/powerdevil.list

echo
echo "########## 2/3  PARLAKLIK PARCALARI ##########"
for k in 'backlighthelper' 'dbus-1/system' 'polkit-1' 'systemd/user' 'autostart' 'kauth' 'discretegpuhelper' 'chargethreshold' 'brightness'; do
    printf '  --- %s ---\n' "$k"
    grep -i "$k" "$L" 2>/dev/null | head -6 | sed 's/^/    /' || true
done

echo
echo "########## 3/3  KAuth ALTYAPISI ##########"
ls -la $A/usr/lib64/libexec/kauth/ $A/usr/libexec/kauth/ $A/usr/lib/libexec/kauth/ 2>/dev/null | sed 's/^/  /'
echo "  --- sistemde kurulu diger KAuth yardimcilari (ornek) ---"
ls $A/usr/share/dbus-1/system-services/ 2>/dev/null | grep -i kde | head -8 | sed 's/^/    /'
ls $A/usr/share/polkit-1/actions/ 2>/dev/null | grep -i kde | head -8 | sed 's/^/    /'
echo "  --- PowerDevil'in derleme ozeti (KAuth / logind) ---"
grep -iE 'kauth|logind|backlight|ddcutil|Found|NOT found|disabled' $A/sources/atasos-B/powerdevil-6.3.4/build/CMakeCache.txt 2>/dev/null | grep -iE 'KAUTH|BACKLIGHT|DDCUTIL|LOGIND' | head -10 | sed 's/^/    /'
sync
