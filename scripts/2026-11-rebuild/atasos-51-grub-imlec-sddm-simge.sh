#!/usr/bin/env bash
# 1) Kubuntu GRUB: atasOS girdilerinden yalniz "atas5 masaustu / SDDM" kalir (digerleri /root altina yedeklenir).
# 2) Imlec: Kubuntu ile ayni gorunum (Wayland 24 x %200 = 48 piksel) -> atasOS X11'de her yerde 48.
# 3) SDDM giris ekrani %200 olcek + imlec 48 (bu laptopa ozgu; ISO'ya girmez, atasos-44 siler).
# 4) Uygulama menusu/panelde Firefox simgesi: hicolor-icon-theme (index.theme yoktu!) + Firefox PNG'leri hicolor'a.
# Kullanim: sudo bash /home/eren/atasos-51-grub-imlec-sddm-simge.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
K=/sources/atasos-B
TS=$(date +%m%d-%H%M)
IMLEC=48

echo "########## 1/4  GRUB (Kubuntu) ##########"
Y=/root/grub-yedek-$TS; mkdir -p $Y
for f in 42_atasos 43_atasos_atas4 44_atasos_atas5; do [ -f /etc/grub.d/$f ] && cp -a /etc/grub.d/$f $Y/; done
G5=/etc/grub.d/44_atasos_atas5
[ -f $Y/44_atasos_atas5 ] || { echo "  HATA: $G5 yok - atas5 girdisi bulunamadi, GRUB'a dokunulmadi"; exit 1; }
# atas5 masaustu girdisini eski dosyadan aynen al (UUID'ler degismesin)
python3 -I - $Y/44_atasos_atas5 $G5 <<'PY'
import sys,re
t=open(sys.argv[1]).read()
m=re.search(r'menuentry "[^"]*atas5[^"]*masaustu[^"]*"[^{]*\{.*?\n\}', t, re.S)
if not m: sys.exit("masaustu girdisi bulunamadi")
g=m.group(0).replace(m.group(0).split('"')[1], "atasOS", 1)
open(sys.argv[2],"w").write('#!/bin/sh\nexec tail -n +3 $0\n'+g+'\n')
PY
[ $? -eq 0 ] || { echo "  HATA: girdi ayiklanamadi; GRUB'a dokunulmadi"; cp -a $Y/44_atasos_atas5 $G5; exit 1; }
chmod 755 $G5
rm -f /etc/grub.d/42_atasos /etc/grub.d/43_atasos_atas4
update-grub 2>&1 | grep -iE 'error|hata' | sed 's/^/  /'
echo "  yedek: $Y"
echo "  GRUB'daki atasOS girdileri:"; grep -n 'menuentry "atasOS' /boot/grub/grub.cfg | sed 's/^/    /'
grep -A8 'menuentry "atasOS"' /boot/grub/grub.cfg | grep -E 'linux |gfxpayload' | sed 's/^/    /'

echo
echo "########## 2/4  p5: IMLEC $IMLEC + SDDM OLCEGI ##########"
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. (GRUB kismi yapildi.)"; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/run $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
H=$A/home/eren/.config; EU=$(stat -c %u $A/home/eren); EG=$(stat -c %g $A/home/eren)
# KDE imlec ayari (KWin ve Plasma bunu okur)
python3 -I - "$H/kcminputrc" $IMLEC <<'PY'
import sys,configparser,os
p,b=sys.argv[1],sys.argv[2]
c=configparser.RawConfigParser(); c.optionxform=str
if os.path.exists(p): c.read(p)
if not c.has_section("Mouse"): c.add_section("Mouse")
c.set("Mouse","cursorTheme","breeze_cursors"); c.set("Mouse","cursorSize",b)
with open(p,"w") as f: c.write(f, space_around_delimiters=False)
PY
chown $EU:$EG "$H/kcminputrc"
F=$H/plasma-workspace/env/atasos-olcek.sh
cp -a "$F" "$F.yedek-$TS"
sed -i -E "s/^export XCURSOR_SIZE=.*/export XCURSOR_SIZE=$IMLEC/; s/Xcursor\.size: [0-9]+/Xcursor.size: $IMLEC/" "$F"
grep -q '^export XCURSOR_THEME=' "$F" || echo 'export XCURSOR_THEME=breeze_cursors' >> "$F"
echo "  kcminputrc: $(grep -E '^cursor' $H/kcminputrc | tr '\n' ' ')"
echo "  olcek betigi: $(grep -oE 'XCURSOR_SIZE=[0-9]+|Xcursor.size: [0-9]+|XCURSOR_THEME=[a-z_]+' "$F" | tr '\n' ' ')"
echo "  breeze_cursors boyutlari: $(python3 -I -c "
import struct,sys
d=open('$A/usr/share/icons/breeze_cursors/cursors/left_ptr','rb').read()
n=struct.unpack('<I',d[12:16])[0]; print(sorted({struct.unpack('<III',d[16+i*12:28+i*12])[1] for i in range(n)}))" 2>/dev/null)"
# SDDM giris ekrani (X11): %200 + imlec. Yalnizca bu laptop: atasos-44 ISO'da bu dosyayi siler.
cat > $A/etc/sddm.conf.d/20-atasos-olcek.conf <<EOF
# atasOS: 3000x2000 ekran icin giris ekrani %200 (yalniz bu bilgisayar; ISO'ya girmez)
[General]
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=2,QT_FONT_DPI=96,XCURSOR_SIZE=$IMLEC,XCURSOR_THEME=breeze_cursors

