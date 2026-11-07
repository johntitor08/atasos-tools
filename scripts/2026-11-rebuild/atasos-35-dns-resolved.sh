#!/usr/bin/env bash
# DNS: NetworkManager "dns=default,systemd-resolved" ile DNS'i systemd-resolved'e yolluyor ama
# resolved etkin degil ve "systemd-resolve" kullanicisi yok; rc-manager=file ile de resolv.conf'a yazmadi.
# Cozum: systemd-resolved'i duzgunce etkinlestir (modern varsayilan yol) + yedek DNS.
#   - systemd-resolve kullanici/grubu   - systemd-resolved.service etkin
#   - /etc/resolv.conf -> /run/systemd/resolve/stub-resolv.conf
#   - NetworkManager dns=systemd-resolved   - FallbackDNS=1.1.1.1 9.9.9.9 8.8.8.8
# Degisen her dosya yedeklenir.
# Kullanim: sudo bash /home/eren/atasos-35-dns-resolved.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
TS=$(date +%Y%m%d-%H%M%S)
Y=$A/var/lib/atasos-paketler/yedek-35-$TS
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev; do mountpoint -q $m && umount $m; done; umount $A 2>/dev/null; }
trap temizle EXIT
mount --bind /dev $A/dev; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
mkdir -p "$Y"
cp -a $A/etc/passwd $A/etc/group $A/etc/shadow $A/etc/resolv.conf "$Y/" 2>/dev/null
cp -a $A/etc/NetworkManager/conf.d/90-atasos-dns.conf "$Y/" 2>/dev/null
D=0

echo "########## 1/5  systemd-resolve KULLANICISI ##########"
if grep -q '^systemd-resolve:' $A/etc/passwd; then
    echo "  zaten var: $(grep '^systemd-resolve:' $A/etc/passwd)"
elif [ -x $A/usr/bin/systemd-sysusers ]; then
    echo 'u systemd-resolve - "systemd Resolver"' | chroot $A /usr/bin/systemd-sysusers - 2>&1 | sed 's/^/  /'
    grep -q '^systemd-resolve:' $A/etc/passwd && echo "  olusturuldu: $(grep '^systemd-resolve:' $A/etc/passwd)" || { echo "  OLUSTURULAMADI <<<"; D=1; }
else
    echo "  systemd-sysusers yok <<<"; D=1
fi

echo
echo "########## 2/5  YEDEK DNS ##########"
mkdir -p $A/etc/systemd/resolved.conf.d
cat > $A/etc/systemd/resolved.conf.d/90-atasos.conf <<'EOF'
# atasOS: agdan DNS gelmezse bunlar kullanilir.
[Resolve]
FallbackDNS=1.1.1.1 9.9.9.9 8.8.8.8
EOF
chmod 644 $A/etc/systemd/resolved.conf.d/90-atasos.conf
echo "  /etc/systemd/resolved.conf.d/90-atasos.conf: FallbackDNS=1.1.1.1 9.9.9.9 8.8.8.8"

echo
echo "########## 3/5  systemd-resolved ETKIN ##########"
chroot $A /usr/bin/systemctl enable systemd-resolved.service 2>&1 | sed 's/^/  /'
E=$(find $A/etc/systemd/system -name 'systemd-resolved.service' -o -name 'dbus-org.freedesktop.resolve1.service' 2>/dev/null | sed "s|$A||")
[ -n "$E" ] && echo "$E" | sed 's/^/  etkin: /' || { echo "  etkinlestirilemedi <<<"; D=1; }
e=$(chroot $A /usr/bin/ldd /usr/lib/systemd/systemd-resolved 2>&1 | grep 'not found')
[ -z "$e" ] && echo "  ldd systemd-resolved  TAMAM" || { echo "  ldd EKSIK: $e"; D=1; }

echo
echo "########## 4/5  /etc/resolv.conf -> resolved ##########"
ln -sfn /run/systemd/resolve/stub-resolv.conf $A/etc/resolv.conf
echo "  /etc/resolv.conf -> $(readlink $A/etc/resolv.conf)"
echo "  (dosya acilista olusur; Kubuntu'dan bakinca 'kirik' gorunmesi normaldir)"
N=$(ls $A/usr/lib*/libnss_resolve.so.2 2>/dev/null | head -1)
if [ -n "$N" ]; then echo "  nss-resolve: ${N#$A}"
else echo "  nss-resolve: YOK (sorun degil: nsswitch dns adimina duser, resolv.conf 127.0.0.53 gosterir)"; fi

echo
echo "########## 5/5  NetworkManager ##########"
cat > $A/etc/NetworkManager/conf.d/90-atasos-dns.conf <<'EOF'
# atasOS: DNS'i systemd-resolved yonetir; NetworkManager ona iletir.
[main]
dns=systemd-resolved
EOF
chmod 644 $A/etc/NetworkManager/conf.d/90-atasos-dns.conf
echo "  90-atasos-dns.conf: dns=systemd-resolved"

sync
echo
if [ "$D" -eq 0 ]; then
cat <<'SON'
  TAMAM. atasOS'u ac (GRUB 5. satir), telefonda erisim noktasi acik olsun. Konsole'da:
    resolvectl status | head -20      # wlp0s20f3 altinda "DNS Servers" gorunmeli
    getent hosts archive.org          # bir IP adresi donmeli
  Sonra Firefox'ta bir site ac.
SON
else
    echo "  SORUN VAR <<< yukariya bak. Yedekler: ${Y#$A}"
fi
echo "  Geri alma: yedekteki resolv.conf / passwd / group / 90-atasos-dns.conf geri kopyalanir,"
echo "             'systemctl disable systemd-resolved' (chroot)."
