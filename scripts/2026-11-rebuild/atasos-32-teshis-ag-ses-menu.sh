#!/usr/bin/env bash
# Masaustu acildi; kalan: DNS/internet, ses, uygulama menusu (Firefox gorunmuyor). SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-32-teshis-ag-ses-menu.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
O=/home/eren/atas3-loglar/teshis-$(date +%m%d-%H%M)
mkdir -p $A "$O"
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
J=$A/var/log/journal
jc(){ journalctl -D "$J" -b 0 --no-pager "$@" 2>/dev/null; }
jc -o short-monotonic > "$O/acilis0.txt"
cp $A/home/eren/.local/share/sddm/xorg-session.log "$O/xorg-session.log" 2>/dev/null

{
echo "################ ACILIS ################"
journalctl -D "$J" --list-boots --no-pager 2>/dev/null | tail -2
jc -k | grep -m1 'Command line'

echo; echo "################ 1. DNS / INTERNET ################"
echo "--- /etc/resolv.conf ---"; ls -l $A/etc/resolv.conf; echo "  hedef: $(readlink -f $A/etc/resolv.conf | sed "s|^$A||")"
cat $A/etc/resolv.conf 2>&1 | sed 's/^/  /'
echo "--- systemd-resolved ---"
ls -l $A/usr/lib/systemd/systemd-resolved 2>&1
ls -l $A/etc/systemd/system/multi-user.target.wants/systemd-resolved.service $A/etc/systemd/system/sysinit.target.wants/systemd-resolved.service 2>&1
jc | grep -E 'systemd-resolved' | head -8
echo "--- NetworkManager dns ayari ---"
cat $A/etc/NetworkManager/NetworkManager.conf $A/etc/NetworkManager/conf.d/*.conf 2>/dev/null | grep -vE '^\s*(#|$)'
jc | grep -E 'NetworkManager.*(dns-mgr|dns|resolv|state is now|Activation: successful|connectivity|policy: set)' | head -15
echo "--- NM'nin TUM dns satirlari ---"
jc | grep -E 'NetworkManager' | grep -iE 'dns|resolv|rc-manager|nameserver' | head -20
echo "--- NM conf.d ---"; ls -la $A/etc/NetworkManager/conf.d/ $A/usr/lib/NetworkManager/conf.d/ 2>&1
for f in $A/etc/NetworkManager/conf.d/*.conf $A/usr/lib/NetworkManager/conf.d/*.conf; do [ -f "$f" ] && { echo "  -- ${f#$A}"; grep -vE '^\s*(#|$)' "$f" | sed 's/^/     /'; }; done
echo "--- systemd-resolved hazir mi ---"
grep -E '^systemd-resolve' $A/etc/passwd $A/etc/group 2>&1
ls $A/usr/lib/sysusers.d/ 2>/dev/null | grep -iE 'resolve|systemd' | sed 's/^/  sysusers: /'
ls -l $A/usr/lib/systemd/system/systemd-resolved.service 2>&1
find $A/etc/systemd/system -name 'systemd-resolved*' 2>/dev/null | sed "s|$A|  etkin: |"
jc | grep -E 'systemd-resolved|resolved\[' | head -6
echo "--- resolvconf komutu (NM 'rc-manager=resolvconf' secmisti) ---"
ls -l $A/usr/bin/resolvconf $A/usr/sbin/resolvconf $A/sbin/resolvconf 2>&1
echo "--- resolv.conf'u degistiren baska bir sey ---"
jc | grep -iE 'resolv\.conf' | head -6
echo "--- nsswitch hosts ---"; grep -E '^hosts' $A/etc/nsswitch.conf 2>&1
echo "--- saat (TLS icin) ---"; jc | grep -iE 'timesyncd|Time has been changed|clock' | head -4

echo; echo "################ 2. SES ################"
jc -k | grep -iE 'snd_hda|hda_intel|hda-codec|ALC256|sof|deferred probe' | head -12
echo "--- PipeWire / WirePlumber ---"
jc | grep -iE 'wireplumber|pipewire' | grep -iE 'alsa|SPA|missing|fail|error' | head -8
echo "--- SPA eklentileri ---"
ls $A/usr/lib*/spa-0.2/ 2>&1
ls $A/usr/lib*/spa-0.2/alsa/ 2>&1 | head
echo "--- pipewire surumu / kaynak ---"
ls -d $A/sources/pipewire* $A/sources/*/pipewire* 2>/dev/null
strings $A/usr/bin/pipewire 2>/dev/null | grep -m1 -oE '^1\.[0-9]+\.[0-9]+$'
echo "--- alsa-lib (pipewire icin gerekli) ---"; ls $A/usr/lib64/libasound.so* 2>&1 | head -3

echo; echo "################ 3. UYGULAMA MENUSU ################"
ls -la $A/etc/xdg/menus/ 2>&1
echo "XDG_MENU_PREFIX ayari:"; grep -rs 'XDG_MENU_PREFIX' $A/etc/profile $A/etc/profile.d $A/etc/environment $A/usr/share/sddm/scripts/Xsession $A/usr/bin/startplasma-x11 2>/dev/null | head
echo "--- .desktop dosyalari ---"
ls $A/usr/share/applications/ 2>/dev/null | wc -l
ls $A/usr/share/applications/ 2>/dev/null | grep -iE 'firefox|konsole|dolphin|systemsettings|calamares'
echo "--- Firefox ---"; ls -l $A/usr/bin/firefox $A/opt/firefox/firefox 2>&1

echo; echo "################ 4. ISO'DA BUNLAR VAR MI ################"
L=/home/eren/atas3-loglar/iso-inceleme/liste.txt
grep -E 'squashfs-root/etc/xdg/menus/[^/]+$' $L | sed 's|squashfs-root||'
grep -E 'squashfs-root/usr/lib(64)?/spa-0\.2/alsa/[^/]+$' $L | sed 's|squashfs-root||'
} > "$O/ozet.txt" 2>&1
chown -R eren:eren "$O"
umount $A 2>/dev/null
echo "  dosyalar: $O"
