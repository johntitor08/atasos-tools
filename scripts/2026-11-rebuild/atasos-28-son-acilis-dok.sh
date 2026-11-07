#!/usr/bin/env bash
# "Acilmadi" - ne acilmadi? Son acilislarin tam kaydini + X kayitlarini doker. SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-28-son-acilis-dok.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
O=/home/eren/atas3-loglar/son-acilis-$(date +%m%d-%H%M)
mkdir -p $A "$O"
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
J=$A/var/log/journal

journalctl -D "$J" --list-boots --no-pager 2>/dev/null | tail -6 > "$O/acilislar.txt"
for b in -2 -1 0; do
    journalctl -D "$J" -b $b -o short-monotonic --no-pager > "$O/acilis$b.txt" 2>/dev/null
done
for f in var/log/Xorg.0.log var/log/Xorg.0.log.old home/eren/.local/share/xorg/Xorg.0.log home/eren/.xsession-errors \
         home/eren/plasma-cikti.txt home/eren/plasma-yazilim.txt \
         var/log/sddm.log home/eren/.local/share/sddm/xorg-session.log home/eren/.local/share/sddm/wayland-session.log \
         var/lib/sddm/.local/share/sddm/xorg-session.log var/lib/sddm/.local/share/sddm/wayland-session.log \
         etc/sddm.conf etc/X11/default-display-manager; do
    [ -f "$A/$f" ] && cp "$A/$f" "$O/$(echo "$f" | tr / _)"
done
{
  echo "p5 son baglanma:"; tune2fs -l /dev/nvme0n1p5 | grep -E 'Last mount time|Last mounted on|Last write time'
  echo; echo "Xorg kayit dosyalarinin tarihleri:"
  ls -la --time-style=full-iso $A/var/log/Xorg.* $A/home/eren/.local/share/xorg/ 2>/dev/null
  echo; echo "SDDM ayar dosyalari:"
  for f in $A/etc/sddm.conf $A/etc/sddm.conf.d/* $A/usr/lib/sddm/sddm.conf.d/*; do
      [ -f "$f" ] && { echo "--- ${f#$A}"; grep -vE '^\s*(#|$)' "$f"; }
  done
} > "$O/durum.txt" 2>&1
chown -R eren:eren "$O"
umount $A 2>/dev/null
echo "  dosyalar: $O"
cat "$O/acilislar.txt" | sed 's/^/  /'
ls -la "$O" | tail -n +4 | awk '{printf "  %8s  %s\n", $5, $9}'