[Theme]
CursorTheme=breeze_cursors
CursorSize=$IMLEC
EOF
echo "  /etc/sddm.conf.d/20-atasos-olcek.conf yazildi"
grep -rhE 'GreeterEnvironment|CursorSize|DisplayServer|Current=' $A/etc/sddm.conf.d/ | sed 's/^/    /'

echo
echo "########## 3/4  hicolor-icon-theme 0.18 ##########"
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys; mount -t tmpfs tmpfs $A/run
mkdir -p $A$K $A/var/lib/atasos-paketler
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin /bin/bash -euo pipefail -c "$1"; }
if [ -f $A/usr/share/icons/hicolor/index.theme ]; then echo "  zaten var"; else
    f=$T/hicolor-icon-theme-0.18.tar.xz
    [ -f $f ] || curl -sSfL --retry 2 -o $f https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-0.18.tar.xz || { echo "  INDIRILEMEDI"; exit 1; }
    [ "$(md5sum $f | cut -d' ' -f1)" = ef14f3af03bcde9ed134aad626bdbaad ] || { echo "  MD5 UYUSMUYOR"; rm -f $f; exit 1; }
    cp $f $A$K/
    cr "cd $K && rm -rf hicolor-icon-theme-0.18 /tmp/stage-hicolor && tar -xf hicolor-icon-theme-0.18.tar.xz && cd hicolor-icon-theme-0.18
        mkdir build && cd build && meson setup --prefix=/usr --buildtype=release .. >/dev/null && ninja >/dev/null
        DESTDIR=/tmp/stage-hicolor ninja install >/dev/null
        cd /tmp/stage-hicolor && find . -type f -o -type l | sed 's|^\.||' | sort > /var/lib/atasos-paketler/hicolor-icon-theme.list
        cp -a . / && rm -rf /tmp/stage-hicolor" || { echo "  BASARISIZ"; exit 1; }
    echo "  kuruldu: $(wc -l < $A/var/lib/atasos-paketler/hicolor-icon-theme.list) dosya (index.theme dahil)"
fi

echo
echo "########## 4/4  FIREFOX SIMGESI ##########"
: > $A/var/lib/atasos-paketler/firefox-simge.list
for b in 16 22 24 32 48 64 128; do
    s=$A/opt/firefox/browser/chrome/icons/default/default$b.png; [ -f $s ] || continue
    h=/usr/share/icons/hicolor/${b}x${b}/apps/firefox.png
    install -Dm644 $s $A$h; echo $h >> $A/var/lib/atasos-paketler/firefox-simge.list
done
echo "  hicolor'a kondu: $(sed 's|/usr/share/icons/hicolor/||; s|/apps/firefox.png||' $A/var/lib/atasos-paketler/firefox-simge.list | tr '\n' ' ')"
D=$A/usr/share/applications/firefox.desktop
echo "  firefox.desktop Icon (once): $(grep -m1 '^Icon=' $D)"
sed -i 's|^Icon=.*|Icon=firefox|' $D
cr 'gtk-update-icon-cache -qf /usr/share/icons/hicolor && echo "  simge onbellegi guncellendi"; command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications; true'
# kullanicinin eski KDE servis onbellegi -> oturum acilisinda yeniden kurulsun
rm -f $A/home/eren/.cache/ksycoca6_* 2>/dev/null; rm -rf $A/home/eren/.cache/icon-cache.kcache 2>/dev/null
sync
echo
echo "  Bitti. Yeniden baslat -> GRUB'da tek atasOS girdisi. Giris ekrani, imlec ve Firefox simgesini kontrol et."
