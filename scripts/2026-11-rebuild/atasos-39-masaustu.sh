#!/usr/bin/env bash
# GRUP B: masaustu araclari. Xorg uygulamalari (xrdb, xrandr, xinput, xset, xdpyinfo + 28 kucuk arac),
# glxinfo/eglinfo (mesa-demos 9.0.0 kaynaklarindan, paketin tamami degil) ve PowerDevil 6.3.4
# (Plasma'nin guc/PARLAKLIK servisi; atasOS'ta yoktu -> parlaklik kaydiricisi ve Fn tuslari calismiyordu).
# Grup A ile ayni motor: chroot, DESTDIR, dosya listesi, kaldigi yerden devam.
# ISTEGE BAGLI paketler basarisiz olursa grup DURMAZ, sonda raporlanir.
# Kullanim: sudo bash /home/eren/atasos-39-masaustu.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
L=/home/eren/atas3-loglar/derleme-B
K=/sources/atasos-B
mkdir -p $A "$T" "$L"
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
           chown -R eren:eren "$L" "$T" 2>/dev/null; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
mkdir -p $A$K $A/var/lib/atasos-paketler

cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        MAKEFLAGS=-j$(nproc) NINJAJOBS=$(nproc) /bin/bash -euo pipefail -c "$1"; }


