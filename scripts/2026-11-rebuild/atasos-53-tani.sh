#!/usr/bin/env bash
# SALT-OKUNUR tani: menude Firefox simgesi, arayuz dili (Ingilizce oldu), PipeWire ALSA eklentisi, son oturum gunlugu.
# p5 salt-okunur baglanir, hicbir sey degistirilmez. Cikti: ~/atas3-loglar/tani-53-<tarih>.txt
# Kullanim: sudo bash /home/eren/atasos-53-tani.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
A=/mnt/atasos; H=$A/home/eren
O=/home/eren/atas3-loglar/tani-53-$(date +%m%d-%H%M).txt
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
trap 'cd /; umount $A 2>/dev/null; chown eren:eren "$O" 2>/dev/null' EXIT
{
echo "########## FIREFOX SIMGESI ##########"
for d in $A/usr/share/applications $A/usr/local/share/applications $H/.local/share/applications; do
    for f in $(grep -l -iE '^Exec=.*firefox' $d/*.desktop 2>/dev/null); do
        echo "  ${f#$A}: $(grep -m1 -E '^Name=' $f) | $(grep -m1 -E '^Icon=' $f) | $(grep -m1 -E '^Exec=' $f)"; done; done
echo "  hicolor index.theme: $(ls -la $A/usr/share/icons/hicolor/index.theme 2>&1 | awk '{print $5, $NF}')"
echo "  hicolor firefox: $(ls $A/usr/share/icons/hicolor/*/apps/firefox.png 2>/dev/null | sed 's|.*/hicolor/||; s|/apps/firefox.png||' | tr '\n' ' ')"
echo "  icon-theme.cache: $(ls -la $A/usr/share/icons/hicolor/icon-theme.cache 2>&1 | awk '{print $5, $6, $7, $8}')"
echo "  kdeglobals [Icons]: $(grep -A1 '^\[Icons\]' $H/.config/kdeglobals 2>/dev/null | tail -1)"
echo "  menu sik kullanilanlar:"; grep -rhoE 'applications:[^",]*firefox[^",]*|preferred://browser' $H/.config/plasma-org.kde.plasma.desktop-appletsrc $H/.local/share/kactivitymanagerd/resources/ 2>/dev/null | sort -u | sed 's/^/    /'
grep -hE '^(favorites|favoritesPortedToKAstats|launchers)=' $H/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | cut -c1-200 | sed 's/^/    /'
echo "  kullanici ksycoca: $(ls $H/.cache/ksycoca6_* 2>/dev/null | wc -l) dosya, tarih: $(ls -l --time-style=+%m-%d_%H:%M $H/.cache/ksycoca6_* 2>/dev/null | awk '{print $6}' | head -1)"
echo
echo "########## DIL ##########"
echo "  /etc/locale.conf: $(cat $A/etc/locale.conf 2>/dev/null | tr '\n' ' ')"
echo "  plasma-localerc: $(cat $H/.config/plasma-localerc 2>/dev/null | tr '\n' ' ')"
echo "  kdeglobals [Locale]/[Translations]: $(grep -A2 -E '^\[(Locale|Translations)\]' $H/.config/kdeglobals 2>/dev/null | tr '\n' ' ')"
echo "  ~/.config/plasma-workspace/env: $(ls $H/.config/plasma-workspace/env/ 2>/dev/null | tr '\n' ' ')"
grep -hE 'LANG|LC_|LANGUAGE' $H/.config/plasma-workspace/env/*.sh $H/.bash_profile $H/.profile $H/.bashrc $A/etc/profile.d/*.sh 2>/dev/null | grep -v '^#' | sed 's/^/    /' | head
echo "  tr_TR yerel ayari derlenmis mi: $(ls $A/usr/lib/locale/ 2>/dev/null | tr '\n' ' ')"
echo "  plasma tr cevirisi: $(ls $A/usr/share/locale/tr/LC_MESSAGES/ 2>/dev/null | grep -cE '^plasma|^kate')"
echo
echo "########## SES (PipeWire ALSA eklentisi) ##########"
ls -la $A/usr/lib*/spa-0.2/alsa/ 2>&1 | sed 's/^/  /' | head -5
ls $A/usr/share/alsa-card-profile 2>&1 | head -3 | sed 's/^/  acp: /'
echo
echo "########## SON OTURUM ##########"
echo "  plasma-yazilim.txt: $(find $H -maxdepth 3 -name 'plasma-yazilim*' 2>/dev/null | sed "s|$A||" | tr '\n' ' ')"
f=$(find $H -maxdepth 3 -name 'plasma-yazilim*' 2>/dev/null | head -1); [ -n "$f" ] && { echo "  --- ilk 15 satir ---"; head -15 "$f" | cut -c1-200 | sed 's/^/    /'; }
echo "  --- ~/.local/share/sddm/xorg-session.log (son 40) ---"
tail -40 $H/.local/share/sddm/xorg-session.log 2>/dev/null | cut -c1-200 | sed 's/^/    /'
echo "  --- son acilisin SDDM/oturum kayitlari ---"
J=$A/var/log/journal; [ -d $J ] && journalctl -D $J -b -1 --no-pager 2>/dev/null | grep -aiE 'sddm|startplasma|kwin|plasmashell.*(error|fail)|session' | tail -25 | cut -c1-200 | sed 's/^/    /' || echo "    (kalici journal yok)"
} > "$O" 2>&1
cat "$O"; echo; echo "  kaydedildi: $O"
