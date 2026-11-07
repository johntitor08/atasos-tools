#!/usr/bin/env bash
# 35. betik systemd-resolve kullanicisini olusturamadi (atasOS'ta systemd-sysusers yok).
# Kubuntu'nun systemd-sysusers'i --root ile atasOS'un passwd/group/shadow dosyalarina yazar;
# bos numarayi atasOS'un kendi dosyalarina bakarak secer.
# Kullanim: sudo bash /home/eren/atasos-35b-resolve-kullanici.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
trap 'umount $A 2>/dev/null' EXIT
Y=$A/var/lib/atasos-paketler/yedek-35b-$TS; mkdir -p "$Y"
cp -a $A/etc/passwd $A/etc/group $A/etc/shadow "$Y/" 2>/dev/null

if grep -q '^systemd-resolve:' $A/etc/passwd; then
    echo "  zaten var: $(grep '^systemd-resolve:' $A/etc/passwd)"
else
    echo 'u systemd-resolve - "systemd Resolver"' | systemd-sysusers --root=$A - 2>&1 | sed 's/^/  /'
fi
echo
P=$(grep '^systemd-resolve:' $A/etc/passwd); G=$(grep '^systemd-resolve:' $A/etc/group)
echo "  passwd: ${P:-YOK <<<}"
echo "  group : ${G:-YOK <<<}"
echo "  shadow: $(grep -c '^systemd-resolve:' $A/etc/shadow 2>/dev/null) satir"
K=$(echo "$P" | cut -d: -f7)
if [ -n "$K" ] && [ ! -e "$A$K" ]; then
    sed -i "s|^\(systemd-resolve:.*:\)$K\$|\1/usr/bin/false|" $A/etc/passwd
    echo "  kabuk $K atasOS'ta yok -> /usr/bin/false yapildi"
fi
U=$(echo "$P" | cut -d: -f3)
n=$(awk -F: -v u="$U" '$3==u' $A/etc/passwd | wc -l)
[ "$n" -eq 1 ] && echo "  UID $U benzersiz  TAMAM" || echo "  UID $U birden fazla kullanicida <<<"
awk -F: 'NF!=7{print "  BOZUK passwd satiri: "$0}' $A/etc/passwd
awk -F: 'NF!=4{print "  BOZUK group satiri: "$0}' $A/etc/group
sync
echo
[ -n "$P" ] && echo "  TAMAM. Artik atasOS'u acabilirsin (GRUB 5. satir)." || echo "  SORUN VAR <<< atasOS'u ACMA. Yedek: ${Y#$A}"
