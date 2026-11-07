#!/usr/bin/env bash
# 1) libfuse 3.16.2 (BLFS 12.3): ntfs-3g, kio-fuse, AppImage, sshfs ve grub-mount icin.
# 2) grub-mount (GRUB 2.12'den YALNIZ bu arac): os-prober 1.85 bolumlere yalniz grub-mount ile bakiyor;
#    yoksa Calamares/GRUB diger isletim sistemlerini hic goremiyor (v29 sanal makine testinde bulundu).
# 3) NVIDIA MX250: atasOS'ta suruculuz -> PCI otomatik guc yonetimi (kullanilmazken uykuya gecsin, pil).
# NOT: FUSE'un calismasi icin cekirdekte CONFIG_FUSE_FS gerekir -> atasos-48 (atas5).
# Kullanim: sudo bash /home/eren/atasos-47-fuse-grubmount.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
L=/home/eren/atas3-loglar/derleme-B
K=/sources/atasos-B
mkdir -p $A "$T" "$L"
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/run $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
           chown -R eren:eren "$L" "$T" 2>/dev/null; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys; mount -t tmpfs tmpfs $A/run
mkdir -p $A$K $A/var/lib/atasos-paketler
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        MAKEFLAGS=-j$(nproc) NINJAJOBS=$(nproc) /bin/bash -euo pipefail -c "$1"; }
indir(){ # url md5
    local f=$T/$(basename "$1")
    [ -f "$f" ] || curl -sSfL --retry 2 -o "$f" "$1" || { echo "  INDIRILEMEDI: $1"; return 1; }
    [ "$(md5sum "$f" | cut -d' ' -f1)" = "$2" ] || { echo "  MD5 UYUSMUYOR: $f"; rm -f "$f"; return 1; }
    cp "$f" $A$K/; }
# DESTDIR'daki dosyalari listele + kirik baglari at + / altina kopyala (grup A/B motoru)
kur(){ echo "cd \$D && find . -type f -o -type l | sed 's|^\.||' | sort > /var/lib/atasos-paketler/$1.list
    while read -r f; do if [ -L \"\$f\" ] && [ ! -e \"\$f\" ]; then echo \"KIRIK BAG: \$f\"; rm -f \"\$f\"; fi; done < /var/lib/atasos-paketler/$1.list
    cp -a \$D/. / && ldconfig && rm -rf \$D"; }

echo "########## 1/3  libfuse 3.16.2 ##########"
if [ -f $A/var/lib/atasos-paketler/fuse3.list ]; then echo "  zaten kurulu"; else
indir https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.gz b00bf08b27ead4a9411578777e94a1cc || exit 1
cr "cd $K && rm -rf fuse-3.16.2 /tmp/stage-fuse && tar -xf fuse-3.16.2.tar.gz && cd fuse-3.16.2
    sed -i '/^udev/,\$ s/^/#/' util/meson.build
    mkdir build && cd build
    meson setup --prefix=/usr --buildtype=release .. > /dev/null
    ninja
    export D=/tmp/stage-fuse; DESTDIR=\$D ninja install
    chmod u+s \$D/usr/bin/fusermount3
    $(kur fuse3)" > "$L/fuse3.log" 2>&1 || { echo "  BASARISIZ:"; tail -15 "$L/fuse3.log" | sed 's/^/    /'; rm -f $A/var/lib/atasos-paketler/fuse3.list; exit 1; }
echo "  tamam: $(wc -l < $A/var/lib/atasos-paketler/fuse3.list) dosya; fusermount3: $(stat -c '%A' $A/usr/bin/fusermount3)"
fi

echo
echo "########## 2/3  grub-mount (GRUB 2.12) ##########"
if [ -x $A/usr/bin/grub-mount ]; then echo "  zaten var"; else
indir https://ftp.gnu.org/gnu/grub/grub-2.12.tar.xz 60c564b1bdc39d8e43b3aab4bc0fb140 || exit 1
cr "cd $K && rm -rf grub-2.12 /tmp/stage-grubmount && tar -xf grub-2.12.tar.xz && cd grub-2.12
    echo depends bli part_gpt > grub-core/extra_deps.lst
    ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --disable-werror --enable-grub-mount > ../grub-mount-configure.log 2>&1
    grep -E 'grub-mount:' ../grub-mount-configure.log
    grep -q 'grub-mount: Yes' ../grub-mount-configure.log || { echo 'configure grub-mount: Yes demedi'; exit 1; }
    make
    export D=/tmp/stage-grubmount; install -Dm755 grub-mount \$D/usr/bin/grub-mount
    $(kur grub-mount)" > "$L/grub-mount.log" 2>&1 || { echo "  BASARISIZ:"; tail -15 "$L/grub-mount.log" | sed 's/^/    /'; rm -f $A/var/lib/atasos-paketler/grub-mount.list; exit 1; }
grep -E 'grub-mount:' "$L/grub-mount.log" | sed 's/^/  /'
echo "  tamam: $(cr 'grub-mount --version' 2>&1 | head -1); ldd eksik: $(chroot $A /usr/bin/ldd /usr/bin/grub-mount | grep -c 'not found')"
fi

echo
echo "########## 3/3  NVIDIA MX250 guc yonetimi ##########"
R=$A/etc/udev/rules.d/80-atasos-nvidia-guc.rules
cat > $R <<'EOF'
# atasOS: NVIDIA ekran karti (MX250) icin surucu yok; kart bostayken uykuya gecsin (pil omru).
ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="auto"
EOF
echo "/etc/udev/rules.d/80-atasos-nvidia-guc.rules" > $A/var/lib/atasos-paketler/nvidia-guc.list
echo "  ${R#$A} yazildi"
sync
echo
echo "  Bitti. FUSE'un calismasi icin cekirdek atas5 gerekiyor: sudo bash /home/eren/atasos-48-cekirdek-atas5.sh"
