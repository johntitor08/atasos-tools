#!/usr/bin/env bash
# atas3 denemesinde ekrana ne oldu? SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-7-atas3-ne-oldu.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
J=$A/var/log/journal
mountpoint -q $A || mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
[ -d "$J" ] || { echo "HATA: journal yok"; exit 1; }
jc(){ journalctl -D "$J" --no-pager "$@" 2>/dev/null; }

echo "########## 1/8  HANGI ACILISLAR KAYITLI ##########"
jc --list-boots | tail -6 | sed 's/^/  /'
echo
echo "  --- her acilisin cekirdegi ---"
for b in -2 -1 0; do
    printf '  acilis %-3s ' "$b"
    jc -b $b -k | grep -m1 'Linux version' | sed -E 's/.*Linux version ([^ ]+) .*/\1/' || echo "(kayit yok)"
done

echo
echo "########## 2/8  SON ACILIS atas3 MU ##########"
SURUM=$(jc -b 0 -k | grep -m1 'Linux version' | sed -E 's/.*Linux version ([^ ]+) .*/\1/')
echo "  son acilistaki cekirdek: ${SURUM:-BULUNAMADI}"
case "$SURUM" in
    *atas3*) echo "  -> atas3 GERCEKTEN acildi. Sorun ekranda." ;;
    *atas2*) echo "  -> atas2 acilmis! GRUB'da YANLIS girdi secilmis olabilir." ;;
    '')      echo "  -> hic kayit yok: cekirdek cok erken oldu veya disk yazilamadi." ;;
    *)       echo "  -> beklenmedik: $SURUM" ;;
esac
echo "  komut satiri:"
jc -b 0 -k | grep -m1 'Command line' | sed 's/^/    /'

echo
echo "########## 3/8  KONSOL KIME VERILDI (asil soru) ##########"
jc -b 0 -k | grep -iE 'Console:|console \[|printk' | head -10 | sed 's/^/  /'
echo
echo "  --- dummy device hala var mi ---"
if jc -b 0 -k | grep -q 'colour dummy device'; then
    echo "    EVET dummy -> hicbir surucu framebuffer'i almamis"
else
    echo "    HAYIR dummy yok -> bir surucu framebuffer'i ALMIS (ilerleme)"
fi

echo
echo "########## 4/8  FRAMEBUFFER / DRM ZINCIRI ##########"
echo "  --- sysfb / simpledrm / fb0 ---"
jc -b 0 -k | grep -iE 'sysfb|simple-framebuffer|simpledrm|fb0|efifb|Registered fb' | head -15 | sed 's/^/  /'
echo
echo "  --- fbcon devralma ---"
jc -b 0 -k | grep -iE 'fbcon|frame buffer device|switching to' | head -10 | sed 's/^/  /'

echo
echo "########## 5/8  i915 SIMPLEDRM'I SOKTU MU (ana suphe) ##########"
jc -b 0 -k | grep -iE 'i915|removing|remove_conflicting|drm' | head -25 | sed 's/^/  /'
echo
if jc -b 0 -k | grep -qiE 'i915'; then
    echo "  >>> i915 YUKLENMIS."
    echo "  --- i915 firmware istedi mi / hata verdi mi ---"
    jc -b 0 -k | grep -iE 'i915.*(firmware|failed|error|timed out|dmc|guc|huc)' | head -12 | sed 's/^/    /'
else
    echo "  >>> i915 hic yuklenmemis."
fi

echo
echo "########## 6/8  SISTEM ACILMAYA DEVAM ETTI MI ##########"
echo "  --- kok dosya sistemi ---"
jc -b 0 | grep -iE 'EXT4-fs.*mounted|switch.root' | head -4 | sed 's/^/  /'
echo
echo "  --- getty basladi mi (dun etkinlestirdik) ---"
jc -b 0 | grep -iE 'getty|agetty|autologin' | head -10 | sed 's/^/  /'
jc -b 0 | grep -qiE 'getty@tty1' && echo "    >>> getty@tty1 BASLADI" || echo "    >>> getty@tty1 kaydi YOK"
echo
echo "  --- giris yapildi mi ---"
jc -b 0 | grep -iE 'New session|logged in|login' | head -6 | sed 's/^/  /'

echo
echo "########## 7/8  HATALAR ##########"
jc -b 0 -p err | head -20 | sed 's/^/  /'
echo
echo "  --- nasil bitti (son 12 satir) ---"
jc -b 0 | tail -12 | sed 's/^/  /'

echo
echo "########## 8/8  KARAR ##########"
D=$(jc -b 0 -k | grep -c 'colour dummy device')
S=$(jc -b 0 -k | grep -ci 'simpledrm')
I=$(jc -b 0 -k | grep -ci 'i915')
G=$(jc -b 0 | grep -ci 'getty@tty1')
printf '  %-30s %s\n' "dummy console satiri"  "$D"
printf '  %-30s %s\n' "simpledrm satiri"      "$S"
printf '  %-30s %s\n' "i915 satiri"           "$I"
printf '  %-30s %s\n' "getty@tty1 satiri"     "$G"
echo
if [ "$S" -gt 0 ] && [ "$I" -gt 0 ]; then
    echo "  TESHIS: simpledrm devraldi, sonra i915 yuklendi."
    echo "          Cozum: i915'i kara listeye al (modul olarak yuklenmesin)."
elif [ "$S" -gt 0 ] && [ "$I" -eq 0 ]; then
    echo "  TESHIS: simpledrm calisti, i915 yok. Ekran panelin kendisiyle ilgili"
    echo "          veya fbcon devralmadi."
elif [ "$D" -gt 0 ]; then
    echo "  TESHIS: konsol hala dummy - secenekler ise yaramamis."
else
    echo "  TESHIS: yukaridaki satirlara bakmak gerek."
fi
echo
echo "=============================================="
echo " Hicbir sey degistirilmedi."
echo "=============================================="
