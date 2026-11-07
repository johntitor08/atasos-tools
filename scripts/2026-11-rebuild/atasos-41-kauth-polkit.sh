#!/usr/bin/env bash
# PARLAKLIK: PowerDevil'in backlighthelper'i kurulu ama calisamiyor, cunku KAuth 6.13.0 "FAKE" arka uçla derlenmis
# (/usr/plugins/kf6/kauth/backend yok, hicbir KDE yardimcisinin polkit .policy dosyasi yok -> her istek REDDEDILIR).
# 1) KAuth 6.13.0'i polkit-qt6 arka ucuyla yeniden derler (ayni surum, ayni ABI; eski dosyalar yedeklenir).
# 2) /sources altindaki KAuth .actions dosyalarindan eksik polkit politikalarini uretir (PowerDevil vb.).
# Grup A/B ile ayni motor: chroot, DESTDIR, dosya listesi.
# Kullanim: sudo bash /home/eren/atasos-41-kauth-polkit.sh
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

URL=https://download.kde.org/stable/frameworks/6.13/kauth-6.13.0.tar.xz
SHA=a33bf07828d88cf499c8bfe717f02f7e289dcf4f58b8f3aae9e2f95615a8d8d6
TARIH=$(date +%m%d-%H%M)

echo "########## 1/3  ON KONTROL ##########"
cr 'ls /usr/lib64/cmake/PolkitQt6-1/PolkitQt6-1Config.cmake /usr/lib/cmake/PolkitQt6-1/PolkitQt6-1Config.cmake 2>/dev/null | head -1 || true' \
    | sed 's/^/  polkit-qt6 cmake: /' | grep . || { echo "  HATA: polkit-qt6 cmake dosyasi yok, KAuth polkit arka ucu derlenemez."; exit 1; }
cr 'ls /usr/lib/polkit-1/polkitd /usr/lib64/polkit-1/polkitd /usr/libexec/polkitd 2>/dev/null | head -1 || true' \
    | sed 's/^/  polkitd: /' | grep . || { echo "  HATA: polkitd yok."; exit 1; }
echo "  kauth arka ucu (once): $(ls $A/usr/plugins/kf6/kauth/ 2>/dev/null | tr '\n' ' ')"

echo
echo "########## 2/3  KAuth 6.13.0 (polkit-qt6) ##########"
f=$T/$(basename $URL)
[ -f "$f" ] || curl -sSfL --retry 2 -o "$f" "$URL" || { echo "  INDIRILEMEDI: $URL"; exit 1; }
[ "$(sha256sum "$f" | cut -d' ' -f1)" = "$SHA" ] || { echo "  SAGLAMA TOPLAMI UYUSMUYOR"; rm -f "$f"; exit 1; }
cp "$f" $A$K/
B=$(date +%s)
cr "cd $K && rm -rf kauth-6.13.0 /tmp/stage-kauth && tar -xf kauth-6.13.0.tar.xz && cd kauth-6.13.0
    export D=/tmp/stage-kauth; mkdir -p \$D
    LIBD=\$(basename \$(dirname \$(ls /usr/lib64/libKF6CoreAddons.so.6 /usr/lib/libKF6CoreAddons.so.6 2>/dev/null | head -1 || true)))
    mkdir build; cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=\$LIBD -DCMAKE_BUILD_TYPE=Release \
       -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=ON -DCMAKE_SKIP_INSTALL_RPATH=ON \
       -DKAUTH_BACKEND_NAME=PolkitQt6-1 -W no-dev
    make
    find . -name 'kauth_backend_plugin.so' | grep -q . || { echo 'POLKIT ARKA UCU DERLENMEDI (FAKE secildi) - kurulmadi'; exit 1; }
    make DESTDIR=\$D install
    cd \$D && find . -type f -o -type l | sed 's|^\.||' | sort > /var/lib/atasos-paketler/kauth.list
    # uzerine yazilacak eski dosyalarin yedegi
    ( cd / && while read -r x; do if [ -e \"\$x\" ] || [ -L \"\$x\" ]; then echo \"\${x#/}\"; fi; done </var/lib/atasos-paketler/kauth.list ) \
       | tar -C / -cf /var/lib/atasos-paketler/yedek-41-kauth-$TARIH.tar -T -
    cp -a \$D/. / && ldconfig && rm -rf \$D" > "$L/kauth.log" 2>&1
S=$?
if [ $S -ne 0 ]; then
    rm -f $A/var/lib/atasos-paketler/kauth.list
    echo "  BASARISIZ ($(( $(date +%s)-B ))s). Son satirlar ($L/kauth.log):"; tail -20 "$L/kauth.log" | sed 's/^/    /'; exit 1
fi
echo "  tamam ($(( $(date +%s)-B ))s, $(wc -l < $A/var/lib/atasos-paketler/kauth.list) dosya; eski dosyalar: /var/lib/atasos-paketler/yedek-41-kauth-$TARIH.tar)"
echo "  kauth arka ucu (sonra): $(ls $A/usr/plugins/kf6/kauth/ 2>/dev/null | tr '\n' ' ')"

echo
echo "########## 3/3  POLKIT POLITIKALARI ##########"
# Her .actions dosyasindaki ilk [org.x.y.eylem] -> yardimci kimligi org.x.y. Yardimcinin D-Bus servisi kuruluysa
# ve politikasi yoksa kauth-policy-gen ile uretilir.
cr 'GEN=$(find /usr/lib64/libexec /usr/libexec /usr/lib/libexec -name kauth-policy-gen -type f 2>/dev/null | head -1 || true)
    [ -n "$GEN" ] || { echo "  HATA: kauth-policy-gen bulunamadi"; exit 1; }
    echo "  uretec: $GEN"
    mkdir -p /usr/share/polkit-1/actions; : > /var/lib/atasos-paketler/kauth-politika.list
    find /sources -maxdepth 6 -name "*.actions" -type f 2>/dev/null | sort | while read -r a; do
        ilk=$(grep -m1 -E "^\[[a-z0-9._-]+\]$" "$a" | tr -d "[]") || true
        [ -n "$ilk" ] || continue
        id=${ilk%.*}
        if [ ! -e /usr/share/dbus-1/system-services/$id.service ]; then echo "  atlandi (yardimci kurulu degil): $id"; continue; fi
        p=/usr/share/polkit-1/actions/$id.policy
        if [ -e "$p" ]; then echo "  zaten var: $id.policy"; continue; fi
        if (cd "$(dirname "$a")" && "$GEN" "$a" "$p") && [ -s "$p" ]; then
            echo "  URETILDI: $id.policy  ($(grep -c "<action " "$p") eylem)"; echo "$p" >> /var/lib/atasos-paketler/kauth-politika.list
        else echo "  URETILEMEDI: $id ($a)"; rm -f "$p"; fi
    done
    echo "  --- yardimcisi olup politikasi hala OLMAYANLAR ---"
    for s in /usr/share/dbus-1/system-services/org.kde.*.service; do
        id=$(basename "$s" .service); grep -q "/kauth/" "$s" || continue
        [ -e /usr/share/polkit-1/actions/$id.policy ] || echo "    $id"
    done' 2>&1 | tee -a "$L/kauth.log"
echo "  --- PowerDevil politikalari ---"
ls $A/usr/share/polkit-1/actions/ | grep -i powerdevil | sed 's/^/    /' || echo "    YOK (bkz. $L/kauth.log)"
sync
echo
echo "  Bitti. atasOS'u ac (GRUB 3. satir): Fn parlaklik tuslari ve paneldeki parlaklik kaydiricisi calismali."
