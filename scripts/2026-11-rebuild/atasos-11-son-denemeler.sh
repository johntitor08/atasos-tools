#!/usr/bin/env bash
# gfxpayload=keep girdileriyle yapilan atas3 denemeleri journal'a yazildi mi? SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-11-son-denemeler.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
J=$A/var/log/journal
mkdir -p $A
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5 baglanamadi"; exit 1; }
jc(){ journalctl -D "$J" --no-pager "$@" 2>/dev/null; }

echo "########## 1/5  KAYITLI SON ACILISLAR ##########"
echo "  (onceki son kayit: 11:31 atas2. adjtime UTC yapildigi icin yenilerin saati artik dogru olmali)"
jc --list-boots | tail -8 | sed 's/^/  /'
echo
echo "  --- son 6 acilisin cekirdegi ve komut satiri ---"
for b in -5 -4 -3 -2 -1 0; do
    v=$(jc -b $b -k | grep -m1 'Linux version' | sed -E 's/.*Linux version ([^ ]+) .*/\1/')
    c=$(jc -b $b -k | grep -m1 'Command line' | grep -oE '(nomodeset|systemd.unit=[^ ]+|loglevel=[0-9])' | tr '\n' ' ')
    printf '  %-3s %-16s %s\n' "$b" "${v:-?}" "$c"
done

N=$(jc -b 0 -k | grep -m1 'Linux version' | grep -c atas3)
echo
if [ "$N" -eq 0 ]; then
    echo "  >>> SON KAYIT atas3 DEGIL. atas3 denemeleri journal'a HIC YAZILMAMIS."
    echo "      Anlami: cekirdek kok dosya sistemini baglayip systemd'yi"
    echo "      calistiracak noktaya gelmeden durmus (erken panik/takilma)."
else
    echo "  >>> atas3 journal'a YAZILMIS - asagida ayrintilar."
fi

echo
echo "########## 2/5  p5 SON NE ZAMAN BAGLANDI ##########"
tune2fs -l /dev/nvme0n1p5 2>/dev/null | grep -E 'Last mount time|Last mounted on|Last write time|Mount count' | sed 's/^/  /'
echo "  ('Last mounted on: /' ve saat denemelere uyuyorsa atas3 koku baglamis demektir)"

echo
echo "########## 3/5  CokUS DOKUMU (EFI pstore) ##########"
echo "  (cekirdek panik olursa dokumu EFI'ye yazabilir; Kubuntu acilista buraya tasir)"
for d in /var/lib/systemd/pstore /sys/fs/pstore; do
    echo "  --- $d ---"
    ls -la "$d" 2>/dev/null | sed 's/^/    /'
done
f=$(find /var/lib/systemd/pstore /sys/fs/pstore -type f -newermt '2026-09-21 14:30' 2>/dev/null | head -3)
if [ -n "$f" ]; then
    for x in $f; do echo "  === $x ==="; tail -40 "$x" | sed 's/^/    /'; done
else
    echo "  bugun 14:30'dan sonra dokum yok"
fi
echo "  atas3'te pstore destegi: $(grep -E '^CONFIG_EFI_VARS_PSTORE=|^CONFIG_PSTORE=' $A/boot/config-6.16.1-atas3 | tr '\n' ' ')"

echo
echo "########## 4/5  atas3 KAYITLARI (varsa) ##########"
for b in -5 -4 -3 -2 -1 0; do
    jc -b $b -k | grep -q 'Linux version.*atas3' || continue
    echo "  ======== acilis $b ========"
    jc -b $b -k | grep -m1 'Command line' | sed 's/^/  /'
    echo "  --- konsol / framebuffer ---"
    jc -b $b -k | grep -iE 'Console:|sysfb|simple-framebuffer|simpledrm|efifb|fb0|fbcon|frame buffer|i915|nomodeset' | head -15 | sed 's/^/    /'
    echo "  --- getty / giris ---"
    jc -b $b | grep -iE 'getty@tty1|autologin|New session' | head -5 | sed 's/^/    /'
    echo "  --- hatalar ---"
    jc -b $b -p err | head -10 | sed 's/^/    /'
    echo "  --- son 6 satir ---"
    jc -b $b | tail -6 | sed 's/^/    /'
done

echo
echo "########## 5/5  EFI FRAMEBUFFER BILGISI (Kubuntu'dan, kiyas) ##########"
echo "  Kubuntu ayni GRUB'dan geliyor; framebuffer ona devredildi mi:"
journalctl -b 0 -k --no-pager 2>/dev/null | grep -iE 'efifb|simple-framebuffer|simpledrm|sysfb' | head -5 | sed 's/^/    /'

umount $A 2>/dev/null
echo
echo "=============================================="
echo " Salt okunur baglandi, hicbir sey degistirilmedi."
echo "=============================================="
