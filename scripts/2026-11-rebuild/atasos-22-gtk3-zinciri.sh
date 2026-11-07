#!/usr/bin/env bash
# Firefox icin GTK3 zinciri: fribidi, alsa-lib, cairo, pango, gdk-pixbuf, at-spi2-core, gtk3.
# Surumler ve MD5'ler BLFS 12.4'ten. atasOS'un KENDI derleyicisiyle chroot icinde derlenir.
# Her paket once DESTDIR'e kurulur, dosya listesi /var/lib/atasos-paketler/<paket>.list'e yazilir.
# Bir paket basarisiz olursa DURUR.  Sure: ~30-60 dk.
# Kullanim: sudo bash /home/eren/atasos-22-gtk3-zinciri.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
L=/home/eren/atas3-loglar/gtk-derleme
mkdir -p $A "$T" "$L"
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi

temizle(){
    for m in $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
    chown -R eren:eren "$L" "$T" 2>/dev/null
    umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi (mesgul)"
}
trap temizle EXIT

#      ad             md5                                 adres
PKGS=(
"fribidi-1.0.16      333ad150991097a627755b752b87f9ff https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz"
"alsa-lib-1.2.14     d0efd7930da31f0034baddc0b993fa03 https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.14.tar.bz2"
"cairo-1.18.4        db575fb41bbda127e0147e401f36f8ac https://www.cairographics.org/releases/cairo-1.18.4.tar.xz"
"pango-1.56.4        3db267bc07bfd96615c652e9187b85b5 https://download.gnome.org/sources/pango/1.56/pango-1.56.4.tar.xz"
"gdk-pixbuf-2.42.12  f986fdbba5ec6233c96f8b6535811780 https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-2.42.12.tar.xz"
"at-spi2-core-2.56.4 1bdef0e54532c4f3f004d7e2d40e256a https://download.gnome.org/sources/at-spi2-core/2.56/at-spi2-core-2.56.4.tar.xz"
"gtk-3.24.50         0b3c6d1d6fc321a32624e65750b60f5d https://download.gnome.org/sources/gtk/3.24/gtk-3.24.50.tar.xz"
)

echo "########## 1/4  KAYNAKLAR (indir + MD5) ##########"
for s in "${PKGS[@]}"; do
    read -r ad md5 url <<< "$s"
    f=$T/$(basename "$url")
    [ -f "$f" ] || curl -sSfL -o "$f" "$url" || { echo "  HATA: $ad indirilemedi"; exit 1; }
    [ "$(md5sum "$f" | awk '{print $1}')" = "$md5" ] || { echo "  HATA: $ad MD5 UYUSMUYOR"; rm -f "$f"; exit 1; }
    printf '  %-22s MD5 tamam\n' "$ad"
done
mkdir -p $A/sources/gtk-zinciri
for s in "${PKGS[@]}"; do
    read -r ad md5 url <<< "$s"
    cp "$T/$(basename "$url")" $A/sources/gtk-zinciri/
done

echo
echo "########## 2/4  CHROOT HAZIRLIGI ##########"
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts
mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
LIBDIR=$(chroot $A /bin/sh -c 'PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig pkg-config --variable=libdir glib-2.0')
LD=$(basename "$LIBDIR")
echo "  glib'in libdir'i: $LIBDIR  -> yeni paketler de --libdir=$LD"
echo "  meson : $(chroot $A /usr/bin/meson --version)   ninja: $(chroot $A /usr/bin/ninja --version)"
mkdir -p $A/var/lib/atasos-paketler

cr(){ # chroot icinde, derleme ortamiyla
    chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        MAKEFLAGS=-j$(nproc) NINJAJOBS=$(nproc) \
        /bin/bash -euo pipefail -c "$1"
}

