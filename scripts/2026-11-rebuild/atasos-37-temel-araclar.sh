#!/usr/bin/env bash
# GRUP A: atasOS'ta eksik temel araclar. atasOS'un KENDI derleyicisiyle chroot icinde derlenir.
# Surum + MD5: LFS/BLFS 12.4. iw: kernel.org sha256sums; htop/bash-completion: GitHub sha256.
# Her paket once /tmp/stage-<paket>'e kurulur, dosya listesi /var/lib/atasos-paketler/<paket>.list.
# Basarisiz olursa DURUR; tekrar calistirinca kurulu paketleri atlayip kaldigi yerden devam eder.
# Kullanim: sudo bash /home/eren/atasos-37-temel-araclar.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
L=/home/eren/atas3-loglar/derleme-A
K=/sources/atasos-A
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
# ad | adres | toplam (md5:..|sha256:..) | ek dosyalar (adres#md5 ...) | kontrol dosyasi
PKGS=(
"man-pages|https://www.kernel.org/pub/linux/docs/man-pages/man-pages-6.15.tar.xz|md5:16f68d70139dd2bbcae4102be4705753||/usr/share/man/man2/read.2"
"inetutils|https://ftp.gnu.org/gnu/inetutils/inetutils-2.6.tar.xz|md5:401d7d07682a193960bcdecafd03de94||/usr/bin/ping"
"which|https://ftp.gnu.org/gnu/which/which-2.23.tar.gz|md5:1963b85914132d78373f02a84cdb3c86||/usr/bin/which"
"nano|https://www.nano-editor.org/dist/v8/nano-8.6.tar.xz|md5:3b5a70dd65ddee4bd848b620c1638526||/usr/bin/nano"
"zip|https://downloads.sourceforge.net/infozip/zip30.tar.gz|md5:7b74551e63f8ee6aab6fbc86676c0d37||/usr/bin/zip"
"popt|https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x/popt-1.19.tar.gz|md5:eaa2135fddb6eb03f2c87ee1823e5a78||/usr/lib/libpopt.so"
"rsync|https://www.samba.org/ftp/rsync/src/rsync-3.4.1.tar.gz|md5:04ce67866db04fd7a1cde0b78168406e||/usr/bin/rsync"
"libtirpc|https://downloads.sourceforge.net/libtirpc/libtirpc-1.3.6.tar.bz2|md5:8de9e6af16c4bc65ba40d0924745f5b7|https://www.linuxfromscratch.org/patches/blfs/12.4/libtirpc-1.3.6-gcc15_fixes-1.patch#|/usr/lib/libtirpc.so"
"lsof|https://github.com/lsof-org/lsof/releases/download/4.99.5/lsof-4.99.5.tar.gz|md5:00f5844ae3520b5699c249dd424500c2||/usr/bin/lsof"
"cpio|https://ftp.gnu.org/gnu/cpio/cpio-2.15.tar.bz2|md5:3394d444ca1905ea56c94b628b706a0b||/usr/bin/cpio"
"dosfstools|https://github.com/dosfstools/dosfstools/releases/download/v4.2/dosfstools-4.2.tar.gz|md5:49c8e457327dc61efab5b115a27b087a||/usr/sbin/mkfs.fat"
"ntfs-3g|https://github.com/tuxera/ntfs-3g/archive/2022.10.3/ntfs-3g-2022.10.3.tar.gz|md5:65814658dfd6ad06796795c4f3d1d6bc||/usr/bin/ntfs-3g"
"hwdata|https://github.com/vcrhonek/hwdata/archive/v0.398/hwdata-0.398.tar.gz|md5:1ce78576cdde13f0e1953445a98bf173||/usr/share/hwdata/pci.ids"
"pciutils|https://mj.ucw.cz/download/linux/pci/pciutils-3.14.0.tar.gz|md5:f70cf2da9377cb484802e291ea60115d||/usr/bin/lspci"
"libusb|https://github.com/libusb/libusb/releases/download/v1.0.29/libusb-1.0.29.tar.bz2|md5:12d4a782ce606a0582fb5038c16d0f75||/usr/lib/libusb-1.0.so /usr/lib64/libusb-1.0.so"
"usbutils|https://kernel.org/pub/linux/utils/usb/usbutils/usbutils-018.tar.xz|md5:0a351e2241c50a1f026a455dccf24d73||/usr/bin/lsusb"
"iw|https://www.kernel.org/pub/software/network/iw/iw-6.17.tar.xz|sha256:7d182e498289ab39b257da6780d562e415377107f50358ee5b55b8cfe40b1e33||/usr/sbin/iw"
"htop|https://github.com/htop-dev/htop/releases/download/3.5.3/htop-3.5.3.tar.xz|sha256:a8b164386494cb85bb255a415a3f5f80afe7a0c4491da5d113b3a0f951087e65||/usr/bin/htop"
"bash-completion|https://github.com/scop/bash-completion/releases/download/2.18.0/bash-completion-2.18.0.tar.xz|sha256:88bcf85124f77f74f2f2f8bcd16ac4382d807a827ede742a64940c7116aea33f||/usr/share/bash-completion/bash_completion"
"openssh|https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.0p1.tar.gz|md5:689148621a2eaa734497b12bed1c5202||/usr/bin/ssh"
"dejagnu|https://ftp.gnu.org/gnu/dejagnu/dejagnu-1.6.3.tar.gz|md5:68c5208c58236eba447d7d6d1326b821||/usr/bin/runtest"
"libarchive|https://github.com/libarchive/libarchive/releases/download/v3.8.1/libarchive-3.8.1.tar.xz|md5:80fd1a7acc4da7c7d4a5f9f96df6e3ff||/usr/bin/bsdunzip"
"expect|https://prdownloads.sourceforge.net/expect/expect5.45.4.tar.gz|md5:00fce8de158422f5ccd2666512329bd2|https://www.linuxfromscratch.org/patches/lfs/12.4/expect-5.45.4-gcc15-1.patch#0ca4d6bb8d572fbcdb13cb36cd34833e|/usr/bin/expect"
)

