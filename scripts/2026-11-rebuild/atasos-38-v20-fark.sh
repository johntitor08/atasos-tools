#!/usr/bin/env bash
# v20 ISO (3 Agustos) ile p5 (Haziran lfs.img + bugunku duzeltmeler) arasindaki fark:
# v20'de olup p5'te OLMAYAN her sey = Haziran->Agustos arasi eklenip p5'e hic gelmemis olanlar.
# SADECE OKUR.
# Kullanim: sudo bash /home/eren/atasos-38-v20-fark.sh
set -u
export LC_ALL=C   # sort ve comm ayni siralamayi kullansin (tr_TR yerel ayari comm'u bozuyor)
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
L=/home/eren/atas3-loglar/iso-inceleme/liste.txt
O=/home/eren/atas3-loglar/v20-fark
mkdir -p $A "$O"
if mountpoint -q $A || grep -q '^/dev/nvme0n1p5 ' /proc/mounts; then
    echo "  p5 su an baska bir islem tarafindan bagli (derleme suruyor olabilir)."
    echo "  O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1
fi
mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
HARIC='^/(home|root|sources|var|tmp|proc|sys|dev|run|mnt|media|lost\+found|kurtarma|boot)(/|$)'

sed 's|^squashfs-root||' "$L" | grep -E '^/.' | grep -vE "$HARIC" | sort -u > "$O/v20.txt"
(cd $A && find . -xdev 2>/dev/null | sed 's|^\.||' | grep -E '^/.' | grep -vE "$HARIC" | sort -u) > "$O/p5.txt"
# /lib -> usr/lib gibi baglar yuzunden ayni dosyanin iki yazimi olmasin
norm(){ sed -E 's#^/lib64/#/usr/lib64/#; s#^/lib/#/usr/lib/#; s#^/bin/#/usr/bin/#; s#^/sbin/#/usr/sbin/#'; }
norm < "$O/v20.txt" | sort -u > "$O/v20.n"; norm < "$O/p5.txt" | sort -u > "$O/p5.n"
comm -23 "$O/v20.n" "$O/p5.n" > "$O/v20de-var-p5te-yok.txt"
comm -13 "$O/v20.n" "$O/p5.n" > "$O/p5te-var-v20de-yok.txt"
umount $A 2>/dev/null

F="$O/v20de-var-p5te-yok.txt"
{
echo "v20 girdi: $(wc -l < "$O/v20.n")   p5 girdi: $(wc -l < "$O/p5.n")"
echo "v20'de olup p5'te OLMAYAN: $(wc -l < "$F")"
echo "p5'te olup v20'de olmayan: $(wc -l < "$O/p5te-var-v20de-yok.txt")  (bugunku derlemeler vb.)"
echo
echo "=== PROGRAMLAR (/usr/bin, /usr/sbin) ==="
grep -E '^/usr/s?bin/[^/]+$' "$F" | sed 's|.*/||' | column -c 160
echo
echo "=== /opt ==="
grep -E '^/opt/[^/]+$' "$F"
echo
echo "=== KUTUPHANELER (ad bazinda, ilk 150) ==="
grep -E '^/usr/lib(64)?/lib[^/]+\.so[^/]*$' "$F" | sed -E 's|.*/||; s/\.so.*//' | sort -u | head -150 | column -c 160
echo
echo "=== /usr/share altinda YENI dizinler (uygulama/tema verisi) ==="
grep -E '^/usr/share/[^/]+$' "$F" | sed 's|/usr/share/||' | column -c 160
echo
echo "=== /usr/share/applications (.desktop) ==="
grep -E '^/usr/share/applications/[^/]+\.desktop$' "$F" | sed 's|.*/||' | column -c 160
echo
echo "=== tema / gorunum (sddm, plasma look-and-feel, ikon, imlec, duvar kagidi) ==="
grep -E '^/usr/share/(sddm/themes|plasma/look-and-feel|plasma/desktoptheme|icons|wallpapers|color-schemes|aurorae/themes)/[^/]+$' "$F"
echo
echo "=== /etc (yapilandirma) ==="
grep -E '^/etc/' "$F" | grep -vE '^/etc/(ssl/certs|ca-certificates)/' | head -120
echo
echo "=== KDE/Qt eklentileri (ust dizin) ==="
grep -E '^/usr/lib(64)?/(qt6/)?plugins/[^/]+$|^/usr/lib(64)?/qt6/qml/[^/]+$' "$F" | head -40
} > "$O/ozet.txt" 2>&1
chown -R eren:eren "$O"
echo "  bitti: $O/ozet.txt"
head -3 "$O/ozet.txt" | sed 's/^/  /'