MS="--prefix=/usr --libdir=$LD --sysconfdir=/etc --buildtype=release --wrap-mode=nofallback"
declare -A AYAR=(
 [fribidi]="meson setup build $MS -Ddocs=false -Dtests=false"
 [alsa-lib]="./configure --prefix=/usr --libdir=/usr/$LD --sysconfdir=/etc --disable-static"
 [cairo]="meson setup build $MS -Dtests=disabled -Dgtk_doc=false"
 [pango]="meson setup build $MS -Dintrospection=disabled -Ddocumentation=false -Dbuild-testsuite=false -Dbuild-examples=false"
 [gdk-pixbuf]="meson setup build $MS -Dtiff=disabled -Dman=false -Dintrospection=disabled -Dinstalled_tests=false -Dtests=false"
 [at-spi2-core]="meson setup build $MS -Dintrospection=disabled -Ddocs=false -Dgtk2_atk_adaptor=false"
 [gtk]="meson setup build $MS -Dintrospection=false -Dgtk_doc=false -Dman=false -Ddemos=false -Dexamples=false -Dtests=false"
)

echo
echo "########## 3/4  DERLEME ##########"
for s in "${PKGS[@]}"; do
    read -r ad md5 url <<< "$s"
    ad_kok=${ad%-*}                      # fribidi-1.0.16 -> fribidi
    arsiv=$(basename "$url")
    if [ -f "$A/var/lib/atasos-paketler/$ad.list" ]; then
        printf '  %-22s zaten kurulu, atlandi\n' "$ad"; continue
    fi
    printf '  %-22s %s  ' "$ad" "$(date +%H:%M:%S)"
    B=$(date +%s)
    if [ "$ad_kok" = alsa-lib ]; then
        DERLE="make && make DESTDIR=/tmp/stage-$ad install"
    else
        DERLE="ninja -C build && DESTDIR=/tmp/stage-$ad ninja -C build install"
    fi
    cr "
      cd /sources/gtk-zinciri && rm -rf $ad /tmp/stage-$ad && tar -xf $arsiv && cd $ad
      ${AYAR[$ad_kok]}
      $DERLE
      cd /tmp/stage-$ad && find . -type f -o -type l | sed 's|^\.||' | sort > /var/lib/atasos-paketler/$ad.list
      cp -a /tmp/stage-$ad/. /
      ldconfig
      rm -rf /tmp/stage-$ad
    " > "$L/$ad.log" 2>&1
    S=$?
    if [ $S -ne 0 ]; then
        echo "BASARISIZ ($(( ($(date +%s)-B)/60 )) dk)"
        echo "    --- son satirlar ($L/$ad.log) ---"
        tail -20 "$L/$ad.log" | sed 's/^/    /'
        echo "  DURDU. Onceki paketler kurulu kaldi; bu paket kurulmadi."
        exit 1
    fi
    echo "tamam ($(( ($(date +%s)-B)/60 )) dk, $(wc -l < $A/var/lib/atasos-paketler/$ad.list) dosya)"
done

echo
echo "########## 4/4  ONBELLEKLER + FIREFOX KONTROLU ##########"
cr "gdk-pixbuf-query-loaders --update-cache; gtk-query-immodules-3.0 --update-cache; glib-compile-schemas /usr/share/glib-2.0/schemas" \
    > "$L/onbellek.log" 2>&1 && echo "  pixbuf / immodules / gsettings onbellekleri guncellendi"
EKS=$(for b in libxul.so libmozgtk.so firefox-bin; do chroot $A /usr/bin/ldd /opt/firefox/$b 2>/dev/null; done \
      | grep 'not found' | grep -vE 'lib(moz|nss|nspr|plc|plds|smime|ssl3|gkcodecs|lgpllibs)' | sort -u)
if [ -z "$EKS" ]; then
    echo "  Firefox'un sistemden istedigi kutuphanelerin HEPSI var."
else
    echo "  Hala eksik:"; echo "$EKS" | sed 's/^/    /'
fi
echo
echo "  kurulum listeleri: /var/lib/atasos-paketler/"
echo "  derleme kayitlari: $L"
