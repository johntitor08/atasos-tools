#!/usr/bin/env bash
# tty1 girisinde Plasma'yi zorla baslatan VM kodunu kapat -> atas3'te calisan komut satiri.
# Eski dosyalar SILINMEZ, yaninda yedek olarak durur.
# Kullanim: sudo bash /home/eren/atasos-14-plasma-otobaslat-kapat.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
H=$A/home/eren
BP=$H/.bash_profile
PS=$A/etc/profile.d/plasma-start.sh
[ -f "$BP" ] || { echo "HATA: $BP yok"; exit 1; }

echo "########## 1/4  ~/.bash_profile ##########"
if [ -f "$H/.bash_profile.vm-plasma" ]; then
    echo "  yedek zaten var: ~/.bash_profile.vm-plasma (ustune yazilmadi)"
else
    cp -p "$BP" "$H/.bash_profile.vm-plasma"
    echo "  yedek: ~/.bash_profile.vm-plasma"
fi
cat > "$BP" <<'EOF'
# tty1'de otomatik Plasma baslatma KAPALI (VM icin yazilmisti).
# Eski hali: ~/.bash_profile.vm-plasma
# Elle denemek icin:  bash ~/.bash_profile.vm-plasma
export LANG=tr_TR.UTF-8
[ -f ~/.bashrc ] && . ~/.bashrc
EOF
chown 1001:1001 "$BP"; chmod 644 "$BP"
echo "  yeni icerik:"; sed 's/^/    /' "$BP"

echo
echo "########## 2/4  /etc/profile.d/plasma-start.sh ##########"
if [ -f "$PS" ]; then
    mv "$PS" "$PS.devre-disi"
    echo "  -> plasma-start.sh.devre-disi  (.sh uzantisi yok, okunmaz)"
else
    echo "  zaten yok"
fi

echo
echo "########## 3/4  KONSOL: KLAVYE + FONT ##########"
V=$A/etc/vconsole.conf
[ -f "$V" ] && { cp -p "$V" "$V.yedek-$(date +%Y%m%d-%H%M%S)"; echo "  mevcut vconsole.conf:"; sed 's/^/    /' "$V"; }
KM=$(find $A/usr/share/keymaps $A/usr/share/kbd/keymaps -name 'trq.map*' 2>/dev/null | head -1)
FD=$(ls -d $A/usr/share/consolefonts $A/usr/share/kbd/consolefonts 2>/dev/null | head -1)
FONT=""
for f in ter-v32n ter-v32b ter-132n ter-132b latarcyrheb-sun32 solar24x32 sun12x22; do
    ls "$FD"/$f.* >/dev/null 2>&1 && { FONT=$f; break; }
done
echo "  trq klavye dosyasi : ${KM:-YOK}"
echo "  font dizini        : ${FD:-YOK}"
echo "  secilen buyuk font : ${FONT:-YOK (8x16 kalacak, kucuk ama okunur)}"
{
    grep -vE '^(KEYMAP|FONT)=' "$V" 2>/dev/null
    [ -n "$KM" ]   && echo "KEYMAP=trq"
    [ -n "$FONT" ] && echo "FONT=$FONT"
} > "$V.yeni"
mv "$V.yeni" "$V"; chmod 644 "$V"; chown 0:0 "$V"
echo "  yeni vconsole.conf:"; sed 's/^/    /' "$V"

echo
echo "########## 4/4  DOGRULAMA ##########"
D=0
grep -q 'startplasma\|Xorg' "$BP" && { echo "  .bash_profile hala Plasma baslatiyor <<<"; D=1; } || echo "  .bash_profile      temiz"
[ -f "$H/.bash_profile.vm-plasma" ] && echo "  eski profil yedegi VAR" || { echo "  YEDEK YOK <<<"; D=1; }
[ -f "$PS" ] && { echo "  plasma-start.sh hala aktif <<<"; D=1; } || echo "  plasma-start.sh    devre disi"
echo "  getty autologin    : $(grep -o 'autologin [a-z]*' $A/etc/systemd/system/getty@tty1.service.d/autologin.conf)"
sync
umount $A 2>/dev/null
echo
if [ "$D" -eq 0 ]; then
    echo "  HAZIR. Yeniden baslat, GRUB'da 3. satir:"
    echo "    'atasOS 6.16.1-atas3  1) metin konsolu  [gfxpayload=keep]'"
    echo "  BEKLENEN: yazilar akar, sonunda 'eren@atasos' komut satiri kalir."
    echo "  Ilk komut olarak sunu yaz ve ciktiyi fotografla:"
    echo "    id; ls -ld / /usr /var; ls -l /usr/bin/sudo /usr/bin/su"
else
    echo "  SORUN VAR <<<"
fi
