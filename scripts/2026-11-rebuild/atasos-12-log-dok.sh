#!/usr/bin/env bash
# atas3 acilislarinin (ve kiyas icin Kubuntu'nun) TAM kaydini dosyaya doker. SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-12-log-dok.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
J=$A/var/log/journal
O=/home/eren/atas3-loglar
mkdir -p $A "$O"
mountpoint -q $A || mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }

for b in $(journalctl -D "$J" --list-boots --no-pager 2>/dev/null | tail -8 | awk '{print $1}'); do
    v=$(journalctl -D "$J" -b "$b" -k --no-pager 2>/dev/null | grep -m1 'Linux version' | sed -E 's/.*Linux version ([^ ]+) .*/\1/')
    case "$v" in *atas3*) ;; *) continue ;; esac
    journalctl -D "$J" -b "$b" -k -o short-monotonic --no-pager > "$O/acilis${b}-cekirdek.txt" 2>/dev/null
    journalctl -D "$J" -b "$b"    -o short-monotonic --no-pager > "$O/acilis${b}-tam.txt"     2>/dev/null
    printf '  acilis %-3s %-14s cekirdek %5s satir, tam %5s satir\n' "$b" "$v" \
        "$(wc -l < "$O/acilis${b}-cekirdek.txt")" "$(wc -l < "$O/acilis${b}-tam.txt")"
done

# kiyas: Kubuntu'nun bu acilisindaki cekirdek kaydi (framebuffer calisiyor)
journalctl -b 0 -k -o short-monotonic --no-pager > "$O/kubuntu-cekirdek.txt" 2>/dev/null
cp $A/boot/config-6.16.1-atas3 "$O/config-atas3"
cp /boot/config-$(uname -r) "$O/config-kubuntu"
chown -R eren:eren "$O"
umount $A 2>/dev/null
echo
echo "  dosyalar: $O"
ls -la "$O" | sed 's/^/    /'
