#!/usr/bin/env bash
# Masaustu (SDDM + Plasma) icin gerekenler yerinde mi? SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-18-masaustu-kontrol.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
O=/home/eren/atas3-loglar/masaustu
mkdir -p $A "$O"
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }

{
echo "=== SDDM yapilandirmasi ==="
for f in $A/etc/sddm.conf $A/etc/sddm.conf.d/* $A/usr/lib/sddm/sddm.conf.d/*; do
    [ -f "$f" ] && { echo "--- ${f#$A} ---"; grep -vE '^\s*(#|$)' "$f"; }
done
echo
echo "=== oturumlar ==="
ls -la $A/usr/share/xsessions/ $A/usr/share/wayland-sessions/ 2>&1
echo
echo "=== SDDM PAM ==="
for f in $A/etc/pam.d/sddm $A/etc/pam.d/sddm-autologin $A/etc/pam.d/sddm-greeter $A/etc/pam.d/login $A/etc/pam.d/system-login $A/etc/pam.d/system-auth $A/etc/pam.d/system-session; do
    [ -f "$f" ] && { echo "--- ${f#$A} ---"; grep -vE '^\s*(#|$)' "$f"; }
done
echo "  pam_systemd.so: $(ls $A/usr/lib*/security/pam_systemd.so 2>/dev/null || echo YOK)"
echo "  pam modul sayisi: $(ls $A/usr/lib*/security/*.so 2>/dev/null | wc -l)"
echo
echo "=== Xorg surucu ve yapilandirma ==="
ls $A/usr/lib*/xorg/modules/drivers/ $A/usr/lib*/xorg/modules/input/ 2>&1
ls -la $A/etc/X11/xorg.conf $A/etc/X11/xorg.conf.d/ $A/usr/share/X11/xorg.conf.d/ 2>&1
for f in $A/etc/X11/xorg.conf $A/etc/X11/xorg.conf.d/*; do
    [ -f "$f" ] && { echo "--- ${f#$A} ---"; grep -vE '^\s*(#|$)' "$f"; }
done
echo "  Xorg ikilisi: $(ls -l $A/usr/bin/Xorg 2>&1)"
echo "  Xorg.wrap   : $(ls -l $A/usr/libexec/Xorg.wrap $A/usr/lib*/xorg/Xorg.wrap 2>/dev/null)"
cat $A/etc/X11/Xwrapper.config 2>/dev/null
echo
echo "=== Mesa DRI suruculeri (Intel icin iris sart) ==="
ls $A/usr/lib*/dri/ 2>&1
ls $A/usr/lib*/libgallium* 2>&1
echo
echo "=== sddm kullanicisi ve dizini ==="
grep -E '^sddm:' $A/etc/passwd $A/etc/group
ls -lnd $A/var/lib/sddm 2>&1
echo
echo "=== onceki SDDM denemeleri (atas3) ==="
for b in $(journalctl -D $A/var/log/journal --list-boots --no-pager 2>/dev/null | tail -12 | awk '{print $1}'); do
    journalctl -D $A/var/log/journal -b $b -k --no-pager 2>/dev/null | grep -q 'Linux version.*atas3' || continue
    n=$(journalctl -D $A/var/log/journal -b $b --no-pager 2>/dev/null | grep -c 'sddm\[')
    [ "$n" -gt 0 ] || continue
    echo "--- acilis $b ($n sddm satiri) ---"
    journalctl -D $A/var/log/journal -b $b --no-pager 2>/dev/null | grep -E 'sddm|Xorg|X\.Org|startplasma|kwin' | head -40
done
echo
echo "=== X sunucu kayitlari ==="
ls -la $A/var/log/Xorg.* $A/var/lib/sddm/.local/share/sddm/ 2>&1
} > "$O/ozet.txt" 2>&1

for f in $A/var/log/Xorg.0.log $A/var/lib/sddm/.local/share/sddm/xorg-session.log $A/var/lib/sddm/.local/share/sddm/wayland-session.log $A/home/eren/.local/share/sddm/xorg-session.log; do
    [ -f "$f" ] && cp "$f" "$O/$(echo ${f#$A} | tr / _)"
done
chown -R eren:eren "$O"
umount $A 2>/dev/null
echo "  dosyalar: $O"
ls -la "$O" | sed 's/^/    /'
