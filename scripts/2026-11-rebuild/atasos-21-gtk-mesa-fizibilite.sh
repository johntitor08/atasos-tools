#!/usr/bin/env bash
# 1) Firefox icin GTK3 zincirinin hangi parcalari var / eksik - SADECE RAPOR.
# 2) Mesa 24.3.4 kaynagini indir (resmi SHA256 dogrulamali), /sources'a ac ve
#    atasOS'un kendi araclariyla SADECE 'meson setup' calistir: iris icin ne eksik?
#    Hicbir sey derlenmez, hicbir sey kurulmaz.
# Kullanim: sudo bash /home/eren/atasos-21-gtk-mesa-fizibilite.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
R=/home/eren/atas3-loglar/fizibilite
mkdir -p $A "$T" "$R"
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi

temizle(){
    for m in $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
    umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi (mesgul)"
}
trap temizle EXIT
PC='PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig'
pc(){ chroot $A /bin/sh -c "$PC pkg-config --modversion $1" 2>/dev/null; }

echo "########## 1/3  EKSIK KUTUPHANELER GERCEKTEN YOK MU ##########"
for l in libgtk-3.so.0 libgdk-3.so.0 libcairo.so.2 libpango-1.0.so.0 libgdk_pixbuf-2.0.so.0 libatk-1.0.so.0 libasound.so.2; do
    f=$(find $A/usr $A/opt -xdev -name "$l" 2>/dev/null | head -1)
    printf '  %-26s %s\n' "$l" "${f:+VAR: ${f#$A}}${f:-yok}"
done
echo "  ld.so.conf: $(cat $A/etc/ld.so.conf $A/etc/ld.so.conf.d/* 2>/dev/null | grep -v '^#' | tr '\n' ' ')"

echo
echo "########## 2/3  GTK3 ZINCIRI (Firefox icin) ##########"
printf '  %-28s %s\n' "PAKET (pkg-config)" "SURUM"
for p in glib-2.0 gobject-introspection-1.0 libffi libxml-2.0 dbus-1 \
         freetype2 fontconfig harfbuzz fribidi libpng libjpeg libtiff-4 pixman-1 \
         cairo cairo-gobject pango pangocairo gdk-pixbuf-2.0 atk atspi-2 atk-bridge-2.0 \
         epoxy xkbcommon xi xcursor xinerama xrandr xdamage xcomposite xtst xext \
         wayland-client wayland-protocols wayland-cursor iso-codes shared-mime-info \
         gsettings-desktop-schemas alsa gtk+-3.0; do
    printf '  %-28s %s\n' "$p" "$(pc $p || true)"
done | awk '{ if (NF==1) print $0"  <<< YOK"; else print }'
echo
echo "  --- /sources'ta ilgili tarball'lar ---"
ls $A/sources 2>/dev/null | grep -iE '^(gtk|cairo|pango|gdk-pixbuf|atk|at-spi|harfbuzz|fribidi|libepoxy|alsa|glib|gobject|shared-mime|iso-codes|pixman|libxkbcommon|sassc|libsass)' | sed 's/^/    /'
echo "  sassc (gtk3 derlemesi ister): $(chroot $A /bin/sh -c 'command -v sassc' || echo YOK)"

echo
echo "########## 3/3  MESA 24.3.4 - iris YAPILANDIRMA DENEMESI ##########"
M=mesa-24.3.4
SHA=e641ae27191d387599219694560d221b7feaa91c900bcec46bf444218ed66025   # docs.mesa3d.org/relnotes/24.3.4.html
if [ ! -f "$T/$M.tar.xz" ]; then
    curl -sSfL -o "$T/$M.tar.xz" "https://archive.mesa3d.org/$M.tar.xz" || { echo "  HATA: indirilemedi"; exit 1; }
fi
G=$(sha256sum "$T/$M.tar.xz" | awk '{print $1}')
[ "$G" = "$SHA" ] && echo "  SHA256 ESLESTI ($(du -h "$T/$M.tar.xz" | cut -f1))" || { echo "  HATA: SHA256 UYUSMUYOR, iptal."; exit 1; }
[ -d "$A/sources/$M" ] || tar -xf "$T/$M.tar.xz" -C $A/sources
echo "  kaynak: /sources/$M"

mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts
mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
rm -rf "$A/sources/$M/build-iris-deneme"
chroot $A /bin/bash -c "
  export $PC
  cd /sources/$M && meson setup build-iris-deneme \
    --prefix=/usr --libdir=lib64 --buildtype=release \
    -Dplatforms=x11,wayland -Dgallium-drivers=iris,softpipe -Dvulkan-drivers= \
    -Dllvm=disabled -Dglx=dri -Degl=enabled -Dgbm=enabled -Dvideo-codecs=
" > "$R/mesa-meson-setup.txt" 2>&1
S=$?
echo "  meson setup cikis kodu: $S"
if [ $S -eq 0 ]; then
    echo "  >>> iris YAPILANDIRILABILIYOR (LLVM olmadan). Ozet:"
    grep -A25 -E '^\s*Gallium' "$R/mesa-meson-setup.txt" | head -20 | sed 's/^/    /'
else
    echo "  >>> YAPILANDIRMA BASARISIZ. Son satirlar:"
    tail -15 "$R/mesa-meson-setup.txt" | sed 's/^/    /'
fi
chown -R eren:eren "$R"
echo
echo "  tam cikti: $R/mesa-meson-setup.txt"
echo "  (build-iris-deneme dizini sadece yapilandirma; hicbir sey derlenmedi/kurulmadi)"
