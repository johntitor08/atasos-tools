#!/usr/bin/env bash
# atasOS systemd'si -PAM ve -ACL derlenmis: girisler logind oturumu olmuyor.
# Sonuc: poweroff reddediliyor, eren journal'i okuyamiyor, masaustu acilsa bile
# /dev/dri (ekran karti), /dev/snd (ses), /dev/input (touchpad) erisimi olmaz.
# Cozum: grup uyelikleri + wheel icin polkit guc kurali + journal grup izni.
# Kullanim: sudo bash /home/eren/atasos-17-gruplar-polkit.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
E=$A/etc
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi

echo "########## 1/4  eren GRUPLARA EKLENIYOR ##########"
cp -p "$E/group" "$E/group.yedek-$TS"
echo "  yedek: /etc/group.yedek-$TS"
for g in video render audio input systemd-journal; do
    line=$(grep -E "^$g:" "$E/group") || { printf '  %-16s GRUP YOK <<<\n' "$g"; continue; }
    mem=$(echo "$line" | cut -d: -f4)
    if echo ",$mem," | grep -q ",eren,"; then
        printf '  %-16s zaten uye\n' "$g"
    else
        new=${mem:+$mem,}eren
        sed -i "s/^$g:\([^:]*\):\([^:]*\):.*/$g:\1:\2:$new/" "$E/group"
        printf '  %-16s eklendi  -> %s\n' "$g" "$(grep -E "^$g:" "$E/group")"
    fi
done

echo
echo "########## 2/4  polkit: wheel kapatabilsin ##########"
RD=$E/polkit-1/rules.d
P=$RD/49-atasos-guc.rules
cat > "$P" <<'EOF'
// atasOS: systemd -PAM derlendigi icin girisler logind oturumu olmuyor ve
// "aktif yerel kullanici" kurali isleyemiyor. wheel uyeleri guc islemlerini yapabilsin.
polkit.addRule(function(action, subject) {
    var izinli = [
        "org.freedesktop.login1.power-off",
        "org.freedesktop.login1.power-off-multiple-sessions",
        "org.freedesktop.login1.reboot",
        "org.freedesktop.login1.reboot-multiple-sessions",
        "org.freedesktop.login1.suspend",
        "org.freedesktop.login1.suspend-multiple-sessions",
        "org.freedesktop.login1.hibernate",
        "org.freedesktop.login1.hibernate-multiple-sessions"
    ];
    if (izinli.indexOf(action.id) >= 0 && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
chown 0:0 "$P"; chmod 644 "$P"
echo "  yazildi: ${P#$A}"
stat -c '  rules.d: %U:%G %a' "$RD"
stat -c '  kural  : %U:%G %a' "$P"

echo
echo "########## 3/4  journal grup izni ##########"
J=$A/var/log/journal
if [ -d "$J" ]; then
    chgrp -R 23 "$J"
    find "$J" -type d -exec chmod 2755 {} +
    find "$J" -type f -name '*.journal*' -exec chmod 640 {} +
    stat -c '  %n  %U:%G %a' "$J" "$J"/* | sed "s|$A||" | head -3
    printf '  dosya ornegi: %s\n' "$(find "$J" -type f -name '*.journal' | head -1 | xargs stat -c '%U:%G %a' 2>/dev/null)"
fi

echo
echo "########## 4/4  DOGRULAMA ##########"
D=0
for g in video render audio input systemd-journal wheel; do
    grep -E "^$g:" "$E/group" | cut -d: -f4 | tr ',' '\n' | grep -qx eren \
        && printf '  %-16s eren UYE\n' "$g" || { printf '  %-16s eren DEGIL <<<\n' "$g"; D=1; }
done
awk -F: 'NF!=4{print "  BOZUK GROUP SATIRI: "$0; b=1} END{exit b}' "$E/group" || D=1
[ -f "$P" ] && echo "  polkit kurali VAR" || { echo "  polkit kurali YOK <<<"; D=1; }
sync
umount $A 2>/dev/null
echo
if [ "$D" -eq 0 ]; then
    echo "  TAMAM. atas3'te dene:"
    echo "    id                      (video,render,audio,input,systemd-journal gorunmeli)"
    echo "    journalctl -b | grep -c unsafe"
    echo "    systemctl poweroff"
else
    echo "  SORUN VAR <<< geri al: cp $E/group.yedek-$TS $E/group"
fi
