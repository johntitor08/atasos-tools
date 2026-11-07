#!/usr/bin/env bash
# atasOS gelistirmeleri (p5'e uygulanir; sonraki ISO bunlari p5'ten alir):
#   1) atasOS logosu: hicolor 'atasos' simgesi (16..512 + svg), Calamares markasi, kurulum simgesi, os-release LOGO
#   2) SDDM giris temasi v2: Turkce ekran klavyesi, otomatik olcek, hata mesaji, saat, yeniden baslat/kapat
#   3) Yuksek cozunurluk: /etc/xdg/plasma-workspace/env/atasos-hidpi.sh (EDID >= 170 dpi -> %200; kullanicinin
#      kendi olcegi varsa dokunmaz). Senin eren hesabindaki atasos-olcek.sh oldugu gibi kalir.
#   4) Calamares slaytlari Turkce + logolu
# Degisen her dosya once /var/lib/atasos-paketler/yedek-56-<tarih>/ altina kopyalanir.
# Kullanim: sudo bash /home/eren/atasos-56-gelistir.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
G=/home/eren/atas3-loglar/gelistirme
for f in $G/logo/atasos.svg $G/logo/atasos-256.png $G/sddm-atasOS/Main.qml $G/sddm-atasOS/logo.png $G/atasos-hidpi.sh $G/show.qml; do
    [ -s "$f" ] || { echo "HATA: $f yok"; exit 1; }; done
A=/mnt/atasos; TS=$(date +%m%d-%H%M); Y=$A/var/lib/atasos-paketler/yedek-56-$TS
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/run $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done; sync; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
mkdir -p $Y
yedek(){ for p in "$@"; do [ -e "$A$p" ] || continue; mkdir -p "$Y$(dirname "$p")"; cp -a "$A$p" "$Y$p"; done; }
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin /bin/bash -c "$1"; }

echo "########## 1/4  LOGO ##########"
for n in 16 22 24 32 48 64 128 256 512; do
    install -Dm644 $G/logo/atasos-$n.png $A/usr/share/icons/hicolor/${n}x${n}/apps/atasos.png
done
install -Dm644 $G/logo/atasos.svg $A/usr/share/icons/hicolor/scalable/apps/atasos.svg
echo "  hicolor/{16..512}/apps/atasos.png + scalable/apps/atasos.svg"
B=$A/etc/calamares/branding/atasos
yedek /etc/calamares/branding/atasos/logo.png /etc/calamares/branding/atasos/show.qml /etc/calamares/branding/atasos/branding.desc /usr/share/applications/calamares.desktop /etc/os-release
install -m644 $G/logo/atasos-256.png $B/logo.png
install -m644 $G/show.qml $B/show.qml
sed -i 's|^\(\s*productUrl:\).*|\1 https://archive.org/details/atasos-live|; s|^\(\s*supportUrl:\).*|\1 https://archive.org/details/atasos-live|' $B/branding.desc
echo "  Calamares: logo.png (atasOS), show.qml (Turkce), adres archive.org"
sed -i 's|^Icon=.*|Icon=atasos|' $A/usr/share/applications/calamares.desktop
echo "  calamares.desktop: $(grep -m1 '^Icon=' $A/usr/share/applications/calamares.desktop)"
# sembolik bag degil, gercek dosya olan os-release'ler (bag ise hedefi zaten listede)
for p in /etc/os-release /usr/lib/os-release; do
    f=$A$p; [ -f "$f" ] && [ ! -L "$f" ] || continue
    yedek $p
    for kv in 'LOGO=atasos' 'HOME_URL="https://archive.org/details/atasos-live"'; do
        k=${kv%%=*}; grep -q "^$k=" "$f" && sed -i "s|^$k=.*|$kv|" "$f" || echo "$kv" >> "$f"; done
    echo "  $p: $(grep -E '^(LOGO|HOME_URL)=' "$f" | tr '\n' ' ')"
done

echo
echo "########## 2/4  SDDM GIRIS TEMASI v2 ##########"
T=$A/usr/share/sddm/themes/atasOS
yedek /usr/share/sddm/themes/atasOS /etc/sddm.conf.d
install -m644 $G/sddm-atasOS/Main.qml $T/Main.qml
install -m644 $G/sddm-atasOS/logo.png $T/logo.png
install -m644 $G/sddm-atasOS/metadata.desktop $T/metadata.desktop
install -m644 $G/sddm-atasOS/theme.conf $T/theme.conf
printf '[General]\n# atasOS: giris ekraninda Turkce ekran klavyesi (temadaki "Ekran klavyesi" dugmesi)\nInputMethod=qtvirtualkeyboard\n' > $A/etc/sddm.conf.d/30-atasos-klavye.conf
echo "  tema: $(ls $T | tr '\n' ' ')"
# bu laptopun %200 ayari: tema artik olcegi kendisi hesapliyor -> Qt olcegi kaldirilir (yoksa cift buyur), imlec kalir
O=$A/etc/sddm.conf.d/20-atasos-olcek.conf
if [ -f $O ]; then
    sed -i -E 's/^GreeterEnvironment=.*/GreeterEnvironment=XCURSOR_SIZE=48,XCURSOR_THEME=breeze_cursors/' $O
    echo "  20-atasos-olcek.conf: $(grep -E '^(GreeterEnvironment|CursorSize)=' $O | tr '\n' ' ')"
fi
for m in qml/QtQuick/VirtualKeyboard/Layouts/libqtvkblayoutsplugin.so plugins/platforminputcontexts/libqtvirtualkeyboardplugin.so; do
    [ -f $A/usr/$m ] && echo "  var: /usr/$m" || echo "  YOK: /usr/$m <<< ekran klavyesi calismaz"; done

echo
echo "########## 3/4  YUKSEK COZUNURLUK (otomatik %200) ##########"
install -Dm644 $G/atasos-hidpi.sh $A/etc/xdg/plasma-workspace/env/atasos-hidpi.sh
mkdir -p $A/etc/atasos
[ -f $A/etc/atasos/olcek ] || printf '# atasOS ekran olcegi: otomatik (>=170 dpi ise %%200) | 1 | 2\n# Kullaniciya ozel: ~/.config/atasos-olcek\nOLCEK=otomatik\n' > $A/etc/atasos/olcek
echo "  /etc/xdg/plasma-workspace/env/atasos-hidpi.sh + /etc/atasos/olcek ($(grep '^OLCEK=' $A/etc/atasos/olcek))"
[ -f $A/home/eren/.config/plasma-workspace/env/atasos-olcek.sh ] && echo "  eren: kendi atasos-olcek.sh dosyan var -> otomatik betik senin oturumuna karismaz"
mount --bind /dev $A/dev; mount -t proc proc $A/proc
cr 'sh -n /etc/xdg/plasma-workspace/env/atasos-hidpi.sh && echo "  sozdizimi: tamam" || echo "  SOZDIZIMI HATASI <<<"'

echo
echo "########## 4/4  SIMGE ONBELLEGI ##########"
cr 'gtk-update-icon-cache -qf /usr/share/icons/hicolor && echo "  hicolor onbellegi guncellendi"; command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications; true'
rm -f $A/home/eren/.cache/ksycoca6_* $A/home/eren/.cache/icon-cache.kcache 2>/dev/null
echo
echo "  Yedek: ${Y#$A}"
echo "  Bitti. Sonraki adim: sudo bash /home/eren/atasos-57-v30-iso.sh"
