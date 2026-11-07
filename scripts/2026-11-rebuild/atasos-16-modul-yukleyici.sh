#!/usr/bin/env bash
# atasOS systemd'si -KMOD derlenmis: udev surucu modullerini OTOMATIK YUKLEYEMIYOR.
# Sonuc: i915 (ekran karti), intel_lpss_pci + hid_multitouch (touchpad), iwlwifi (WiFi) hic yuklenmiyor.
# Cozum: udev her aygit icin MODALIAS'i /sbin/modprobe'a versin (klasik LFS yontemi).
# Ayrica eren'in PATH'ine /usr/sbin eklenir (poweroff bulunamadi).
# Kullanim: sudo bash /home/eren/atasos-16-modul-yukleyici.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
V=6.16.1-atas3
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi

echo "########## 1/5  atasOS'ta modprobe var mi ##########"
MP=""
for p in /usr/sbin/modprobe /sbin/modprobe /usr/bin/modprobe; do
    [ -e "$A$p" ] && { MP=$p; break; }
done
[ -n "$MP" ] || { echo "  HATA: atasOS'ta modprobe (kmod) YOK. Iptal."; umount $A; exit 1; }
echo "  modprobe: $MP -> $(readlink -f "$A$MP" | sed "s|$A||")"
[ -f "$A/usr/lib/modules/$V/modules.alias" ] || { echo "  HATA: $V modules.alias yok"; exit 1; }
echo "  modules.alias ($V): $(wc -l < "$A/usr/lib/modules/$V/modules.alias") satir"

echo
echo "########## 2/5  BU DONANIMDA HANGI SURUCULER YUKLENECEK (simulasyon) ##########"
echo "  (Kubuntu ayni makinede calisiyor; aygit kimlikleri ayni)"
find /sys/devices -name modalias -exec cat {} + 2>/dev/null | sort -u > /tmp/atasos-modalias.$$
T=$(wc -l < /tmp/atasos-modalias.$$)
while read -r al; do
    modprobe -d "$A" -S "$V" -R "$al" 2>/dev/null
done < /tmp/atasos-modalias.$$ | sort -u > /tmp/atasos-yuklenecek.$$
rm -f /tmp/atasos-modalias.$$
echo "  $T aygit kimligi -> $(wc -l < /tmp/atasos-yuklenecek.$$) modul"
tr '\n' ' ' < /tmp/atasos-yuklenecek.$$ | fold -w 76 -s | sed 's/^/    /'; echo
echo
echo "  --- kritik olanlar ---"
D=0
for m in i915 intel_lpss_pci hid_multitouch iwlwifi; do
    if grep -qx "$m" /tmp/atasos-yuklenecek.$$; then printf '    %-18s YUKLENECEK\n' "$m"
    else printf '    %-18s listede yok <<<\n' "$m"; D=1; fi
done
grep -qx iwlwifi /tmp/atasos-yuklenecek.$$ && echo "    (iwlmvm'i iwlwifi kendisi ister)"
rm -f /tmp/atasos-yuklenecek.$$

echo
echo "########## 3/5  udev KURALI ##########"
R=$A/etc/udev/rules.d/80-atasos-modalias.rules
cat > "$R" <<EOF
# atasOS: systemd -KMOD derlendi, udev'in kmod yerlesigi yok.
# Her aygit icin uygun surucuyu modprobe ile yukle (acilista coldplug + sonradan takilanlar).
# -b: /etc/modprobe.d kara listesine uy.
ACTION=="add", ENV{MODALIAS}=="?*", RUN+="$MP -b -q \$env{MODALIAS}"
EOF
chmod 644 "$R"; chown 0:0 "$R"
echo "  yazildi: ${R#$A}"
sed 's/^/    /' "$R"

echo
echo "########## 4/5  PATH (poweroff, reboot vb.) ##########"
BP=$A/home/eren/.bash_profile
if grep -q '/usr/sbin' "$BP" 2>/dev/null; then
    echo "  zaten var"
else
    sed -i '/^export LANG=/a export PATH="$PATH:/usr/sbin:/sbin"' "$BP"
    echo "  eklendi: ~/.bash_profile"
fi
sed 's/^/    /' "$BP"
for c in poweroff reboot; do
    printf '  %-10s %s\n' "$c" "$(ls -l $A/usr/sbin/$c $A/sbin/$c 2>/dev/null | head -1 | awk '{print $NF, $(NF-2)}' || echo YOK)"
done

echo
echo "########## 5/5  SONUC ##########"
sync
umount $A 2>/dev/null
if [ "$D" -eq 0 ]; then
    echo "  TAMAM. atas3 acilinca:"
    echo "    lsmod | grep -E 'i915|lpss|multitouch|iwl'"
    echo "  komutu dort surucuyu da gostermeli; touchpad ve WiFi aygitlari olusmali."
else
    echo "  Kritik suruculerden biri eslesmedi <<< kural yine de yazildi, ama yukariya bak."
fi
