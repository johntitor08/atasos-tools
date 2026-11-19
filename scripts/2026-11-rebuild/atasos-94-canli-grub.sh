#!/usr/bin/env bash
# atasos-94: Kubuntu GRUB menusune GECICI bir "atasOS vNN Canli (ISO dosyasindan)" girdisi ekler / kaldirir (en yeni ISO).
#   Amac: en yeni ISO'yu p4'e KURMADAN gercek donanimda (HiDPI %200, portal, atasOS masaustu) denemek.
#   - en yeni /veri/atasos-iso/atasos-live-vNN.iso loop ile acilir; diskler salt-okunur kalir, kurulum bu modda KAPALI.
#   - Dokunulan tek sey: /etc/grub.d/46_atasos_iso_canli (yeni dosya) + update-grub. p4, p5, EFI'ye dokunulmaz.
#   - Deneme bitince: sudo bash ~/atasos-94-canli-grub.sh kaldir
# Kullanim: sudo bash ~/atasos-94-canli-grub.sh [ekle|kaldir]
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0 ${1:-ekle}"; exit 1; }
G=/etc/grub.d/46_atasos_iso_canli
ISO=$(ls /veri/atasos-iso/atasos-live-v[0-9]*.iso 2>/dev/null | sort -V | tail -1); SUR=$(basename "$ISO" .iso); SUR=${SUR#atasos-live-}

case "${1:-ekle}" in
kaldir)
    [ -e $G ] || { echo "  $G zaten yok; yapilacak bir sey yok."; exit 0; }
    rm -f $G && update-grub 2>&1 | grep -iE 'error|done' | sed 's/^/  /'
    grep -q "atasOS $SUR Canli" /boot/grub/grub.cfg && echo "  HATA: girdi grub.cfg'de hala var" || echo "  TAMAM: canli ISO girdisi kaldirildi."
    exit 0 ;;
ekle) ;;
*) echo "Kullanim: sudo bash $0 [ekle|kaldir]"; exit 1 ;;
esac

[ -f "$ISO" ] && [ -f "$ISO.sha256" ] || { echo "HATA: $ISO ya da .sha256 yok"; exit 1; }
echo "  ISO dogrulaniyor..."; (cd "${ISO%/*}" && sha256sum -c --quiet "${ISO##*/}.sha256") || { echo "HATA: ISO sha256 tutmuyor"; exit 1; }
[ -e $G ] && { echo "  UYARI: $G zaten var, ustune yaziliyor:"; grep menuentry $G | sed 's/^/    /'; }
IUUID=$(findmnt -no UUID --target "$ISO"); IMP=$(findmnt -no TARGET --target "$ISO"); IYOL=${ISO#$IMP}
[ -n "$IUUID" ] && [ -n "$IYOL" ] && [ "$IYOL" != "$ISO" ] || { echo "HATA: ISO'nun bolumu/yolu bulunamadi"; exit 1; }
command -v update-grub >/dev/null || { echo "HATA: update-grub yok"; exit 1; }
cat > $G <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "atasOS $SUR Canli (ISO dosyasindan - deneme, kurulum kapali)" --class atasos {
    insmod part_gpt
    insmod ext2
    insmod iso9660
    insmod loopback
    insmod all_video
    insmod gfxterm
    set gfxpayload=keep
    search --no-floppy --fs-uuid --set=root $IUUID
    loopback loop $IYOL
    linux (loop)/boot/vmlinuz quiet loglevel=3 atasos.iso=$IYOL
    initrd (loop)/boot/initramfs.img
}
EOF
chmod 755 $G
update-grub 2>&1 | grep -iE 'error|done' | sed 's/^/  /'
grep -n 'menuentry "atasOS' /boot/grub/grub.cfg | sed 's/^/  /'
grep -q "atasOS $SUR Canli" /boot/grub/grub.cfg && echo "  TAMAM: yeniden baslatinca GRUB menusunde 'atasOS $SUR Canli' sec." || { echo "  HATA: girdi grub.cfg'ye girmedi"; exit 1; }
echo "  Deneme bitince: sudo bash $0 kaldir"
