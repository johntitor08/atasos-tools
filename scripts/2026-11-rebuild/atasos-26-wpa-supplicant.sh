#!/usr/bin/env bash
# wpa_supplicant 2.11'i D-Bus destegiyle (NetworkManager bunu ister) + WPA3 (SAE) ile yeniden derle.
# BLFS 12.4 tarifi + D-Bus blogu. atasOS'un kendi derleyicisiyle chroot icinde.
# Eski ikililer yedeklenir. Ayrica 25. betigin yazdigi YINELENEN D-Bus politikasi kaldirilir.
# Kullanim: sudo bash /home/eren/atasos-26-wpa-supplicant.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
LOG=/home/eren/atas3-loglar/wpa-derleme.log
TS=$(date +%Y%m%d-%H%M%S)
V=wpa_supplicant-2.11; MD5=72a4a00eddb7a499a58113c3361ab094
mkdir -p $A "$T"
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done; chown eren:eren "$LOG" 2>/dev/null; umount $A 2>/dev/null; }
trap temizle EXIT
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
WS=$A/usr/sbin/wpa_supplicant

echo "########## 1/6  MEVCUT wpa_supplicant GERCEKTEN D-Bus'siz mi ##########"
N=$(readelf -d "$WS" 2>/dev/null | grep NEEDED | grep -oE '\[[^]]+\]' | tr -d '[]' | tr '\n' ' ')
echo "  bagli oldugu kutuphaneler: $N"
if echo "$N" | grep -q 'libdbus-1'; then
    echo "  libdbus-1'e BAGLI -> D-Bus destegi aslinda VAR. Yeniden derlemeye gerek yok."
    YENIDEN=0
else
    echo "  libdbus-1 YOK -> D-Bus destegi yok, yeniden derlenecek."
    YENIDEN=1
fi

echo
echo "########## 2/6  YINELENEN POLITIKA TEMIZLIGI ##########"
if [ -f $A/etc/dbus-1/system.d/wpa_supplicant.conf ] && [ -f $A/usr/share/dbus-1/system.d/wpa_supplicant.conf ]; then
    rm -f $A/usr/share/dbus-1/system.d/wpa_supplicant.conf
    echo "  25. betigin yazdigi /usr/share/dbus-1/system.d/wpa_supplicant.conf kaldirildi (asil dosya /etc'de)"
else
    echo "  yineleme yok"
fi

if [ "$YENIDEN" -eq 1 ]; then
echo
echo "########## 3/6  ON KOSULLAR (chroot) ##########"
pc(){ chroot $A /bin/sh -c "PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig pkg-config --modversion $1" 2>/dev/null; }
EK=0
for p in libnl-3.0 libnl-genl-3.0 openssl dbus-1; do
    v=$(pc $p); printf '  %-16s %s\n' "$p" "${v:-YOK <<<}"; [ -n "$v" ] || EK=1
done
[ -f $A/usr/include/readline/readline.h ] && echo "  readline         var" || { echo "  readline         YOK <<<"; EK=1; }
[ "$EK" -eq 0 ] || { echo "  Eksik on kosul var, derlenmedi."; exit 1; }

echo
echo "########## 4/6  KAYNAK (indir + MD5) ##########"
[ -f "$T/$V.tar.gz" ] || curl -sSfL -o "$T/$V.tar.gz" "https://w1.fi/releases/$V.tar.gz" || { echo "  HATA: indirilemedi"; exit 1; }
[ "$(md5sum "$T/$V.tar.gz" | awk '{print $1}')" = "$MD5" ] && echo "  MD5 tamam (BLFS 12.4)" || { echo "  HATA: MD5 UYUSMUYOR"; exit 1; }
mkdir -p $A/sources/wpa; cp "$T/$V.tar.gz" $A/sources/wpa/

echo
echo "########## 5/6  DERLEME ##########"
chroot $A /usr/bin/env -i HOME=/root LC_ALL=C PATH=/usr/bin:/usr/sbin:/bin:/sbin \
  PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
  /bin/bash -euo pipefail -c "
