#!/usr/bin/env bash
# tty1 girisinde Plasma'yi ne baslatiyor? + kok dizin sahiplikleri. SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-13-profil-dok.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
O=/home/eren/atas3-loglar/profil
mkdir -p $A "$O"
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }

# eren'in (atasOS) kabuk/oturum dosyalari
for f in .bash_profile .bash_login .profile .bashrc .xinitrc .xsession .xprofile .zprofile .zshrc; do
    [ -f "$A/home/eren/$f" ] && cp "$A/home/eren/$f" "$O/eren$f"
done
# sistem geneli
cp $A/etc/profile "$O/etc-profile" 2>/dev/null
cp $A/etc/bashrc  "$O/etc-bashrc"  2>/dev/null
mkdir -p "$O/profile.d"; cp $A/etc/profile.d/* "$O/profile.d/" 2>/dev/null
mkdir -p "$O/getty-dropin"; cp $A/etc/systemd/system/getty@tty1.service.d/* "$O/getty-dropin/" 2>/dev/null

# Plasma'yi baslatan satir nerede
{
echo "=== startplasma/startx/exec gecen satirlar ==="
grep -rnE 'startplasma|startx|xinit|plasma|kwin|exec |tty1|XDG_VTNR|wayland' "$O" 2>/dev/null
echo
echo "=== ust duzey sahiplikler (atasOS) ==="
stat -c '%U(%u):%G(%g) %a  %n' $A $A/* $A/usr/* $A/var/* 2>/dev/null | sed "s|$A|/|; s|//|/|" | grep -v 'root(0):root(0)'
echo
echo "=== eren'e (1001) ait sistem dizini sayisi (ilk 3 seviye, /home haric) ==="
find $A -maxdepth 3 -path $A/home -prune -o -uid 1001 -print 2>/dev/null | wc -l
find $A -maxdepth 3 -path $A/home -prune -o -uid 1001 -print 2>/dev/null | sed "s|$A||" | head -40
} > "$O/ozet.txt" 2>&1

chown -R eren:eren "$O"
umount $A 2>/dev/null
echo "  dosyalar: $O"
ls -la "$O" | sed 's/^/    /'
