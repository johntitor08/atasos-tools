#!/usr/bin/env bash
# X sunucusu root yetkisiz (rootless) basliyor ve logind oturumu olmadigi icin
# /dev/tty0'i acamiyor: "parse_vt_settings: Cannot open /dev/tty0 (Permission denied)".
# Cozum: Xorg.wrap X'i root olarak baslatsin (logind'siz sistemlerde standart yol).
# Ayrica X icin Turkce klavye.
# Kullanim: sudo bash /home/eren/atasos-19-xwrapper.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
O=/home/eren/atas3-loglar/masaustu
mkdir -p $A "$O"
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi

echo "########## 1/4  SON DENEMENIN X KAYDI ##########"
L=$A/home/eren/.local/share/xorg/Xorg.0.log
if [ -f "$L" ]; then
    cp "$L" "$O/eren-Xorg.0.log"; chown eren:eren "$O/eren-Xorg.0.log"
    grep -E '\(EE\)|\(WW\) .*(tty|VT|drm|card)|Log file|using VT|logind|Running as' "$L" | head -15 | sed 's/^/  /'
else
    echo "  bulunamadi: ${L#$A}"
fi
echo "  --- aygit izinleri (tmpfiles/udev varsayilani) ---"
echo "  Xorg.wrap: $(stat -c '%A %U:%G' $A/usr/libexec/Xorg.wrap)"

echo
echo "########## 2/4  /etc/X11/Xwrapper.config ##########"
mkdir -p $A/etc/X11
W=$A/etc/X11/Xwrapper.config
[ -f "$W" ] && cp -p "$W" "$W.yedek-$(date +%Y%m%d-%H%M%S)"
cat > "$W" <<'EOF'
# atasOS: systemd -PAM derlendi, girisler logind oturumu olmuyor.
# Rootless X /dev/tty0'i acamiyor; X'i root olarak baslat.
allowed_users=console
needs_root_rights=yes
EOF
chown 0:0 "$W"; chmod 644 "$W"
sed 's/^/  /' "$W"

echo
echo "########## 3/4  X icin Turkce klavye ##########"
mkdir -p $A/etc/X11/xorg.conf.d
K=$A/etc/X11/xorg.conf.d/00-keyboard.conf
cat > "$K" <<'EOF'
Section "InputClass"
    Identifier "atasOS klavye"
    MatchIsKeyboard "on"
    Option "XkbLayout" "tr"
EndSection
EOF
chown 0:0 "$K"; chmod 644 "$K"
echo "  yazildi: ${K#$A}"
ls $A/usr/share/X11/xkb/symbols/tr >/dev/null 2>&1 && echo "  xkb 'tr' duzeni: VAR" || echo "  xkb 'tr' duzeni: YOK <<<"

echo
echo "########## 4/4  DOGRULAMA ##########"
D=0
grep -qx 'needs_root_rights=yes' "$W" && echo "  needs_root_rights=yes  TAMAM" || { echo "  <<< yazilamadi"; D=1; }
case "$(stat -c '%A %U' $A/usr/libexec/Xorg.wrap)" in
    -r-s*root|-rws*root) echo "  Xorg.wrap setuid root   TAMAM" ;;
    *) echo "  Xorg.wrap setuid DEGIL <<<"; D=1 ;;
esac
sync
umount $A 2>/dev/null
echo
[ "$D" -eq 0 ] && {
    echo "  TAMAM. atas3'te tekrar:  bash ~/.bash_profile.vm-plasma"
    echo "  Bu kez X kaydi /var/log/Xorg.0.log'a yazilmali (root olarak calistiginin isareti)."
} || echo "  SORUN VAR <<<"