# derleme + DESTDIR kurulumu ($D = sahne dizini). Kaynak dizininde calisir.
derle(){ case $1 in
man-pages) echo 'rm -v man3/crypt* ; make -R GIT=false prefix=/usr DESTDIR=$D install' ;;
inetutils) echo "sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
  ./configure --prefix=/usr --bindir=/usr/bin --localstatedir=/var --disable-logger --disable-whois \
     --disable-rcp --disable-rexec --disable-rlogin --disable-rsh --disable-servers
  make; make DESTDIR=\$D install; mkdir -p \$D/usr/sbin; mv -v \$D/usr/bin/ifconfig \$D/usr/sbin/" ;;
which)     echo './configure --prefix=/usr; make; make DESTDIR=$D install' ;;
nano)      echo './configure --prefix=/usr --sysconfdir=/etc --enable-utf8 --docdir=/usr/share/doc/nano-8.6; make; make DESTDIR=$D install' ;;
zip)       echo 'make -f unix/Makefile generic CC="gcc -std=gnu89"; make prefix=$D/usr MANDIR=$D/usr/share/man/man1 -f unix/Makefile install' ;;
popt)      echo './configure --prefix=/usr --disable-static; make; make DESTDIR=$D install' ;;
rsync)     echo './configure --prefix=/usr --disable-xxhash --without-included-zlib; make; make DESTDIR=$D install' ;;
libtirpc)  echo 'patch -Np1 -i ../libtirpc-1.3.6-gcc15_fixes-1.patch
  ./configure --prefix=/usr --sysconfdir=/etc --disable-static --disable-gssapi; make; make DESTDIR=$D install' ;;
lsof)      echo './configure --prefix=/usr --disable-static; make; make DESTDIR=$D install' ;;
cpio)      echo 'sed -e "/^extern int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/" -i src/extern.h
  sed -e "/^int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/" -i src/global.c
  ./configure --prefix=/usr --enable-mt --with-rmt=/usr/libexec/rmt; make; make DESTDIR=$D install' ;;
dosfstools) echo './configure --prefix=/usr --enable-compat-symlinks --mandir=/usr/share/man --docdir=/usr/share/doc/dosfstools-4.2; make; make DESTDIR=$D install' ;;
ntfs-3g)   echo './autogen.sh; ./configure --prefix=/usr --disable-static --with-fuse=internal --docdir=/usr/share/doc/ntfs-3g-2022.10.3
  make; make DESTDIR=$D install; mkdir -p $D/usr/sbin; ln -svf ../bin/ntfs-3g $D/usr/sbin/mount.ntfs' ;;
hwdata)    echo './configure --prefix=/usr --disable-blacklist; make DESTDIR=$D install' ;;
pciutils)  echo "sed -r '/INSTALL/{/PCI_IDS|update-pciids /d; s/update-pciids.8//}' -i Makefile
  make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes
  make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes DESTDIR=\$D install install-lib
  chmod -v 755 \$D/usr/lib/libpci.so*" ;;
