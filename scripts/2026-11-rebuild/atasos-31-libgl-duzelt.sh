#!/usr/bin/env bash
# SIYAH EKRANIN NEDENI: libGL.so.1 -> libGL.so.1.5.0 = Mesa'nin "xlib" YAZILIM GLX'i (XMesa).
# kwin_x11 / plasmashell bununla cizmeye calisiyor: "XMesaCreateWindowBuffer: depth mismatch",
# "incomplete framebuffer" -> siyah ekran. Gercek GLX libGL.so.1.2.0 (libgallium/iris + DRI3).
# Iki dosyanin SONAME'i ayni (libGL.so.1); ldconfig yuksek numarali olani (1.5.0) secer ->
# bag elle duzeltilse bile geri bozulur. Bu yuzden 1.5.0 SILINMEZ, yedek klasorune TASINIR.
# Kullanim: sudo bash /home/eren/atasos-31-libgl-duzelt.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
L=$A/usr/lib64
TS=$(date +%Y%m%d-%H%M%S)
Y=$A/var/lib/atasos-paketler/yedek-31-libgl-$TS
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev; do mountpoint -q $m && umount $m; done; umount $A 2>/dev/null; }
trap temizle EXIT
mount --bind /dev $A/dev; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys

echo "########## 1/4  ONCE ##########"
ls -la $L/libGL.so* | awk '{print "  "$9, $10, $11, "("$5")"}' | sed "s|$A||g"
for f in $L/libGL.so.1.2.0 $L/libGL.so.1.5.0; do
    [ -f "$f" ] || continue
    printf '  %-20s XMesa:%-2s dri3:%-3s libgallium:%s\n' "$(basename $f)" \
        "$(strings $f | grep -c XMesa)" "$(strings $f | grep -ci dri3)" \
        "$(readelf -d $f | grep -c 'libgallium')"
done
[ -f $L/libGL.so.1.2.0 ] || { echo "  HATA: libGL.so.1.2.0 (gercek GLX) yok. Hicbir sey degismedi."; exit 1; }
readelf -d $L/libGL.so.1.2.0 | grep -q libgallium || { echo "  HATA: 1.2.0 beklenen surucu-GLX'i degil. Hicbir sey degismedi."; exit 1; }
echo "  --- baska dizinlerde libGL.so.1 var mi (golgeleme) ---"
find $A/usr/lib $A/usr/local/lib $A/opt/lib $A/lib64 -maxdepth 1 -name 'libGL.so*' 2>/dev/null | sed "s|$A|    |" || true

echo
echo "########## 2/4  YAZILIM GLX'INI KENARA AL + BAGLARI DUZELT ##########"
mkdir -p "$Y"
cp -a $L/libGL.so $L/libGL.so.1 "$Y/" 2>/dev/null
if [ -f $L/libGL.so.1.5.0 ]; then mv $L/libGL.so.1.5.0 "$Y/"; echo "  libGL.so.1.5.0 -> ${Y#$A}/ (silinmedi)"; fi
ln -sfn libGL.so.1.2.0 $L/libGL.so.1
ln -sfn libGL.so.1     $L/libGL.so
chroot $A /sbin/ldconfig
echo "  libGL.so.1 -> $(readlink $L/libGL.so.1)   (ldconfig sonrasi)"

echo
echo "########## 3/4  DOGRULAMA ##########"
D=0
[ "$(readlink $L/libGL.so.1)" = "libGL.so.1.2.0" ] && echo "  bag ldconfig'ten sonra da dogru      TAMAM" || { echo "  bag yine bozuldu <<<"; D=1; }
P=$(chroot $A /sbin/ldconfig -p | grep -E 'libGL\.so\.1 ' | head -3)
echo "  ldconfig -p:"; echo "$P" | sed 's/^/    /'
echo "$P" | head -1 | grep -q '/usr/lib64/libGL.so.1$' || { echo "  ilk sirada baska bir libGL var <<<"; D=1; }
e=$(chroot $A /usr/bin/ldd /usr/lib64/libGL.so.1 2>&1 | grep 'not found')
[ -z "$e" ] && echo "  ldd libGL.so.1                       TAMAM" || { echo "  ldd EKSIK:"; echo "$e" | sed 's/^/    /'; D=1; }
chroot $A /usr/bin/ldd /usr/bin/kwin_x11 2>/dev/null | grep -E 'libGL\.so|libgallium|libEGL' | sed 's/^/    kwin_x11 -> /'
echo "  --- oturuma yazilim cizimini zorlayan ayar kaldi mi ---"
grep -rlE 'LIBGL_ALWAYS_SOFTWARE=1|KWIN_COMPOSE=N' $A/etc/environment $A/etc/profile $A/etc/profile.d \
    $A/home/eren/.config/plasma-workspace/env $A/home/eren/.profile $A/home/eren/.bash_profile 2>/dev/null \
    | sed "s|$A|    |" || echo "    yok"

echo
echo "########## 4/4  SONUC ##########"
sync
if [ "$D" -eq 0 ]; then
cat <<'SON'
  TAMAM. Yeniden baslat, GRUB'da 5. satir: "atasOS 6.16.1-atas3 3) masaustu / SDDM".
  Masaustu gelirse Konsole'da:  glxinfo -B 2>/dev/null | grep -i renderer
  (glxinfo yoksa Bilgi Merkezi > Grafik). "Mesa Intel(R) UHD Graphics" gormeliyiz.
SON
else
    echo "  SORUN VAR <<< Geri alma: yedek ${Y#$A}"
fi
echo "  Geri alma (gerekirse Kubuntu'dan): yedekteki libGL.so.1.5.0'i /usr/lib64'e geri koy,"
echo "  libGL.so.1 bagini 1.5.0'a cevir, ldconfig."
