#!/usr/bin/env bash
# 2026-06-23'teki 90 dakikalik acilista EKRAN CALISIYORDU. Orada ne farkliydi?
# SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-9-calisan-acilis.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
J=$A/var/log/journal
mountpoint -q $A || mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
jc(){ journalctl -D "$J" --no-pager "$@" 2>/dev/null; }
B=-5   # 2026-06-23 09:05 -> 10:35

echo "########## 1/9  O ACILIS NEYDI ##########"
jc --list-boots | sed 's/^/  /'
echo
echo "  --- cekirdek ve komut satiri ---"
jc -b $B -k | grep -m1 'Linux version' | sed 's/^/  /'
jc -b $B -k | grep -m1 'Command line'  | sed 's/^/  /'
echo
echo "  --- ne kadar surdu / nasil bitti ---"
jc -b $B | head -1 | sed 's/^/  ilk : /'
jc -b $B | tail -1 | sed 's/^/  son : /'

echo
echo "########## 2/9  KONSOL KIME VERILDI (kiyas noktasi) ##########"
jc -b $B -k | grep -iE 'Console:|console \[' | head -8 | sed 's/^/  /'
if jc -b $B -k | grep -q 'colour dummy device'; then
    echo "  >>> dummy VAR"
else
    echo "  >>> dummy YOK - gercek bir surucu almis"
fi

echo
echo "########## 3/9  FRAMEBUFFER ZINCIRI ##########"
jc -b $B -k | grep -iE 'sysfb|simple-framebuffer|simpledrm|efifb|Registered fb|fb0|fbcon|frame buffer' \
    | head -20 | sed 's/^/  /'

echo
echo "########## 4/9  DRM / i915 ##########"
jc -b $B -k | grep -iE 'i915|drm|GuC|HuC|DMC|firmware' | head -30 | sed 's/^/  /'

echo
echo "########## 5/9  GRAFIK OTURUMU GERCEKTEN ACILDI MI ##########"
echo "  --- sddm / plasma / X / wayland ---"
jc -b $B | grep -iE 'sddm|plasma|Xorg|wayland|display-manager|graphical.target' | head -20 | sed 's/^/  /'
echo
echo "  --- kullanici oturumu ---"
jc -b $B | grep -iE 'New session|seat0|logind' | head -12 | sed 's/^/  /'

echo
echo "########## 6/9  KOK NEREDEN BAGLANDI (ISO mu, p5 mi) ##########"
jc -b $B | grep -iE 'EXT4-fs|squashfs|loop|iso9660|overlay|switch.root|mounted filesystem' \
    | head -12 | sed 's/^/  /'
echo
echo "  NOT: 'squashfs/iso9660/loop' gorursen o acilis ISO'dandir,"
echo "       'EXT4-fs (nvme0n1p5)' gorursen kurulu sistemden."

echo
echo "########## 7/9  O CEKIRDEGIN CONFIG'I DURUYOR MU ##########"
V=$(jc -b $B -k | grep -m1 'Linux version' | sed -E 's/.*Linux version ([^ ]+) .*/\1/')
echo "  o acilistaki cekirdek: ${V:-BULUNAMADI}"
ls -la $A/boot/ | sed 's/^/  /'

echo
echo "########## 8/9  KRITIK KIYAS: o config vs atas3 config ##########"
C=$A/boot/config-$V
if [ -f "$C" ]; then
    echo "  $C bulundu. Ekran secenekleri karsilastiriliyor:"
    printf '  %-36s %-10s %s\n' "simge" "CALISAN($V)" "ATAS3"
    for s in CONFIG_DRM CONFIG_DRM_SIMPLEDRM CONFIG_DRM_FBDEV_EMULATION \
             CONFIG_FRAMEBUFFER_CONSOLE CONFIG_SYSFB_SIMPLEFB CONFIG_FB_EFI \
             CONFIG_DRM_I915 CONFIG_AUDIT CONFIG_FB CONFIG_VT CONFIG_VT_CONSOLE; do
        a=$(grep -E "^$s=" "$C" 2>/dev/null | cut -d= -f2); a=${a:-YOK}
        b=$(grep -E "^$s=" "$A/boot/config-6.16.1-atas3" 2>/dev/null | cut -d= -f2); b=${b:-YOK}
        if [ "$a" = "$b" ]; then printf '  %-36s %-10s %s\n' "$s" "$a" "$b"
        else printf '  %-36s %-10s %s   <<< FARKLI\n' "$s" "$a" "$b"; fi
    done
else
    echo "  $C YOK - o cekirdegin config'i saklanmamis."
    echo "  /boot'taki config dosyalari:"
    ls -la $A/boot/config* 2>/dev/null | sed 's/^/    /'
fi

echo
echo "########## 9/9  OZET ##########"
printf '  %-34s %s\n' "o acilista dummy console" "$(jc -b $B -k | grep -c 'colour dummy device')"
printf '  %-34s %s\n' "o acilista i915 satiri"   "$(jc -b $B -k | grep -ci 'i915')"
printf '  %-34s %s\n' "o acilista fb kaydi"      "$(jc -b $B -k | grep -ciE 'Registered fb|fb0|simpledrm|efifb')"
printf '  %-34s %s\n' "o acilista sddm/plasma"   "$(jc -b $B | grep -ciE 'sddm|plasma')"
echo
echo "=============================================="
echo " Hicbir sey degistirilmedi."
echo "=============================================="
