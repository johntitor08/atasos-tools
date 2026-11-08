#!/bin/bash
# atasOS chroot icinde calisir (atasos-65 cagirir). Flatpak zincirini derler; her paket once DESTDIR'e kurulur,
# baska bir dosyanin ustune yazmadigi denetlenir, sonra /'a kopyalanir ve dosya listesi
# /var/lib/atasos-paketler/<ad>.list'e yazilir.
set -uo pipefail
K=/sources/flatpak-zinciri; P=$K/paket; IS=$K/is; L=/var/lib/atasos-paketler
J=$(nproc)
export MAKEFLAGS=-j$J
export PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig   # /etc/profile ile ayni (polkit lib64'te)
mkdir -p $P $IS $L
ac(){ rm -rf "$IS/$1"; tar -xf "$K/$2" -C "$IS" || exit 1; cd "$IS/$1" || exit 1; }
kur(){ # $1 = paket adi (DESTDIR: $P/$1)
    local d=$P/$1 cak
    [ -d "$d" ] || { echo "  HATA: $1 DESTDIR bos"; exit 1; }
    rm -rf "$d/usr/share/doc" "$d/usr/share/info/dir"
    cak=$(cd "$d" && find . -mindepth 1 ! -type d -printf '%P\n' | while read -r f; do [ -e "/$f" ] && [ ! -d "/$f" ] && echo "/$f"; done)
    if [ -n "$cak" ]; then echo "  UYARI: $1 su dosyalarin ustune yaziyor:"; echo "$cak" | head -20 | sed 's/^/    /'; fi
    ( cd "$d" && find . -mindepth 1 ! -type d -printf '/%P\n' | sort ) > "$L/$1.list"
    cp -a "$d/." / || exit 1
    ldconfig
    echo "  KURULDU: $1 ($(wc -l < "$L/$1.list") dosya)"
}
ac_kur_at(){ # autotools: $1 ad, $2 tarball, $3.. configure secenekleri
    local ad=$1 tb=$2; shift 2
    echo "########## $ad ##########"
    ac "$ad" "$tb"
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static "$@" > ../$ad-configure.log 2>&1 \
        || { tail -30 ../$ad-configure.log; echo "  HATA: $ad configure"; exit 1; }
    make > ../$ad-make.log 2>&1 || { tail -40 ../$ad-make.log; echo "  HATA: $ad make"; exit 1; }
    rm -rf "$P/$ad"; make DESTDIR="$P/$ad" install > ../$ad-install.log 2>&1 || { tail -20 ../$ad-install.log; echo "  HATA: $ad install"; exit 1; }
    kur "$ad"
}
ac_kur_meson(){ # meson: $1 ad, $2 tarball, $3.. meson secenekleri
    local ad=$1 tb=$2; shift 2
    echo "########## $ad ##########"
    ac "$ad" "$tb"
    [ -n "${YAMA:-}" ] && { eval "$YAMA" || { echo "  HATA: $ad yama"; exit 1; }; }
    meson setup b --prefix=/usr --sysconfdir=/etc --localstatedir=/var --buildtype=release "$@" > ../$ad-setup.log 2>&1 \
        || { tail -40 ../$ad-setup.log; echo "  HATA: $ad meson setup"; exit 1; }
    ninja -C b > ../$ad-ninja.log 2>&1 || { tail -40 ../$ad-ninja.log; echo "  HATA: $ad derleme"; exit 1; }
    rm -rf "$P/$ad"; DESTDIR="$P/$ad" meson install -C b --no-rebuild > ../$ad-install.log 2>&1 \
        || { tail -20 ../$ad-install.log; echo "  HATA: $ad install"; exit 1; }
    kur "$ad"
}
atla(){ [ -f "$L/$1.list" ] && [ "${YENIDEN:-0}" != 1 ] && { echo "########## $1: zaten kurulu, atlandi ##########"; return 0; }; return 1; }

