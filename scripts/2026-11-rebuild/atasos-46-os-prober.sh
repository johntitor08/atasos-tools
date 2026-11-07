#!/usr/bin/env bash
# os-prober 1.85 (Debian kaynagi): Calamares'in diskteki diger isletim sistemlerini (Windows, Kubuntu...) gormesi
# ("yanina kur") ve kurulan sistemin GRUB menusune onlari eklemesi icin. Grup A/B motoru: chroot, DESTDIR, dosya listesi.
# Sonda os-prober chroot icinde bir kez calistirilir (diger bolumleri SALT-OKUNUR baglayip bakar).
# Kullanim: sudo bash /home/eren/atasos-46-os-prober.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
L=/home/eren/atas3-loglar/derleme-B
K=/sources/atasos-B
F=os-prober_1.85.tar.xz
SHA=f06094db841a214f975e79d66e2a79ea8c2b39b0f762e9d384b2feffd4ae7447
mkdir -p $A "$L"
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/run $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
           chown -R eren:eren "$L" 2>/dev/null; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
[ -f $A/var/lib/atasos-paketler/os-prober.list ] && [ -x $A/usr/bin/os-prober ] && { echo "  os-prober zaten kurulu. Hicbir sey yapilmadi."; exit 0; }
[ "$(sha256sum "$T/$F" | cut -d' ' -f1)" = "$SHA" ] || { echo "HATA: $T/$F yok ya da saglama toplami uyusmuyor"; exit 1; }
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
mount -t tmpfs tmpfs $A/run
mkdir -p $A$K $A/var/lib/atasos-paketler; cp "$T/$F" $A$K/
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin /bin/bash -euo pipefail -c "$1"; }

echo "########## 1/2  DERLEME + KURULUM ##########"
cr "cd $K && rm -rf os-prober-1.85 /tmp/stage-osp && tar -xf $F && cd os-prober-1.85
    make newns
    D=/tmp/stage-osp
    install -Dm755 os-prober \$D/usr/bin/os-prober
    install -Dm755 linux-boot-prober \$D/usr/bin/linux-boot-prober
    install -Dm755 newns \$D/usr/lib/os-prober/newns
    install -Dm644 common.sh \$D/usr/share/os-prober/common.sh
    mkdir -p \$D/var/lib/os-prober
    for p in os-probes os-probes/mounted os-probes/init linux-boot-probes linux-boot-probes/mounted; do
        mkdir -p \$D/usr/lib/\$p
        for f in \$p/common/* \$p/x86/*; do [ -f \"\$f\" ] && install -m755 \"\$f\" \$D/usr/lib/\$p/; done
    done
    install -m755 os-probes/mounted/powerpc/20macosx \$D/usr/lib/os-probes/mounted/
    cd \$D && find . -type f -o -type l | sed 's|^\.||' | sort > /var/lib/atasos-paketler/os-prober.list
    cp -a \$D/. / && rm -rf \$D" > "$L/os-prober.log" 2>&1 || { echo "  BASARISIZ:"; tail -15 "$L/os-prober.log" | sed 's/^/    /'; rm -f $A/var/lib/atasos-paketler/os-prober.list; exit 1; }
echo "  tamam: $(wc -l < $A/var/lib/atasos-paketler/os-prober.list) dosya"
echo "  os-probes: $(ls $A/usr/lib/os-probes/mounted/ | tr '\n' ' ')"
echo "  gerekli araclar: $(for t in blkid lsblk mount umount logger dmsetup grub-mount grub-probe; do printf '%s=%s ' $t "$(cr "command -v $t >/dev/null && echo var || echo YOK")"; done)"

echo
echo "########## 2/2  DENEME (bu laptoptaki diger sistemler) ##########"
cr 'timeout 120 os-prober 2>/dev/null || true' | sed 's/^/  /'
sync
echo
echo "  Bitti. v29 ISO yeniden uretilince Calamares diger sistemleri gorur; kurulan sistemin GRUB'u da onlari listeler."