# ---------------------------------------------------------------- tarifler
XURL=https://www.x.org/pub/individual/app
LURL=https://www.x.org/pub/individual/lib
PKGS=(
"libXt|$LURL/libXt-1.3.1.tar.xz|md5:9acd189c68750b5028cf120e53c68009||/usr/lib64/libXt.so.6 /usr/lib/libXt.so.6"
"libXmu|$LURL/libXmu-1.2.1.tar.xz|md5:85edefb7deaad4590a03fccba517669f||/usr/lib64/libXmu.so.6 /usr/lib/libXmu.so.6"
"libXpm|$LURL/libXpm-3.5.17.tar.xz|md5:05b5667aadd476d77e9b5ba1a1de213e||/usr/lib64/libXpm.so.4 /usr/lib/libXpm.so.4"
"libXaw|$LURL/libXaw-1.0.16.tar.xz|md5:2a9793533224f92ddad256492265dd82||/usr/lib64/libXaw7.so.7 /usr/lib/libXaw7.so.7"
"iceauth|$XURL/iceauth-1.0.10.tar.xz|md5:30f898d71a7d8e817302970f1976198c||/usr/bin/iceauth"
"mkfontscale|$XURL/mkfontscale-1.2.3.tar.xz|md5:7dcf5f702781bdd4aaff02e963a56270||/usr/bin/mkfontscale"
"sessreg|$XURL/sessreg-1.1.4.tar.xz|md5:b9efe1d21615c474b22439d41981beef||/usr/bin/sessreg"
"setxkbmap|$XURL/setxkbmap-1.3.4.tar.xz|md5:1d61c9f4a3d1486eff575bf233e5776c||/usr/bin/setxkbmap"
"smproxy|$XURL/smproxy-1.0.8.tar.xz|md5:6484cd8ee30354aaaf8f490988f5f6ef||/usr/bin/smproxy"
"xauth|$XURL/xauth-1.1.4.tar.xz|md5:bf7b5a94561c7c98de447ea53afabfc4||/usr/bin/xauth"
"xcmsdb|$XURL/xcmsdb-1.0.7.tar.xz|md5:37063ccf902fe3d55a90f387ed62fe1f||/usr/bin/xcmsdb"
"xcursorgen|$XURL/xcursorgen-1.0.9.tar.xz|md5:f97e81b2c063f6ae9b18d4b4be7543f6||/usr/bin/xcursorgen"
"xdpyinfo|$XURL/xdpyinfo-1.4.0.tar.xz|md5:700556957773d378fa16a65a4406be0a||/usr/bin/xdpyinfo"
"xdriinfo|$XURL/xdriinfo-1.0.8.tar.xz|md5:830a54ef3ba338013e06a1b5b012b4bd||/usr/bin/xdriinfo"
"xev|$XURL/xev-1.2.6.tar.xz|md5:f29d1544f8dd126a1b85e2f7f728672d||/usr/bin/xev"
"xgamma|$XURL/xgamma-1.0.8.tar.xz|md5:687e42aa5afaec37f14da3072651c635||/usr/bin/xgamma"
"xhost|$XURL/xhost-1.0.10.tar.xz|md5:45c7e956941194e5f06a9c7307f5f971||/usr/bin/xhost"
"xinput|$XURL/xinput-1.6.4.tar.xz|md5:8e4d14823b7cbefe1581c398c6ab0035||/usr/bin/xinput"
"xkbcomp|$XURL/xkbcomp-1.4.7.tar.xz|md5:83d711948de9ccac550d2f4af50e94c3||/usr/bin/xkbcomp"
"xkbevd|$XURL/xkbevd-1.1.6.tar.xz|md5:543c0535367ca30e0b0dbcfa90fefdf9||/usr/bin/xkbevd"
"xkbutils|$XURL/xkbutils-1.0.6.tar.xz|md5:07483ddfe1d83c197df792650583ff20||/usr/bin/xkbwatch"
"xkill|$XURL/xkill-1.0.6.tar.xz|md5:f62b99839249ce9a7a8bb71a5bab6f9d||/usr/bin/xkill"
"xlsatoms|$XURL/xlsatoms-1.1.4.tar.xz|md5:da5b7a39702841281e1d86b7349a03ba||/usr/bin/xlsatoms"
"xlsclients|$XURL/xlsclients-1.1.5.tar.xz|md5:ab4b3c47e848ba8c3e47c021230ab23a||/usr/bin/xlsclients"
"xmessage|$XURL/xmessage-1.0.7.tar.xz|md5:ba2dd3db3361e374fefe2b1c797c46eb||/usr/bin/xmessage"
"xmodmap|$XURL/xmodmap-1.0.11.tar.xz|md5:0d66e07595ea083871048c4b805d8b13||/usr/bin/xmodmap"
"xpr|$XURL/xpr-1.2.0.tar.xz|md5:ab6c9d17eb1940afcfb80a72319270ae||/usr/bin/xpr"
"xprop|$XURL/xprop-1.2.8.tar.xz|md5:5ef4784b406d11bed0fdf07cc6fba16c||/usr/bin/xprop"
"xrandr|$XURL/xrandr-1.5.3.tar.xz|md5:dc7680201afe6de0966c76d304159bda||/usr/bin/xrandr"
"xrdb|$XURL/xrdb-1.2.2.tar.xz|md5:c8629d5a0bc878d10ac49e1b290bf453||/usr/bin/xrdb"
"xrefresh|$XURL/xrefresh-1.1.0.tar.xz|md5:55003733ef417db8fafce588ca74d584||/usr/bin/xrefresh"
"xset|$XURL/xset-1.2.5.tar.xz|md5:18ff5cdff59015722431d568a5c0bad2||/usr/bin/xset"
"xsetroot|$XURL/xsetroot-1.1.3.tar.xz|md5:fa9a24fe5b1725c52a4566a62dd0a50d||/usr/bin/xsetroot"
"xvinfo|$XURL/xvinfo-1.1.5.tar.xz|md5:d698862e9cad153c5fefca6eee964685||/usr/bin/xvinfo"
"xwd|$XURL/xwd-1.0.9.tar.xz|md5:b0081fb92ae56510958024242ed1bc23||/usr/bin/xwd"
"xwininfo|$XURL/xwininfo-1.1.6.tar.xz|md5:c91201bc1eb5e7b38933be8d0f7f16a8||/usr/bin/xwininfo"
"xwud|$XURL/xwud-1.0.7.tar.xz|md5:3e741db39b58be4fef705e251947993d||/usr/bin/xwud"
"mesa-demos-info|https://archive.mesa3d.org/demos/mesa-demos-9.0.0.tar.xz|sha256:3046a3d26a7b051af7ebdd257a5f23bfeb160cad6ed952329cdff1e9f1ed496b||/usr/bin/glxinfo"
"milou|https://download.kde.org/stable/plasma/6.3.4/milou-6.3.4.tar.xz|sha256:ae7bd7d22e66e588034fe21a73aa8b376d233e82f44470707b708c1771e3ff37||/usr/lib64/qt6/qml/org/kde/milou/qmldir /usr/lib/qt6/qml/org/kde/milou/qmldir /usr/lib64/qml/org/kde/milou/qmldir"
"powerdevil|https://download.kde.org/stable/plasma/6.3.4/powerdevil-6.3.4.tar.xz|sha256:bb8fb337fd214793396707730b22b8f822135296a6b2ac0c28d774096ab22b5e||/usr/lib64/libexec/org_kde_powerdevil /usr/libexec/org_kde_powerdevil /usr/lib/libexec/org_kde_powerdevil"
)
# zorunlu olmayanlar: basarisiz olursa grup devam eder
ZORUNLU=" libXt libXmu xrdb xrandr xinput xset xdpyinfo mesa-demos-info powerdevil "
XORG_CONFIG="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static"

