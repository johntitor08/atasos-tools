#!/usr/bin/env bash
# NetworkManager WiFi eklentisi eksik: "'wifi' plugin not available; creating generic device".
# 1) libnm-device-plugin-wifi.so'yu v20 ISO'dan al (NM 1.56.0, p5 ile ayni surum).
# 2) wpa_supplicant'in D-Bus destegi + etkinlestirme dosyalari (NM onu D-Bus ile cagirir).
# 3) regulatory.db: cfg80211 gomulu oldugu icin disk baglanmadan once araniyor -> acilis sonrasi yeniden yukle.
# Kullanim: sudo bash /home/eren/atasos-25-wifi-eklenti.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
SQ=/home/eren/atas3-loglar/iso-inceleme/filesystem.squashfs
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev; do mountpoint -q $m && umount $m; done; umount $A 2>/dev/null; }
trap temizle EXIT
mount --bind /dev $A/dev; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
D=0

echo "########## 1/4  NetworkManager WiFi EKLENTISI ##########"
echo "  p5 NetworkManager: $(chroot $A /usr/sbin/NetworkManager --version 2>/dev/null)"
P=usr/lib64/NetworkManager/1.56.0/libnm-device-plugin-wifi.so
if [ -e "$A/$P" ]; then echo "  zaten var"
else
    printf '%s\n' "$P" > /tmp/nm-ef.$$
    unsquashfs -q -f -d "$A" -ef /tmp/nm-ef.$$ "$SQ" >/dev/null 2>&1; rm -f /tmp/nm-ef.$$
    echo "/$P" > $A/var/lib/atasos-paketler/nm-wifi-eklentisi.list
fi
if [ -e "$A/$P" ]; then
    e=$(chroot $A /usr/bin/ldd "/$P" 2>&1 | grep 'not found')
    [ -z "$e" ] && echo "  /$P  TAMAM (ldd eksiksiz)" || { echo "  EKSIK KUTUPHANE:"; echo "$e" | sed 's/^/    /'; D=1; }
else echo "  AKTARILAMADI <<<"; D=1; fi

echo
echo "########## 2/4  wpa_supplicant + D-Bus ##########"
WS=""; for p in usr/sbin/wpa_supplicant usr/bin/wpa_supplicant sbin/wpa_supplicant; do [ -x "$A/$p" ] && { WS=/$p; break; }; done
[ -n "$WS" ] || { echo "  wpa_supplicant YOK <<<"; exit 1; }
echo "  ikili: $WS  ($(chroot $A $WS -v 2>/dev/null | head -1))"
if strings "$A$WS" | grep -q 'fi.w1.wpa_supplicant1'; then echo "  D-Bus destegi: VAR"
else echo "  D-Bus destegi: YOK <<< (CONFIG_CTRL_IFACE_DBUS_NEW ile yeniden derlenmeli)"; D=1; fi
e=$(chroot $A /usr/bin/ldd "$WS" 2>&1 | grep 'not found'); [ -z "$e" ] && echo "  ldd: TAMAM" || { echo "  ldd EKSIK:"; echo "$e" | sed 's/^/    /'; D=1; }

SVC=$A/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service
POL=$A/usr/share/dbus-1/system.d/wpa_supplicant.conf
UNIT=$A/usr/lib/systemd/system/wpa_supplicant.service
ls $A/usr/share/dbus-1/system.d/*wpa* $A/etc/dbus-1/system.d/*wpa* 2>/dev/null | sed "s|$A|  mevcut politika: |"
if [ ! -f "$SVC" ]; then
    mkdir -p "$(dirname "$SVC")"
    cat > "$SVC" <<EOF
[D-BUS Service]
Name=fi.w1.wpa_supplicant1
Exec=$WS -u
User=root
SystemdService=wpa_supplicant.service
EOF
    echo "  yazildi: ${SVC#$A}"
else echo "  var: ${SVC#$A}"; fi
if ! ls $A/usr/share/dbus-1/system.d/*wpa* $A/etc/dbus-1/system.d/*wpa* >/dev/null 2>&1; then
    mkdir -p "$(dirname "$POL")"
    cat > "$POL" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="fi.w1.wpa_supplicant1"/>
    <allow send_destination="fi.w1.wpa_supplicant1"/>
    <allow send_interface="fi.w1.wpa_supplicant1"/>
    <allow receive_sender="fi.w1.wpa_supplicant1" receive_type="signal"/>
  </policy>
  <policy context="default">
    <deny own="fi.w1.wpa_supplicant1"/>
    <deny send_destination="fi.w1.wpa_supplicant1"/>
    <deny receive_sender="fi.w1.wpa_supplicant1" receive_type="signal"/>
  </policy>
</busconfig>
EOF
    echo "  yazildi: ${POL#$A}"
fi
if [ ! -f "$UNIT" ] && [ ! -f "$A/etc/systemd/system/wpa_supplicant.service" ]; then
    cat > "$UNIT" <<EOF
[Unit]
Description=WPA supplicant
Before=network.target
Wants=network.target

[Service]
Type=dbus
BusName=fi.w1.wpa_supplicant1
ExecStart=$WS -u

[Install]
WantedBy=multi-user.target
Alias=dbus-fi.w1.wpa_supplicant1.service
EOF
    echo "  yazildi: ${UNIT#$A}"
else echo "  var: wpa_supplicant.service"; fi
chmod 644 "$SVC" "$POL" "$UNIT" 2>/dev/null; chown 0:0 "$SVC" "$POL" "$UNIT" 2>/dev/null

echo
echo "########## 3/4  regulatory.db ACILIS SONRASI ##########"
IW=""; for p in usr/sbin/iw usr/bin/iw sbin/iw; do [ -x "$A/$p" ] && { IW=/$p; break; }; done
if [ -n "$IW" ]; then
    cat > $A/etc/systemd/system/atasos-regdb.service <<EOF
[Unit]
Description=atasOS: WiFi bolge veritabanini yeniden yukle (cfg80211 gomulu, diskten once araniyor)
After=local-fs.target
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=$IW reg reload

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p $A/etc/systemd/system/multi-user.target.wants
    ln -sfn /etc/systemd/system/atasos-regdb.service $A/etc/systemd/system/multi-user.target.wants/atasos-regdb.service
    echo "  iw var ($IW) -> atasos-regdb.service etkinlestirildi"
else
    echo "  iw YOK -> atlandi. (baglantiyi engellemez; 5 GHz'de bazi kanallar pasif kalir)"
fi

echo
echo "########## 4/4  SONUC ##########"
sync
if [ "$D" -eq 0 ]; then
cat <<'SON'
  TAMAM. atas3'te masaustunu baslat, sonra:
    nmcli device                          # wlp0s20f3 artik 'wifi' gorunmeli
    nmcli device wifi list                # aglar listelenmeli
    nmcli device wifi connect "O1 Next 5G"
  ya da Plasma'daki ag simgesinden sec.
SON
else
    echo "  SORUN VAR <<< yukariya bak."
fi
