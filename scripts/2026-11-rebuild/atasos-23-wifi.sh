#!/usr/bin/env bash
# atasOS'ta WiFi: firmware + kayitli aglar + NetworkManager polkit izni.
# atas3 cekirdegi zstd sikistirmasini okumaz (sadece XZ), firmware ACILARAK kopyalanir.
# Kullanim: sudo bash /home/eren/atasos-23-wifi.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
W=/home/eren/cachyos-kurtarma/wifi
FW=$A/usr/lib/firmware
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
trap 'umount $A 2>/dev/null' EXIT

echo "########## 1/4  iwlwifi FIRMWARE ##########"
echo "  kart: Intel Comet Lake PCH-LP CNVi WiFi (8086:02f0)"
echo "  Kubuntu'nun yukledigi surum: QuZ-a0-jf-b0-77"
n=0
for f in /lib/firmware/iwlwifi-QuZ-a0-jf-b0-*.ucode.zst; do
    [ -e "$f" ] || continue
    h=$(basename "$f" .zst)
    if [ -e "$FW/$h" ] || [ -e "$FW/$h.xz" ]; then continue; fi
    zstd -qdf "$f" -o "$FW/$h" && n=$((n+1))
done
chown 0:0 $FW/iwlwifi-QuZ-a0-jf-b0-*.ucode 2>/dev/null
chmod 644 $FW/iwlwifi-QuZ-a0-jf-b0-*.ucode 2>/dev/null
echo "  kopyalanan: $n dosya"
ls $FW/iwlwifi-QuZ-a0-jf-b0-*.ucode 2>/dev/null | sed "s|$A||" | sed 's/^/    /'

echo
echo "  --- regulatory.db (kayitlarda 'failed with error -2' diyordu) ---"
for f in regulatory.db regulatory.db.p7s; do
    if [ -e "$FW/$f" ]; then printf '    %-20s zaten var\n' "$f"
    else cp /lib/firmware/$f "$FW/$f" && chown 0:0 "$FW/$f" && chmod 644 "$FW/$f" && printf '    %-20s kopyalandi\n' "$f"; fi
done

echo
echo "########## 2/4  KAYITLI AGLAR ##########"
D=$A/etc/NetworkManager/system-connections
mkdir -p "$D"
k=0
for f in "$W"/*.nmconnection; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    if [ -e "$D/$b" ]; then printf '  %-28s zaten var, atlandi\n' "$b"; continue; fi
    cp "$f" "$D/$b"; chown 0:0 "$D/$b"; chmod 600 "$D/$b"; k=$((k+1))
    printf '  %-28s kuruldu\n' "$b"
done
echo "  toplam yeni: $k"
echo "  --- izinler (NetworkManager 600 ve root:root olmayanlari REDDEDER) ---"
ls -l "$D" | tail -n +2 | awk '{printf "    %s %s:%s  %s\n", $1, $3, $4, $9}' | head -10

echo
echo "########## 3/4  NetworkManager POLKIT IZNI ##########"
P=$A/etc/polkit-1/rules.d/50-atasos-ag.rules
cat > "$P" <<'EOF'
// atasOS: systemd -PAM derlendigi icin girisler logind oturumu olmuyor,
// NetworkManager'in "aktif yerel kullanici" kurali isleyemiyor.
// wheel uyeleri agi yonetebilsin.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
chown 0:0 "$P"; chmod 644 "$P"
echo "  yazildi: ${P#$A}"

echo
echo "########## 4/4  DOGRULAMA ##########"
d=0
[ -e "$FW/iwlwifi-QuZ-a0-jf-b0-77.ucode" ] && echo "  firmware 77       VAR" || { echo "  firmware 77       YOK <<<"; d=1; }
[ -e "$FW/regulatory.db" ] && echo "  regulatory.db     VAR" || { echo "  regulatory.db     YOK <<<"; d=1; }
c=$(ls "$D"/*.nmconnection 2>/dev/null | wc -l)
echo "  kayitli ag        $c adet"
[ "$c" -gt 0 ] || d=1
b=$(find "$D" -name '*.nmconnection' ! -perm 600 -o -name '*.nmconnection' ! -user root 2>/dev/null | wc -l)
[ "$b" -eq 0 ] && echo "  ag dosyasi izinleri TAMAM" || { echo "  $b dosyanin izni yanlis <<<"; d=1; }
[ -e "$P" ] && echo "  polkit ag kurali  VAR" || { echo "  polkit ag kurali  YOK <<<"; d=1; }
sync
echo
if [ "$d" -eq 0 ]; then
cat <<'SON'
  TAMAM. atas3'u ac (3. satir), sonra:

    bash ~/.bash_profile.vm-plasma     # masaustu
    # Plasma acilinca: sag alttaki ag simgesinden "O1 Next 5G" sec
    # ya da komut satirindan:  nmcli device wifi connect "O1 Next 5G"

  Baglandiktan sonra Firefox'u dene: menuden ya da terminalden 'firefox'.
  Ekran kucuk gelirse: Sistem Ayarlari > Ekran ve Monitor > Olcek > %200
SON
else
    echo "  SORUN VAR <<< yukariya bak."
fi