derle(){ case $1 in
mesa-demos-info) echo 'gcc -O2 -Isrc/glad/include -Isrc/util -o glxinfo src/xdemos/glxinfo.c src/util/glinfo_common.c src/glad/src/glad.c -lGL -lX11 -ldl -lm
  install -Dm755 glxinfo $D/usr/bin/glxinfo
  if gcc -O2 -Isrc/glad/include -Isrc/util -o eglinfo src/egl/opengl/eglinfo.c src/util/glinfo_common.c src/glad/src/glad.c -lEGL -ldl -lm; then
     install -Dm755 eglinfo $D/usr/bin/eglinfo; else echo "eglinfo derlenemedi (EGL basliklari yok) - atlandi"; fi' ;;
milou) echo 'LIBD=$(basename $(dirname $(ls /usr/lib64/libKF6CoreAddons.so.6 /usr/lib/libKF6CoreAddons.so.6 2>/dev/null | head -1 || true)))
  mkdir build; cd build
  cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=$LIBD -DCMAKE_BUILD_TYPE=Release \
     -DBUILD_TESTING=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=ON -DCMAKE_SKIP_INSTALL_RPATH=ON -W no-dev
  make; make DESTDIR=$D install' ;;
powerdevil) echo 'LIBD=$(basename $(dirname $(ls /usr/lib64/libKF6CoreAddons.so.6 /usr/lib/libKF6CoreAddons.so.6 2>/dev/null | head -1 || true)))
  echo "KDE kutuphane dizini: $LIBD   qt: $(command -v qtpaths6 qtpaths 2>/dev/null | head -1)"
  mkdir build; cd build
  cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=$LIBD -DCMAKE_BUILD_TYPE=Release \
     -DBUILD_TESTING=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=ON -DCMAKE_SKIP_INSTALL_RPATH=ON -W no-dev
  make; make DESTDIR=$D install' ;;
libX*) echo 'LDIR=$(dirname $(ls /usr/lib64/libX11.so.6 /usr/lib/libX11.so.6 2>/dev/null | head -1 || true)); echo "X kutuphane dizini: $LDIR"
  ./configure '"$XORG_CONFIG"' --libdir=$LDIR; make; make DESTDIR=$D install' ;;
*)     echo "./configure $XORG_CONFIG; make; make DESTDIR=\$D install; rm -f \$D/usr/bin/xkeystone" ;;
esac; }
once(){ :; }
sonra(){ :; }

