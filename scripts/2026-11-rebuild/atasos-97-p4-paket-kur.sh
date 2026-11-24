#!/usr/bin/env bash
# atasos-97: YAYINLANMAMIS (yerel, 82'de denetlenmis) atspkg paketlerini Kubuntu'dan p4'e (kurulu atasOS) KURAR.
#   Gercek donanim denemesi icin: p4'e girip internetten indirmek yerine chroot ile 'atspkg kur' calistirilir
#   (kurulum kancalari da p4'un icinde calisir, tipki p4'te kurmak gibi).
#   - paketler /veri/atasos-paket/paketler/SHA256SUMS ile denetlenir; yalniz adi verilen paketler kurulur
#   - p4 yazilabilir baglanir; yalniz atspkg'nin kurdugu dosyalar degisir. Is bitince her sey ayrilir.
#   - p5'e, Kubuntu'ya, EFI'ye dokunulmaz.
# Kullanim (Konsole'da): sudo bash ~/atasos-97-p4-paket-kur.sh linux-6.18.64-1.atspkg.tar.zst [baska.atspkg.tar.zst ...]
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0 <paket>..."; exit 1; }
[ $# -gt 0 ] || { echo "Kullanim: sudo bash $0 <paket-dosyasi>..."; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi calisiyor. Hicbir sey yapilmadi."; exit 1; }
PK=/veri/atasos-paket/paketler
DEV=/dev/nvme0n1p4
[ "$(blkid -s LABEL -o value $DEV)" = atasos-kurulu ] || { echo "HATA: $DEV etiketi atasos-kurulu degil"; exit 1; }
grep -q "^$DEV " /proc/mounts && { echo "  p4 baska bir yerde bagli (Dolphin?); once ayir. Hicbir sey yapilmadi."; exit 1; }
for f in "$@"; do
    h=$(awk -v f="$f" '$2==f{print $1}' $PK/SHA256SUMS)
    [ -n "$h" ] && [ "$(sha256sum "$PK/$f" 2>/dev/null | cut -d' ' -f1)" = "$h" ] || { echo "HATA: $f paketler/'de yok ya da SHA256SUMS ile tutmuyor"; exit 1; }
done
M=/mnt/atasos-p4
mkdir -p $M
mount $DEV $M || { echo "HATA: p4 baglanamadi"; exit 1; }
temizle(){ cd /; for m in $M/tmp $M/sys $M/proc $M/dev/pts $M/dev; do mountpoint -q $m && umount $m; done; sync; umount $M || echo "  UYARI: p4 ayrilamadi"; }
trap temizle EXIT
[ -x $M/usr/bin/atspkg ] || { echo "HATA: p4'te atspkg yok"; exit 1; }
mount --bind /dev $M/dev; mount --bind /dev/pts $M/dev/pts; mount -t proc proc $M/proc; mount -t sysfs sysfs $M/sys
mount -t tmpfs -o size=2G tmpfs $M/tmp
cr(){ chroot $M /usr/bin/env -i HOME=/root TERM=${TERM:-dumb} LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }
echo "  p4 once: $(ls $M/boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | tr '\n' ' ')"
for f in "$@"; do
    cp "$PK/$f" $M/tmp/ && cr atspkg kur "/tmp/$f" 2>&1 | sed 's/^/    /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  HATA: $f kurulamadi"; exit 1; }
done
echo "  p4 sonra: $(ls $M/boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | tr '\n' ' ')"
for k in $(ls $M/boot/vmlinuz-* | sed 's|.*/vmlinuz-||'); do
    [ -f $M/usr/lib/modules/$k/modules.dep ] && echo "  $k: moduller + modules.dep var" || echo "  $k: modules.dep YOK <<<"
done
cr atspkg listele 2>/dev/null | grep -E '^(linux|atasos-guncelleme) ' | sed 's/^/  kurulu: /'
echo "  TAMAM. Sonraki adim (Kubuntu GRUB menusu): sudo bash ~/atasos-96-p4-cekirdek-grub.sh"
