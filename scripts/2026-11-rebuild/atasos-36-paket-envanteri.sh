#!/usr/bin/env bash
# atasOS'ta hangi temel paketler eksik? LFS 12.4 bolum 8 + gunluk BLFS araclari. SADECE OKUR.
# Her paket icin o paketin kurdugu tipik bir dosya aranir; /sources'ta kaynagi var mi bakilir.
# Kullanim: sudo bash /home/eren/atasos-36-paket-envanteri.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
O=/home/eren/atas3-loglar/envanter-$(date +%m%d-%H%M)
mkdir -p $A "$O"
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
var(){ for p in "$@"; do ls $A$p >/dev/null 2>&1 && return 0; done; return 1; }
kaynak(){ ls $A/sources 2>/dev/null | grep -iE "^$1[-_][0-9]" | grep -vE '\.(patch|sig|asc)$' | head -1; }

tara(){ # baslik, ardindan "paket|kaynak-oneki|dosya1 dosya2 ..." satirlari
    local baslik=$1; shift
    echo "################ $baslik ################"
    local n=0 e=0
    while IFS='|' read -r ad onek dosyalar; do
        [ -z "$ad" ] && continue
        n=$((n+1))
        if var $dosyalar; then printf '  %-18s var\n' "$ad"
        else e=$((e+1)); k=$(kaynak "$onek"); printf '  %-18s EKSIK   kaynak: %s\n' "$ad" "${k:-yok}"; echo "$ad" >> "$O/eksik-$baslik.txt"; fi
    done
    echo "  -> $n paketten $e eksik"; echo
}

