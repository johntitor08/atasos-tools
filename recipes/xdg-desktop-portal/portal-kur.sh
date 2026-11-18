#!/bin/bash
# atasOS: xdg-desktop-portal 1.18.4 + xdg-desktop-portal-kde 6.3.4 kurulumu.
# Dosyalar önceden derlenip ./kok altına hazırlandı; bu betik onları / altına kopyalar.
# Kullanım:  sudo bash portal-kur.sh
# Kaldırma:  sudo bash portal-kur.sh --kaldir
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştır: sudo bash $0"; exit 1; }
[ -d kok ] && [ -f dosya-listesi.txt ] || { echo "kok/ veya dosya-listesi.txt yok"; exit 1; }

if [ "${1:-}" = "--kaldir" ]; then
    while IFS= read -r f; do rm -f -- "$f"; done < dosya-listesi.txt
    echo "Portal dosyaları kaldırıldı. Oturumu kapatıp aç."
    exit 0
fi

# Mevcut dizinlerin sahip/izinlerine dokunmadan, dosyaları root sahipliğinde kopyala.
tar -C kok -cf - . | tar -C / -xpf - --no-overwrite-dir --no-same-owner
echo "== Kuruldu: $(wc -l < dosya-listesi.txt) dosya"
ls -l /usr/libexec/xdg-desktop-portal /usr/libexec/xdg-desktop-portal-kde
echo
echo "Şimdi oturumu kapatıp yeniden aç (ya da bilgisayarı yeniden başlat)."