libusb)    echo './configure --prefix=/usr --disable-static; make; make DESTDIR=$D install' ;;
usbutils)  echo 'mkdir build; cd build; meson setup .. --prefix=/usr --buildtype=release; ninja; DESTDIR=$D ninja install' ;;
iw)        echo 'make PREFIX=/usr; make PREFIX=/usr DESTDIR=$D install' ;;
htop)      echo './configure --prefix=/usr; make; make DESTDIR=$D install' ;;
bash-completion) echo './configure --prefix=/usr --sysconfdir=/etc; make; make DESTDIR=$D install' ;;
openssh)   echo './configure --prefix=/usr --sysconfdir=/etc/ssh --with-privsep-path=/var/lib/sshd \
     --with-default-path=/usr/bin --with-superuser-path=/usr/sbin:/usr/bin --with-pid-dir=/run
  make; make DESTDIR=$D install
  install -v -m755 contrib/ssh-copy-id $D/usr/bin; install -v -m644 contrib/ssh-copy-id.1 $D/usr/share/man/man1' ;;
dejagnu)   echo 'mkdir -v build; cd build; ../configure --prefix=/usr; make DESTDIR=$D install' ;;
libarchive) echo 'LA=$(ls /usr/lib64/libarchive.so.13* /usr/lib/libarchive.so.13* 2>/dev/null | head -1 || true)
  LDIR=$(dirname ${LA:-/usr/lib/x}); echo "mevcut libarchive: ${LA:-yok} -> libdir=$LDIR"
  ./configure --prefix=/usr --libdir=$LDIR --disable-static; make; make DESTDIR=$D install
  ln -sfv bsdunzip $D/usr/bin/unzip' ;;
expect)    echo 'TD=$(dirname $(find /usr/lib /usr/lib64 -maxdepth 1 -name tclConfig.sh | head -1))
  TH=$(find /usr/include /usr/lib /usr/lib64 -name tcl.h 2>/dev/null | head -1)
  echo "tclConfig.sh: $TD   tcl.h: ${TH:-YOK}"
  if [ -z "$TH" ]; then
    echo "tcl.h YOK - expect atlandi (yalnizca test araci)"
    mkdir -p $D/usr/share/doc/expect-atlandi; echo "tcl.h bulunamadi" > $D/usr/share/doc/expect-atlandi/NEDEN
  else
    patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
    ./configure --prefix=/usr --with-tcl=$TD --enable-shared --disable-rpath --mandir=/usr/share/man --with-tclinclude=$(dirname $TH)
    make; make DESTDIR=$D install; ln -svf expect5.45.4/libexpect5.45.4.so $D$TD/
  fi' ;;
esac; }

# kurulumdan ONCE (gercek sistemde, root) ve SONRA calisacak adimlar
once(){ case $1 in
openssh) echo 'getent group sshd >/dev/null || groupadd -g 50 sshd
  getent passwd sshd >/dev/null || useradd -c "sshd PrivSep" -d /var/lib/sshd -g sshd -s /bin/false -u 50 sshd
  install -v -g sys -m700 -d /var/lib/sshd' ;;
esac; }
sonra(){ case $1 in
inetutils) echo 'setcap cap_net_raw+ep /usr/bin/ping; setcap cap_net_raw+ep /usr/bin/traceroute; getcap /usr/bin/ping /usr/bin/traceroute' ;;
openssh)   echo 'ssh-keygen -A >/dev/null' ;;
esac; }

# ---------------------------------------------------------------- motor
echo "########## GRUP A: TEMEL ARACLAR ##########"
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
        echo "  DURDU. Duzeltilip tekrar calistirilinca kaldigi yerden devam eder."; exit 1
    fi
    so=$(sonra $ad); [ -n "$so" ] && cr "$so" >> "$L/$ad.log" 2>&1
    echo "tamam ($(( $(date +%s)-B ))s, $(wc -l < $A/var/lib/atasos-paketler/$ad.list) dosya)"
    grep -hE "KIRIK BAG|BIRLESTIRILDI" "$L/$ad.log" | sed "s/^/      /"
done

echo
echo "########## unzip ##########"
if [ -e $A/usr/bin/unzip ]; then echo "  unzip zaten var"
elif [ -x $A/usr/bin/bsdunzip ]; then ln -s bsdunzip $A/usr/bin/unzip; echo "/usr/bin/unzip" > $A/var/lib/atasos-paketler/unzip-bag.list; echo "  unzip -> bsdunzip (libarchive)"
else echo "  bsdunzip yok - unzip ayrica derlenmeli"; fi

echo
echo "########## DOGRULAMA ##########"
for c in ping traceroute which nano zip unzip rsync lsof cpio mkfs.fat ntfs-3g lspci lsusb iw htop ssh runtest expect man; do
    p=$(cr "command -v $c" 2>/dev/null); printf '  %-11s %s\n' "$c" "${p:-YOK <<<}"
done
echo "  ping yetkisi: $(cr 'getcap /usr/bin/ping' 2>/dev/null)"
echo "  lspci ornek : $(cr 'lspci | grep -m1 -i vga' 2>/dev/null)"
echo
echo "  derleme kayitlari: $L"