# ---------------------------------------------------------------- motor
BASARISIZ=""
echo "########## GRUP B: MASAUSTU ##########"
echo "  p5 bos alan: $(df -h $A | tail -1 | awk '{print $4}')   cekirdek: $(nproc)"
echo
for s in "${PKGS[@]}"; do
    IFS='|' read -r ad url top ekler kontrol <<< "$s"
    printf '  %-16s ' "$ad"
    var=0; for k in $kontrol; do [ -e "$A$k" ] && var=1; done
    if [ $var -eq 1 ]; then
        [ -f $A/var/lib/atasos-paketler/$ad.list ] && echo "zaten kurulu, atlandi" || echo "sistemde zaten var ($kontrol), atlandi"
        continue
    fi
    rm -f $A/var/lib/atasos-paketler/$ad.list   # yarim kalmis onceki denemenin listesi
    # indir + dogrula
    f=$T/$(basename "$url")
    [ -f "$f" ] || curl -sSfL --retry 2 -o "$f" "$url" || { echo "INDIRILEMEDI: $url"; exit 1; }
    tur=${top%%:*}; bek=${top#*:}
    ger=$( [ $tur = md5 ] && md5sum "$f" | cut -d' ' -f1 || sha256sum "$f" | cut -d' ' -f1 )
    [ "$ger" = "$bek" ] || { echo "SAGLAMA TOPLAMI UYUSMUYOR ($tur)"; rm -f "$f"; exit 1; }
    cp "$f" $A$K/
    for e in $ekler; do
        eu=${e%%#*}; em=${e#*#}; ef=$T/$(basename "$eu")
        [ -f "$ef" ] || curl -sSfL -o "$ef" "$eu" || { echo "EK INDIRILEMEDI: $eu"; exit 1; }
        [ -z "$em" ] || [ "$(md5sum "$ef" | cut -d' ' -f1)" = "$em" ] || { echo "EK MD5 UYUSMUYOR: $eu"; exit 1; }
        cp "$ef" $A$K/
    done
    arsiv=$(basename "$f"); dz=$(tar -tf "$f" | head -1 | cut -d/ -f1)
    B=$(date +%s)
    o=$(once $ad); if [ -n "$o" ]; then cr "$o" > "$L/$ad.log" 2>&1 || { echo "ON ADIM BASARISIZ ($L/$ad.log)"; exit 1; }; else : > "$L/$ad.log"; fi
    cr "cd $K && rm -rf $dz /tmp/stage-$ad && tar -xf $arsiv && cd $dz
        export D=/tmp/stage-$ad; mkdir -p \$D
        $(derle $ad)
        for x in bin sbin lib lib64; do if [ -d \$D/\$x ] && [ ! -L \$D/\$x ] && [ -L /\$x ]; then h=\$(readlink -f /\$x); mkdir -p \$D\$h; cp -a \$D/\$x/. \$D\$h/; rm -rf \$D/\$x; echo \"BIRLESTIRILDI: /\$x -> \$h\"; fi; done
        cd \$D && find . -type f -o -type l | sed 's|^\.||' | sort > /var/lib/atasos-paketler/$ad.list
        while read -r f; do if [ -L \"\$f\" ] && [ ! -e \"\$f\" ]; then echo \"KIRIK BAG KALDIRILDI: \$f -> \$(readlink \"\$f\")\" | tee -a /var/lib/atasos-paketler/kirik-baglar.log; rm -f \"\$f\"; fi; done < /var/lib/atasos-paketler/$ad.list
        cp -a \$D/. / && ldconfig && rm -rf \$D" >> "$L/$ad.log" 2>&1
    S=$?
    if [ $S -ne 0 ]; then
        rm -f $A/var/lib/atasos-paketler/$ad.list
        echo "BASARISIZ ($(( ($(date +%s)-B) ))s)"; echo "    --- son satirlar ($L/$ad.log) ---"
        tail -15 "$L/$ad.log" | sed 's/^/    /'
        if [ "${ZORUNLU#* $ad }" = "$ZORUNLU" ]; then echo "  (istege bagli - devam ediliyor)"; BASARISIZ="$BASARISIZ $ad"; continue; fi
        echo "  DURDU. Duzeltilip tekrar calistirilinca kaldigi yerden devam eder."; exit 1
    fi
    so=$(sonra $ad); [ -n "$so" ] && cr "$so" >> "$L/$ad.log" 2>&1
    echo "tamam ($(( $(date +%s)-B ))s, $(wc -l < $A/var/lib/atasos-paketler/$ad.list) dosya)"
    grep -hE "KIRIK BAG|BIRLESTIRILDI" "$L/$ad.log" | sed "s/^/      /"
done

echo
echo "########## DOGRULAMA ##########"
for c in xrdb xrandr xinput xset xdpyinfo xauth xev xprop xwininfo xkill glxinfo eglinfo; do
    p=$(cr "command -v $c" 2>/dev/null); printf '  %-10s %s\n' "$c" "${p:-YOK}"
done
echo "  --- PowerDevil ---"
cr 'ls -l /usr/lib64/libexec/org_kde_powerdevil /usr/libexec/org_kde_powerdevil 2>/dev/null; ls /usr/share/dbus-1/system-services/ | grep -i powerdevil; ls /usr/share/polkit-1/actions/ | grep -i powerdevil; find /usr/lib/systemd/user -name "*powerdevil*"' 2>/dev/null | sed 's/^/    /'
[ -n "$BASARISIZ" ] && echo "  istege bagli olup derlenemeyenler:$BASARISIZ (kayitlar: $L)"
echo
echo "  Bitti. atasOS'u ac (GRUB 3. satir): parlaklik kaydiricisi ve Fn tuslari calismali."
