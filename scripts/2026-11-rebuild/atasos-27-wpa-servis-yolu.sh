#!/usr/bin/env bash
# wpa_supplicant.service yanlis yolu cagiriyor: /usr/local/usr/sbin/wpa_supplicant
# Ikili /usr/sbin/wpa_supplicant'ta. D-Bus -> systemd -> bu servis zinciri kirik oldugu icin
# NetworkManager wpa_supplicant'a ulasamaz. /etc altinda dogru yollu bir servis yazilir
# (/usr/lib'deki asil dosyaya dokunulmaz; /etc onu gecersiz kilar).
# Kullanim: sudo bash /home/eren/atasos-27-wpa-servis-yolu.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
trap 'umount $A 2>/dev/null' EXIT

echo "--- yollar ---"
for p in /usr/local/usr/sbin/wpa_supplicant /usr/local/sbin/wpa_supplicant /usr/sbin/wpa_supplicant; do
    printf '  %-38s %s\n' "$p" "$([ -x "$A$p" ] && echo VAR || echo yok)"
done
[ -x $A/usr/sbin/wpa_supplicant ] || { echo "HATA: /usr/sbin/wpa_supplicant yok"; exit 1; }

echo "--- /usr/local altinda baska yanlis yollu birim var mi ---"
grep -lE '/usr/local/usr/' $A/usr/lib/systemd/system/*.service $A/usr/share/dbus-1/system-services/*.service 2>/dev/null | sed "s|$A|  |" || echo "  yok"

O=$A/etc/systemd/system/wpa_supplicant.service
[ -f "$O" ] && cp -p "$O" "$O.yedek-$(date +%Y%m%d-%H%M%S)"
cat > "$O" <<'EOF'
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
chown 0:0 "$O"; chmod 644 "$O"
echo
echo "--- dogrulama ---"
E=$(grep -E '^ExecStart=' "$O" | cut -d= -f2 | awk '{print $1}')
printf '  ExecStart ikilisi: %s  %s\n' "$E" "$([ -x "$A$E" ] && echo 'VAR - TAMAM' || echo 'YOK <<<')"
echo "  /etc'deki birim /usr/lib'dekini gecersiz kilar (systemd onceligi)."
sync
echo
echo "  atas3'te masaustunu baslat, sonra atasOS'IN ICINDEN:"
echo "    nmcli device"
echo "    nmcli device wifi list"
