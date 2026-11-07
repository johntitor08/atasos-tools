#!/usr/bin/env bash
# Eski atasOS EFI girdilerini sil (Boot0004 "atasOS masaustu", Boot0005 "atasOS metin konsolu").
# Ikisi de \EFI\atasos\vmlinuz.efi'yi (eski atas2, kok baglayamiyor) aciyor -> siyah ekran.
# Kubuntu/ubuntu girdilerine ve vmlinuz.efi dosyasina DOKUNULMAZ.
# Numara baska bir girdiye aitse hicbir sey silinmez.
# Kullanim: sudo bash /home/eren/atasos-30-efi-girdi-temizle.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
command -v efibootmgr >/dev/null || { echo "efibootmgr yok"; exit 1; }

echo "--- once ---"
efibootmgr | grep -E 'BootOrder|^Boot[0-9A-F]{4}' | cut -c1-90 | sed 's/^/  /'
efibootmgr -v > /root/efibootmgr-yedek-$(date +%Y%m%d-%H%M%S).txt
echo "  (tam liste yedegi: /root/efibootmgr-yedek-*.txt)"
echo

for n in 0004 0005; do
    satir=$(efibootmgr -v | grep -E "^Boot$n\*? ")
    if [ -z "$satir" ]; then echo "  Boot$n zaten yok"; continue; fi
    if echo "$satir" | grep -q 'atasOS' && echo "$satir" | grep -qi 'EFI\\atasos\\vmlinuz\.efi'; then
        efibootmgr -q -b $n -B && echo "  Boot$n silindi  ($(echo "$satir" | sed -E 's/^Boot[0-9A-F]{4}\*? //' | cut -f1))"
    else
        echo "  Boot$n beklenen atasOS girdisi DEGIL -> DOKUNULMADI:"
        echo "    $(echo "$satir" | cut -c1-90)"
    fi
done

echo
echo "--- sonra ---"
efibootmgr | grep -E 'BootOrder|^Boot[0-9A-F]{4}' | cut -c1-90 | sed 's/^/  /'
efibootmgr | grep -q 'Kubuntu' && echo "  Kubuntu girdisi YERINDE" || echo "  UYARI: Kubuntu girdisi gorunmuyor <<<"
[ -f /boot/efi/EFI/atasos/vmlinuz.efi ] && echo "  vmlinuz.efi dosyasi yerinde (silinmedi)"
