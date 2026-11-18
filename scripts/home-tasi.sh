#!/bin/bash
# atasOS: /home'u 99,8 GB'lık p5 bölümüne ("atasOS" etiketli) taşır.
#
# - p5 /mnt/atasos'a bağlanır (içindeki mevcut dosyalara dokunulmaz).
# - /home, /mnt/atasos/home-kurulu'ya kopyalanır ve oradan /home'a bind edilir.
# - Kökteki eski /home SİLİNMEZ; yeni düzen doğrulandıktan sonra elle silinir.
#
# En iyisi masaüstü oturumunu kapatıp bir TTY'den (Ctrl+Alt+F3) çalıştırmak:
#   sudo bash home-tasi.sh
# Bittikten sonra: sudo reboot

set -euo pipefail

P5=/dev/disk/by-partuuid/524c28d4-f588-4154-b586-6654380d7f22
MNT=/mnt/atasos
HEDEF=$MNT/home-kurulu

[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştır: sudo bash $0"; exit 1; }
[ -b "$P5" ] || { echo "p5 bulunamadı: $P5"; exit 1; }
[ "$(lsblk -no FSTYPE "$P5")" = ext4 ] || { echo "p5 ext4 değil, duruyorum."; exit 1; }

if findmnt -rn -S "$P5" >/dev/null; then
    ONCEKI=$(findmnt -rn -S "$P5" -o TARGET | head -1)
    [ "$ONCEKI" = "$MNT" ] || { echo "p5 zaten $ONCEKI'a bağlı; önce ayır."; exit 1; }
else
    mkdir -p "$MNT"
    mount "$P5" "$MNT"
fi

echo "== p5'in mevcut içeriği (dokunulmayacak):"
ls -la "$MNT"

GEREKEN=$(du -sk /home | cut -f1)
BOS=$(df -k --output=avail "$MNT" | tail -1)
echo "== /home: $((GEREKEN/1024)) MB, p5'te boş: $((BOS/1024)) MB"
[ "$BOS" -gt $((GEREKEN + 1048576)) ] || { echo "p5'te yeterli yer yok."; exit 1; }

echo "== Kopyalanıyor: /home -> $HEDEF"
mkdir -p "$HEDEF"
chmod 755 "$HEDEF"
rsync -aHAX --info=progress2 /home/ "$HEDEF/"

if ! grep -q '524c28d4-f588-4154-b586-6654380d7f22' /etc/fstab; then
    cp -a /etc/fstab "/etc/fstab.yedek-$(date +%Y%m%d-%H%M%S)"
    cat >> /etc/fstab <<EOF

# p5 ("atasOS", 99,8 GB): /home buradan geliyor (home-tasi.sh)
PARTUUID=524c28d4-f588-4154-b586-6654380d7f22  $MNT  ext4  defaults,noatime  0  2
$HEDEF  /home  none  bind,x-systemd.requires-mounts-for=$MNT  0  0
EOF
    echo "== /etc/fstab güncellendi (yedeği /etc/fstab.yedek-*)."
else
    echo "== /etc/fstab'ta p5 satırı zaten var, dokunmadım."
fi

echo "== fstab doğrulaması:"
findmnt --verify --tab-file /etc/fstab || { echo "fstab doğrulaması başarısız! Yedekten geri al: /etc/fstab.yedek-*"; exit 1; }

echo
echo "Tamam. Şimdi yeniden başlat: sudo reboot"
echo "Açılınca 'df -h /home' 99,8 GB'lık bölümü göstermeli."