cd /sources/wpa && rm -rf $V && tar -xf $V.tar.gz && cd $V
cat > wpa_supplicant/.config << 'EOF'
CONFIG_BACKEND=file
CONFIG_CTRL_IFACE=y
CONFIG_DEBUG_FILE=y
CONFIG_DEBUG_SYSLOG=y
CONFIG_DEBUG_SYSLOG_FACILITY=LOG_DAEMON
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WEXT=y
CONFIG_DRIVER_WIRED=y
CONFIG_EAP_GTC=y
CONFIG_EAP_LEAP=y
CONFIG_EAP_MD5=y
CONFIG_EAP_MSCHAPV2=y
CONFIG_EAP_OTP=y
CONFIG_EAP_PEAP=y
CONFIG_EAP_TLS=y
CONFIG_EAP_TTLS=y
CONFIG_IEEE8021X_EAPOL=y
CONFIG_IPV6=y
CONFIG_LIBNL32=y
CONFIG_PKCS12=y
CONFIG_READLINE=y
CONFIG_WPS=y
CONFIG_CTRL_IFACE_DBUS=y
CONFIG_CTRL_IFACE_DBUS_NEW=y
CONFIG_CTRL_IFACE_DBUS_INTRO=y
CONFIG_SAE=y
CONFIG_OWE=y
CONFIG_IEEE80211W=y
CFLAGS += -I/usr/include/libnl3
EOF
cd wpa_supplicant && make -j\$(nproc) BINDIR=/usr/sbin LIBDIR=/usr/lib
" > "$LOG" 2>&1 || { echo "  DERLEME BASARISIZ. Son satirlar:"; tail -20 "$LOG" | sed 's/^/    /'; exit 1; }
echo "  derlendi (kayit: $LOG)"

echo
echo "########## 6/6  KURULUM + DOGRULAMA ##########"
Y=$A/var/lib/atasos-paketler/yedek-wpa-$TS; mkdir -p "$Y"
for b in wpa_supplicant wpa_cli wpa_passphrase; do [ -e $A/usr/sbin/$b ] && cp -a $A/usr/sbin/$b "$Y/"; done
echo "  eski ikililer yedeklendi -> ${Y#$A}"
S=$A/sources/wpa/$V
install -m755 $S/wpa_supplicant/wpa_supplicant $S/wpa_supplicant/wpa_cli $S/wpa_supplicant/wpa_passphrase $A/usr/sbin/
install -m644 $S/wpa_supplicant/dbus/fi.w1.wpa_supplicant1.service $A/usr/share/dbus-1/system-services/
install -m644 $S/wpa_supplicant/dbus/dbus-wpa_supplicant.conf $A/etc/dbus-1/system.d/wpa_supplicant.conf
printf '/usr/sbin/wpa_supplicant\n/usr/sbin/wpa_cli\n/usr/sbin/wpa_passphrase\n' > $A/var/lib/atasos-paketler/$V.list
fi

echo
echo "  --- dogrulama ---"
D=0
N=$(readelf -d "$WS" | grep NEEDED | grep -oE '\[[^]]+\]' | tr -d '[]' | tr '\n' ' ')
echo "$N" | grep -q libdbus-1 && echo "  libdbus-1'e bagli   TAMAM" || { echo "  libdbus-1 YOK <<<"; D=1; }
strings "$WS" | grep -q 'fi.w1.wpa_supplicant1' && echo "  D-Bus adi gomulu    TAMAM" || { echo "  D-Bus adi YOK <<<"; D=1; }
e=$(chroot $A /usr/bin/ldd /usr/sbin/wpa_supplicant | grep 'not found'); [ -z "$e" ] && echo "  ldd                 TAMAM" || { echo "  ldd EKSIK: $e"; D=1; }
echo "  surum: $(chroot $A /usr/sbin/wpa_supplicant -v 2>/dev/null | head -1)"
echo "  --- D-Bus etkinlestirme dosyasi ---"; sed 's/^/    /' $A/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service
U=$(ls $A/etc/systemd/system/wpa_supplicant.service $A/usr/lib/systemd/system/wpa_supplicant.service 2>/dev/null | head -1)
echo "  --- ${U#$A} ---"; grep -E '^(Type|BusName|ExecStart)=' "$U" | sed 's/^/    /'
if ! grep -qE '^ExecStart=.*wpa_supplicant.* -u( |$)' "$U"; then
    # D-Bus etkinlestirmesi bu servisi baslatir; -u olmadan NetworkManager ona ulasamaz
    cat > $A/etc/systemd/system/wpa_supplicant.service <<'EOF'
[Unit]
Description=WPA supplicant (D-Bus)
Before=network.target
Wants=network.target

[Service]
Type=dbus
BusName=fi.w1.wpa_supplicant1
ExecStart=/usr/sbin/wpa_supplicant -u

[Install]
WantedBy=multi-user.target
Alias=dbus-fi.w1.wpa_supplicant1.service
EOF
    U=$A/etc/systemd/system/wpa_supplicant.service
    echo "  eski servis -u kullanmiyordu -> /etc/systemd/system/wpa_supplicant.service yazildi (D-Bus kipi)"
fi
grep -qE '^ExecStart=.*wpa_supplicant.* -u( |$)' "$U" && echo "  servis D-Bus kipinde (-u) TAMAM" || { echo "  servis -u ile BASLAMIYOR <<<"; D=1; }
sync
echo
[ "$D" -eq 0 ] && echo "  TAMAM. atas3'te: nmcli device  -> wlp0s20f3 'wifi' olmali; sonra ag simgesinden baglan." \
               || echo "  SORUN VAR <<< yukariya bak."
