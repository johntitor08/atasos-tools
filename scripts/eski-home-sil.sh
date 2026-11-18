#!/bin/bash
# Kök bölümde, yeni /home bağlantısının altında kalan eski /home kopyasını siler.
# Kullanım: sudo bash eski-home-sil.sh
set -euo pipefail

KOK=/mnt/kok-eski

[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştır: sudo bash $0"; exit 1; }

# Güvenlik: /home gerçekten p5'ten gelmeli, yoksa canlı veriyi silebiliriz.
KAYNAK=$(findmnt -n -o SOURCE /home || true)
case "$KAYNAK" in
    */nvme0n1p5\[/home-kurulu\]) ;;
    *) echo "/home p5'ten bağlı değil ($KAYNAK), duruyorum."; exit 1 ;;
esac

# Kök dosya sistemini (alt bağlantılar olmadan) ayrı bir yere bağla:
# burada /home, bind'in altındaki eski dizin olarak görünür.
mkdir -p "$KOK"
mountpoint -q "$KOK" || mount --bind / "$KOK"
trap 'umount "$KOK" 2>/dev/null; rmdir "$KOK" 2>/dev/null' EXIT

# Ek güvenlik: bağladığımız yer kök bölüm olmalı, p5 değil.
[ "$(findmnt -n -o SOURCE "$KOK" | sed 's/\[.*//')" = "$(findmnt -n -o SOURCE / | sed 's/\[.*//')" ] \
    || { echo "Bind beklenen kök değil, duruyorum."; exit 1; }

echo "== Kökteki eski /home içeriği:"
ls -la "$KOK/home"
du -sh "$KOK/home"/* 2>/dev/null || true
echo "== Yeni /home (p5):"
du -sh /home/* 2>/dev/null

echo
read -r -p "Kökteki eski /home içeriği KALICI olarak silinsin mi? (evet yaz): " CEVAP
[ "$CEVAP" = "evet" ] || { echo "Vazgeçildi, hiçbir şey silinmedi."; exit 0; }

# /home dizininin kendisi kalsın (bağlantı noktası), sadece içi silinsin.
find "$KOK/home" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
sync
echo "== Silindi. Kök bölüm:"
df -h /
