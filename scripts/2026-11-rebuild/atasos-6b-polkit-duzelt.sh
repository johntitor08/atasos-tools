#!/usr/bin/env bash
# polkit dizin sahipliklerini BLFS standardina getir. Kucuk duzeltme.
# Kullanim: sudo bash /home/eren/atasos-6b-polkit-duzelt.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
mountpoint -q $A || mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
[ -d "$A/etc/polkit-1" ] || { echo "HATA: /etc/polkit-1 yok"; exit 1; }

echo "--- once ---"
ls -lnd "$A/etc/polkit-1" "$A/etc/polkit-1/rules.d" | sed 's/^/  /'

chown 0:0   "$A/etc/polkit-1"          && chmod 755 "$A/etc/polkit-1"
chown 27:27 "$A/etc/polkit-1/rules.d"  && chmod 700 "$A/etc/polkit-1/rules.d"

echo
echo "--- sonra (beklenen: 0 0 / 27 27) ---"
ls -lnd "$A/etc/polkit-1" "$A/etc/polkit-1/rules.d" | sed 's/^/  /'

T=0
[ "$(stat -c '%u:%g:%a' "$A/etc/polkit-1")"         = "0:0:755"   ] || { echo "  /etc/polkit-1 YANLIS <<<"; T=1; }
[ "$(stat -c '%u:%g:%a' "$A/etc/polkit-1/rules.d")" = "27:27:700" ] || { echo "  rules.d YANLIS <<<"; T=1; }
sync
echo
[ "$T" -eq 0 ] && echo "TAMAM. Artik yeniden baslatabilirsin." || echo "SORUN VAR."
