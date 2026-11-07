#!/usr/bin/env bash
# Python 3.13'un _ctypes modulu eksik (Python derlenirken libffi yoktu; libffi sonradan kurulmus).
# v20 ISO'daki ayni surum Python'un _ctypes + _ctypes_test modulleri aktarilir (p5'te OLMAYAN 2 dosya, ustune yazma yok).
# Sonda: import ctypes + libc'den gercek bir fonksiyon cagrisi.
# Kullanim: sudo bash /home/eren/atasos-49-python-ctypes.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
SQ=/home/eren/atas3-loglar/iso-inceleme/filesystem.squashfs
DY=usr/lib/python3.13/lib-dynload
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; for m in $A/proc $A/dev; do mountpoint -q $m && umount $m; done; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"' EXIT

echo "########## 1/3  KARSILASTIRMA ##########"
unsquashfs -q -d "$TMP/v20" "$SQ" usr/lib/libpython3.13.so.1.0 "$DY" >/dev/null 2>&1
L=$(ls "$TMP/v20/$DY" | grep -E '^_ctypes(_test)?\.cpython-313-x86_64-linux-gnu\.so$')
[ "$(echo "$L" | grep -c .)" -eq 2 ] || { echo "HATA: v20'de _ctypes bulunamadi"; exit 1; }
cmp -s "$TMP/v20/usr/lib/libpython3.13.so.1.0" "$A/usr/lib/libpython3.13.so.1.0" \
  && echo "  libpython3.13: v20 ile p5 BIREBIR ayni (ayni Python derlemesi)" \
  || echo "  libpython3.13: v20 ile p5 farkli derleme (ayni 3.13 ABI'si; cpython-313 modulleri uyumlu)"
for f in $L; do [ -e "$A/$DY/$f" ] && { echo "  $f zaten var. Hicbir sey yapilmadi."; exit 0; }; done
echo "  libffi (p5): $(ls $A/usr/lib/libffi.so.8* 2>/dev/null | tr '\n' ' ')"

echo
echo "########## 2/3  AKTARIM ##########"
for f in $L; do install -m755 -o root -g root "$TMP/v20/$DY/$f" "$A/$DY/$f"; echo "  /$DY/$f"; done
printf '/%s/%s\n' "$DY" $L > $A/var/lib/atasos-paketler/python-ctypes.list

echo
echo "########## 3/3  DENEME ##########"
mount --bind /dev $A/dev; mount -t proc proc $A/proc
echo "  ldd eksik: $(chroot $A /usr/bin/ldd /$DY/_ctypes.cpython-313-x86_64-linux-gnu.so | grep -c 'not found')"
chroot $A /usr/bin/env -i PATH=/usr/bin:/usr/sbin /usr/bin/python3 -c '
import ctypes, ctypes.util
libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6")
print("  import ctypes: TAMAM, libc.getpid() =", libc.getpid(), " ctypes", ctypes.__version__)' || echo "  DENEME BASARISIZ <<<"
sync
