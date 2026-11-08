#!/usr/bin/env bash
# Kubuntu GRUB'unda tek atasOS girdisi: "atasOS" artik atas6 cekirdegini acar, ayri "atasOS (atas6 - deneme)" girdisi kalkar.
# Canli ISO girdisi (46_atasos_iso_canli, her ISO uretiminde en yeni ISO'ya gore yeniden yazilir) oldugu gibi kalir.
# Eski /etc/grub.d dosyalari /home/eren/atas3-loglar/grub-yedek-68/ altina kopyalanir.
# Kullanim: sudo bash /home/eren/atasos-68-grub-tek-girdi.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
G=/etc/grub.d; Y=/home/eren/atas3-loglar/grub-yedek-68
[ -f $G/44_atasos_atas5 ] && [ -f $G/45_atasos_atas6 ] || { echo "HATA: 44_atasos_atas5 / 45_atasos_atas6 yok (zaten yapilmis olabilir)"; exit 1; }
grep -q 'vmlinuz-6.16.1-atas6 ' $G/45_atasos_atas6 || { echo "HATA: 45_atasos_atas6 beklenen atas6 girdisi degil"; exit 1; }
mkdir -p $Y && cp -a $G/44_atasos_atas5 $G/45_atasos_atas6 $Y/ && chown -R eren:eren $Y
# atas6 girdisini "atasOS" adiyla 44_atasos olarak yaz (siralama ayni kalir: Kubuntu girdilerinden sonra, ISO'dan once)
sed 's|^menuentry "atasOS (atas6 - yeni cekirdek, deneme)"|menuentry "atasOS"|' $G/45_atasos_atas6 > $G/44_atasos
chmod 755 $G/44_atasos
grep -q '^menuentry "atasOS" ' $G/44_atasos && grep -q 'vmlinuz-6.16.1-atas6 ' $G/44_atasos || { echo "HATA: yeni girdi yazilamadi; hicbir sey silinmedi"; rm -f $G/44_atasos; exit 1; }
rm -f $G/44_atasos_atas5 $G/45_atasos_atas6
update-grub 2>&1 | grep -iE 'error|hata|done|bitti' | sed 's/^/  /'
echo "  --- GRUB menusundeki atasOS girdileri ---"
grep -n 'menuentry "atasOS' /boot/grub/grub.cfg | sed 's/^/  /'
echo "  Eski dosyalar: $Y"
