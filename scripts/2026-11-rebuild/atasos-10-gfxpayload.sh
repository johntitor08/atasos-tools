#!/usr/bin/env bash
# ASIL EKSIK: benim yazdigim GRUB girdilerinde 'set gfxpayload=keep' yoktu.
# EFI'de GRUB varsayilan olarak cekirdege dogrusal framebuffer bilgisi VERMEZ.
# O bilgi gelmeyince sysfb 'simple-framebuffer' aygitini uretmez, simpledrm
# baglanacak bir sey bulamaz ve konsol yine 'dummy' olur.
# Kullanim: sudo bash /home/eren/atasos-10-gfxpayload.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
mountpoint -q $A || mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
P5UUID=652f2262-d729-4c56-9eb4-ed463d94644a
PU=524c28d4-f588-4154-b586-6654380d7f22
YENI=6.16.1-atas3
ESKI=6.16.1-atas2

echo "########## 1/6  SIMDIKI DURUM ##########"
echo "  --- 42_atasos'ta video ayari ---"
grep -cE 'gfxpayload' /etc/grub.d/42_atasos | sed 's/^/    gfxpayload satiri: /'
echo "  --- GRUB grafik terminali kullaniyor mu (gfxterm sart) ---"
grep -m3 -E 'terminal_output|set gfxmode' /boot/grub/grub.cfg | sed 's/^/    /'
echo "  --- Ubuntu girdileri nasil yapiyor (kiyas) ---"
grep -m2 -E 'gfxpayload' /boot/grub/grub.cfg | sed 's/^/    /'

echo
echo "########## 2/6  YEDEK (bu kez /etc/grub.d DISINA) ##########"
YD=/root/grub.d-yedekler; mkdir -p "$YD"
cp /etc/grub.d/42_atasos "$YD/42_atasos.oncesi-$(date +%Y%m%d-%H%M%S)"
chmod -x "$YD"/* 2>/dev/null
echo "  yedek: $YD  (calistirilabilir degil - gecen seferki hata tekrarlanmasin)"

echo
echo "########## 3/6  GIRDILER YENIDEN YAZILIYOR ##########"
G=/etc/grub.d/42_atasos
ortak(){ cat <<'EOF'
    insmod part_gpt
    insmod ext2
    insmod all_video
    insmod gfxterm
    set gfxpayload=keep
EOF
}
{
echo '#!/bin/sh'
echo 'exec tail -n +3 $0'

echo "menuentry \"atasOS  $YENI  1) metin konsolu  [gfxpayload=keep]\" --class atasos {"
ortak
echo "    search --no-floppy --fs-uuid --set=root $P5UUID"
echo "    linux /boot/vmlinuz-$YENI root=PARTUUID=$PU rw rootwait systemd.unit=multi-user.target console=tty0 loglevel=7"
echo '}'

echo "menuentry \"atasOS  $YENI  2) metin konsolu + nomodeset  (i915 devre disi)\" --class atasos {"
ortak
echo "    search --no-floppy --fs-uuid --set=root $P5UUID"
echo "    linux /boot/vmlinuz-$YENI root=PARTUUID=$PU rw rootwait systemd.unit=multi-user.target console=tty0 loglevel=7 nomodeset"
echo '}'

echo "menuentry \"atasOS  $YENI  3) masaustu / SDDM\" --class atasos {"
ortak
echo "    search --no-floppy --fs-uuid --set=root $P5UUID"
echo "    linux /boot/vmlinuz-$YENI root=PARTUUID=$PU rw rootwait console=tty0 loglevel=4"
echo '}'

echo "menuentry \"atasOS  $ESKI  4) ESKI cekirdek (geri donus)\" --class atasos {"
ortak
echo "    search --no-floppy --fs-uuid --set=root $P5UUID"
echo "    linux /boot/vmlinuz-$ESKI root=PARTUUID=$PU rw rootwait systemd.unit=multi-user.target console=tty0 loglevel=7"
echo '}'
} > "$G"
chmod +x "$G"
echo "  --- yazilan girdiler ---"
grep -n '^menuentry' "$G" | sed 's/^/    /'

echo
echo "########## 4/6  MENU URETILIYOR ##########"
update-grub 2>&1 | grep -iE 'error|warn' | sed 's/^/  /'
T=$(grep -c '^menuentry.*atasOS' /boot/grub/grub.cfg)
echo "  atasOS girdi sayisi: $T  (beklenen: 4)"

echo
echo "########## 5/6  DOGRULAMA ##########"
D=0
echo "  --- her atasOS girdisinde gfxpayload=keep var mi ---"
K=$(awk '/^menuentry.*atasOS/,/^}/' /boot/grub/grub.cfg | grep -c 'set gfxpayload=keep')
printf '  %-44s %s  (beklenen 4)\n' "gfxpayload=keep satiri" "$K"
[ "$K" -eq 4 ] || D=1
echo
echo "  --- all_video yuklu mu ---"
V=$(awk '/^menuentry.*atasOS/,/^}/' /boot/grub/grub.cfg | grep -c 'insmod all_video')
printf '  %-44s %s  (beklenen 4)\n' "insmod all_video" "$V"
[ "$V" -eq 4 ] || D=1
echo
echo "  --- cekirdek dosyalari cagriliyor mu ---"
awk '/^menuentry.*atasOS/,/^}/' /boot/grub/grub.cfg | grep -oE 'vmlinuz-[0-9.]+-[a-z0-9]+' | sort | uniq -c | sed 's/^/    /'
echo
echo "  --- GRUB gercekten grafik terminalde mi (keep bunu devreder) ---"
if grep -q 'terminal_output gfxterm' /boot/grub/grub.cfg; then
    echo "    gfxterm AKTIF - keep calisir"
else
    echo "    gfxterm YOK <<< keep ise yaramayabilir"; D=1
fi
echo
echo "  --- menu sirasi ---"
grep -nE '^(menuentry|submenu)' /boot/grub/grub.cfg \
  | sed -E 's/^[0-9]+:(menuentry|submenu) .([^"'"'"']*)..*/\2/' \
  | nl -ba -w3 -s'  ' | sed 's/^/  /'

echo
echo "########## 6/6  SONUC ##########"
if [ "$D" -eq 0 ] && [ "$T" -eq 4 ]; then
    echo "  HAZIR."
    echo
    echo "  SIRAYLA DENE - ilki calismazsa ikincisi:"
    echo "    1) 'atasOS $YENI  1) metin konsolu  [gfxpayload=keep]'"
    echo "    2) calismazsa: 'atasOS $YENI  2) metin konsolu + nomodeset'"
    echo
    echo "  2. secenek i915'i tamamen devre disi birakir; framebuffer'i"
    echo "  kimse simpledrm'den geri almaz. Ikisi de siyah kalirsa sorun"
    echo "  GRUB'in framebuffer devrinde degil, baska yerde demektir."
else
    echo "  SORUN VAR <<< yukariya bak, yeniden baslatma."
fi
echo
echo "=============================================="
echo " Cekirdeklere dokunulmadi."
echo "=============================================="