# itstool yerine: AppStream yalniz ceviri birlestirmek icin cagiriyor; ceviriler olmadan girdiyi kopyalar.
mkdir -p $K/bin
cat > $K/bin/itstool <<'EOF'
#!/bin/bash
# atasOS: itstool yerine gecici arac (yalniz derleme sirasinda). -j GIRDI -o CIKTI: girdiyi kopyalar.
j= o=
while [ $# -gt 0 ]; do case "$1" in -j) j=$2; shift 2;; -o) o=$2; shift 2;; *) shift;; esac; done
[ -n "$j" ] && [ -n "$o" ] && exec cp "$j" "$o"
exit 0
EOF
chmod 755 $K/bin/itstool

atla libseccomp-2.6.0 || ac_kur_at libseccomp-2.6.0 libseccomp-2.6.0.tar.gz
atla yaml-0.2.5       || ac_kur_at yaml-0.2.5 yaml-0.2.5.tar.gz
atla npth-1.8         || ac_kur_at npth-1.8 npth-1.8.tar.bz2
atla libassuan-3.0.2  || ac_kur_at libassuan-3.0.2 libassuan-3.0.2.tar.bz2
atla libksba-1.6.7    || ac_kur_at libksba-1.6.7 libksba-1.6.7.tar.bz2
atla gnupg-2.4.7      || ac_kur_at gnupg-2.4.7 gnupg-2.4.7.tar.bz2 --disable-doc --disable-sqlite --disable-ldap
atla gpgme-1.24.2     || ac_kur_at gpgme-1.24.2 gpgme-1.24.2.tar.bz2 --enable-languages=cl \
                            --disable-gpg-test --disable-gpgsm-test --disable-gpgconf-test --disable-g13-test
atla libxmlb-0.3.22   || ac_kur_meson libxmlb-0.3.22 libxmlb-0.3.22.tar.xz -Dgtkdoc=false -Dintrospection=false -Dtests=false -Dcli=false
# AppStream kilavuz sayfalari secenekle kapanmiyor ve Docbook XSL istiyor (atasOS'ta yok): docs/ atlanir
atla AppStream-1.0.4  || PATH=$K/bin:$PATH YAMA="sed -i \"/^subdir('docs\\/')/d\" meson.build && ! grep -q \"subdir('docs\" meson.build" ac_kur_meson AppStream-1.0.4 AppStream-1.0.4.tar.xz \
                            -Dstemming=false -Dsystemd=true -Dvapi=false -Dqt=false -Dcompose=false -Dapt-support=false \
                            -Dgir=false -Dsvg-support=false -Dzstd-support=true -Ddocs=false -Dapidocs=false -Dinstall-docs=false
atla bubblewrap-0.11.0 || ac_kur_meson bubblewrap-0.11.0 bubblewrap-0.11.0.tar.xz -Dman=disabled -Dselinux=disabled -Dtests=false
atla xdg-dbus-proxy-0.1.6 || ac_kur_meson xdg-dbus-proxy-0.1.6 xdg-dbus-proxy-0.1.6.tar.xz -Dman=disabled -Dtests=false
atla libostree-2025.2 || ac_kur_at libostree-2025.2 libostree-2025.2.tar.xz \
                            --with-curl --without-soup --without-soup3 --with-crypto=openssl --with-gpgme --without-selinux \
                            --with-libsystemd --with-builtin-grub2-mkconfig --disable-man --disable-gtk-doc --enable-introspection=no
# flatpak'in variant-schema-compiler'i python3 pyparsing modulu istiyor (saf Python, PyPI wheel)
if ! atla pyparsing-3.2.3; then
    echo "########## pyparsing-3.2.3 ##########"
    rm -rf $P/pyparsing-3.2.3
    pip3 install --no-index --no-deps --root $P/pyparsing-3.2.3 --root-user-action=ignore -q $K/pyparsing-3.2.3-py3-none-any.whl \
        || { echo "  HATA: pyparsing"; exit 1; }
    kur pyparsing-3.2.3
fi
atla flatpak-1.16.1   || ac_kur_meson flatpak-1.16.1 flatpak-1.16.1.tar.xz \
                            -Dsystem_bubblewrap=/usr/bin/bwrap -Dsystem_dbus_proxy=/usr/bin/xdg-dbus-proxy \
                            -Dtests=false -Dinstalled_tests=false -Dgtkdoc=disabled -Ddocbook_docs=disabled -Dman=disabled \
                            -Dgir=disabled -Dmalcontent=disabled -Dselinux_module=disabled -Ddconf=disabled \
                            -Dsystem_helper=enabled -Dprivileged_group=wheel
echo "########## DERLEME BITTI ##########"