{
tara LFS <<'EOF'
man-pages|man-pages|/usr/share/man/man2/read.2*
iana-etc|iana-etc|/etc/services
glibc|glibc|/usr/lib/libc.so.6 /usr/lib64/libc.so.6
zlib|zlib|/usr/lib/libz.so.1 /usr/lib64/libz.so.1
bzip2|bzip2|/usr/bin/bzip2
xz|xz|/usr/bin/xz
lz4|lz4|/usr/bin/lz4
zstd|zstd|/usr/bin/zstd
file|file|/usr/bin/file
readline|readline|/usr/lib/libreadline.so* /usr/lib64/libreadline.so*
m4|m4|/usr/bin/m4
bc|bc|/usr/bin/bc
flex|flex|/usr/bin/flex
tcl|tcl|/usr/bin/tclsh*
expect|expect|/usr/bin/expect
dejagnu|dejagnu|/usr/bin/runtest
pkgconf|pkgconf|/usr/bin/pkgconf /usr/bin/pkg-config
binutils|binutils|/usr/bin/ld
gmp|gmp|/usr/lib/libgmp.so* /usr/lib64/libgmp.so*
mpfr|mpfr|/usr/lib/libmpfr.so* /usr/lib64/libmpfr.so*
mpc|mpc|/usr/lib/libmpc.so* /usr/lib64/libmpc.so*
attr|attr|/usr/bin/getfattr
acl|acl|/usr/bin/getfacl
libcap|libcap|/usr/sbin/setcap /usr/bin/setcap
libxcrypt|libxcrypt|/usr/lib/libcrypt.so* /usr/lib64/libcrypt.so*
shadow|shadow|/usr/sbin/useradd
gcc|gcc|/usr/bin/gcc
ncurses|ncurses|/usr/lib/libncursesw.so* /usr/lib64/libncursesw.so*
sed|sed|/usr/bin/sed
psmisc|psmisc|/usr/bin/killall
gettext|gettext|/usr/bin/gettext
bison|bison|/usr/bin/bison
grep|grep|/usr/bin/grep
bash|bash|/usr/bin/bash
libtool|libtool|/usr/bin/libtool
gdbm|gdbm|/usr/lib/libgdbm.so* /usr/lib64/libgdbm.so*
gperf|gperf|/usr/bin/gperf
expat|expat|/usr/lib/libexpat.so* /usr/lib64/libexpat.so*
inetutils|inetutils|/usr/bin/ping /usr/bin/traceroute /usr/bin/telnet
less|less|/usr/bin/less
perl|perl|/usr/bin/perl
xml-parser|XML-Parser|/usr/lib/perl5/*/site_perl/*/*/XML/Parser.pm /usr/lib/perl5/*/*/XML/Parser.pm
intltool|intltool|/usr/bin/intltoolize
autoconf|autoconf|/usr/bin/autoconf
automake|automake|/usr/bin/automake
openssl|openssl|/usr/bin/openssl
libelf|elfutils|/usr/lib/libelf.so* /usr/lib64/libelf.so*
libffi|libffi|/usr/lib/libffi.so* /usr/lib64/libffi.so*
python3|Python|/usr/bin/python3
ninja|ninja|/usr/bin/ninja
meson|meson|/usr/bin/meson
kmod|kmod|/usr/bin/kmod
coreutils|coreutils|/usr/bin/ls /usr/bin/stat
check|check|/usr/lib/libcheck.so* /usr/lib64/libcheck.so*
diffutils|diffutils|/usr/bin/diff
gawk|gawk|/usr/bin/gawk
findutils|findutils|/usr/bin/find
groff|groff|/usr/bin/groff
grub|grub|/usr/sbin/grub-install /usr/bin/grub-install
gzip|gzip|/usr/bin/gzip
iproute2|iproute2|/usr/sbin/ip /usr/bin/ip
kbd|kbd|/usr/bin/loadkeys
libpipeline|libpipeline|/usr/lib/libpipeline.so* /usr/lib64/libpipeline.so*
make|make|/usr/bin/make
patch|patch|/usr/bin/patch
tar|tar|/usr/bin/tar
texinfo|texinfo|/usr/bin/makeinfo
vim|vim|/usr/bin/vim
man-db|man-db|/usr/bin/man
procps-ng|procps-ng|/usr/bin/ps
util-linux|util-linux|/usr/bin/mount
e2fsprogs|e2fsprogs|/usr/sbin/mke2fs /usr/bin/mke2fs
systemd|systemd|/usr/lib/systemd/systemd
dbus|dbus|/usr/bin/dbus-daemon
EOF

tara BLFS <<'EOF'
iputils(ping)|iputils|/usr/bin/ping
iw|iw|/usr/sbin/iw /usr/bin/iw
wireless-regdb|wireless-regdb|/usr/lib/firmware/regulatory.db /lib/firmware/regulatory.db
xrdb|xrdb|/usr/bin/xrdb
xset|xset|/usr/bin/xset
xrandr|xrandr|/usr/bin/xrandr
xinput|xinput|/usr/bin/xinput
setxkbmap|setxkbmap|/usr/bin/setxkbmap
xdpyinfo|xdpyinfo|/usr/bin/xdpyinfo
mesa-demos(glxinfo)|mesa-demos|/usr/bin/glxinfo
pciutils(lspci)|pciutils|/usr/bin/lspci /usr/sbin/lspci
usbutils(lsusb)|usbutils|/usr/bin/lsusb
which|which|/usr/bin/which
wget|wget|/usr/bin/wget
curl|curl|/usr/bin/curl
git|git|/usr/bin/git
nano|nano|/usr/bin/nano
zip|zip|/usr/bin/zip
unzip|unzip|/usr/bin/unzip
rsync|rsync|/usr/bin/rsync
openssh|openssh|/usr/bin/ssh
lsof|lsof|/usr/bin/lsof /usr/sbin/lsof
htop|htop|/usr/bin/htop
dosfstools|dosfstools|/usr/sbin/mkfs.fat /usr/sbin/mkfs.vfat
ntfs-3g|ntfs-3g|/usr/bin/ntfs-3g /bin/ntfs-3g
sudo|sudo|/usr/bin/sudo
cpio|cpio|/usr/bin/cpio
bash-completion|bash-completion|/usr/share/bash-completion/bash_completion
EOF

tara DAGITIM <<'EOF'
calamares|calamares|/usr/bin/calamares
kpmcore|kpmcore|/usr/lib/libkpmcore.so* /usr/lib64/libkpmcore.so*
yaml-cpp|yaml-cpp|/usr/lib/libyaml-cpp.so* /usr/lib64/libyaml-cpp.so*
boost-python|boost|/usr/lib/libboost_python3*.so* /usr/lib64/libboost_python3*.so*
squashfs-tools|squashfs-tools|/usr/bin/mksquashfs /usr/sbin/mksquashfs
xorriso|libisoburn|/usr/bin/xorriso
mtools|mtools|/usr/bin/mtools /usr/bin/mcopy
efibootmgr|efibootmgr|/usr/sbin/efibootmgr /usr/bin/efibootmgr
parted|parted|/usr/sbin/parted /usr/bin/parted
rsync(kurulum)|rsync|/usr/bin/rsync
EOF
echo "  --- ISO'daki Calamares (karsilastirma) ---"
grep -E 'squashfs-root/(usr/bin/calamares|usr/lib(64)?/libcalamares[^/]*\.so[^/]*|usr/lib(64)?/libkpmcore[^/]*|etc/calamares/settings\.conf)$' \
    /home/eren/atas3-loglar/iso-inceleme/liste.txt 2>/dev/null | sed 's|squashfs-root|    |'
echo

echo "################ OZET ################"
for t in LFS BLFS DAGITIM; do printf '  %-5s eksik: %s\n' "$t" "$( [ -f "$O/eksik-$t.txt" ] && tr '\n' ' ' < "$O/eksik-$t.txt" || echo yok)"; done
echo "  /sources'taki tarball sayisi: $(ls $A/sources 2>/dev/null | grep -cE '\.tar\.(xz|gz|bz2|zst)$|\.tgz$')"
echo "  bos alan (p5): $(df -h $A | tail -1 | awk '{print $4}')"
} 2>&1 | tee "$O/ozet.txt"
chown -R eren:eren "$O"
umount $A 2>/dev/null
echo; echo "  dosyalar: $O"
