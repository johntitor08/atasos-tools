#!/usr/bin/env bash
# 1) WiFi: CachyOS'tan gelen 6 profil "interface-name=wlan0" ile karta kilitli. atasOS'ta kart
#    wlp0s20f3 oldugu icin NetworkManager bu profilleri HIC denemiyor (sadece eduroam denendi).
# 2) Hiz: p5'teki X "No glamor support" -> her sey islemcide. v20 ISO'daki glamor'lu
#    modesetting surucusu + libglamoregl.so aktarilir (ayni Xorg 1.21.1.14).
# Degisen her dosya yedeklenir.
# Kullanim: sudo bash /home/eren/atasos-29-wifi-profil-glamor.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
SQ=/home/eren/atas3-loglar/iso-inceleme/filesystem.squashfs
TS=$(date +%Y%m%d-%H%M%S)
Y=$A/var/lib/atasos-paketler/yedek-29-$TS
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev; do mountpoint -q $m && umount $m; done; umount $A 2>/dev/null; }
trap temizle EXIT
mount --bind /dev $A/dev; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
mkdir -p "$Y"
D=0

echo "########## 1/3  WiFi PROFILLERI: interface-name kilidi ##########"
C=$A/etc/NetworkManager/system-connections
mkdir -p "$Y/system-connections"
n=0
for f in "$C"/*.nmconnection; do
    grep -q '^interface-name=' "$f" || continue
    cp -a "$f" "$Y/system-connections/"
    sed -i '/^interface-name=/d' "$f"
    chown 0:0 "$f"; chmod 600 "$f"
    printf '  %-34s kilit kaldirildi\n' "$(basename "$f")"; n=$((n+1))
done
echo "  $n profil duzeltildi (yedek: ${Y#$A}/system-connections)"
k=$(grep -l '^interface-name=' "$C"/*.nmconnection 2>/dev/null | wc -l)
[ "$k" -eq 0 ] && echo "  kilitli profil kalmadi  TAMAM" || { echo "  hala $k kilitli profil <<<"; D=1; }
b=$(find "$C" -name '*.nmconnection' \( ! -perm 600 -o ! -user root \) | wc -l)
[ "$b" -eq 0 ] && echo "  izinler (root:root 600) TAMAM" || { echo "  $b dosyanin izni yanlis <<<"; D=1; }

echo
echo "########## 2/3  X SUNUCU: glamor ##########"
echo "  p5 Xorg surumu : $(strings $A/usr/libexec/Xorg 2>/dev/null | grep -m1 -oE '^1\.21\.[0-9]+\.[0-9]+$' || echo '?')"
MS=usr/lib64/xorg/modules/drivers/modesetting_drv.so
GL=usr/lib64/xorg/modules/libglamoregl.so
printf '  p5 modesetting glamor dizesi: %s   (0 = glamor'"'"'siz derlenmis)\n' "$(strings $A/$MS 2>/dev/null | grep -ci glamor)"
mkdir -p "$Y/xorg"
for f in $MS $GL; do [ -e "$A/$f" ] && cp -a "$A/$f" "$Y/xorg/"; done
printf '%s\n%s\n' "$MS" "$GL" > /tmp/x29.$$
unsquashfs -q -f -d "$A" -ef /tmp/x29.$$ "$SQ" >/dev/null 2>&1; rm -f /tmp/x29.$$
printf '/%s\n/%s\n' "$MS" "$GL" > $A/var/lib/atasos-paketler/xorg-glamor-iso.list
for f in $MS $GL; do
    [ -e "$A/$f" ] || { echo "  /$f AKTARILAMADI <<<"; D=1; continue; }
    e=$(chroot $A /usr/bin/ldd "/$f" 2>&1 | grep 'not found')
    printf '  %-48s glamor: %-4s ldd: %s\n' "/$f" "$(strings "$A/$f" | grep -ci glamor)" "$([ -z "$e" ] && echo TAMAM || echo "EKSIK <<<")"
    [ -z "$e" ] || { echo "$e" | sed 's/^/      /'; D=1; }
done
echo "  eski dosyalar: ${Y#$A}/xorg"

echo
echo "########## 3/3  SONUC ##########"
sync
if [ "$D" -eq 0 ]; then
cat <<'SON'
  TAMAM. atas3'te masaustunu baslat (bash ~/.bash_profile.vm-plasma). Telefonda
  erisim noktasini ACIK tut; "O1 Next 5G" otomatik baglanmali.

  Masaustu acilinca Konsole'da:
    grep -E 'glamor|renderer' /var/log/Xorg.0.log
    nmcli device
  Beklenen: "glamor initialized" ve wlp0s20f3 'connected'.

  X ACILMAZSA (siyah ekran ya da komut satirina geri donus): guc tusuna kisa bas,
  Kubuntu'ya don. Yedekten geri alinir; atasOS'un icinden bir sey yapman gerekmez.
SON
else
    echo "  SORUN VAR <<< yukariya bak. Geri almak icin yedek: ${Y#$A}"
fi
