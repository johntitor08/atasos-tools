#!/bin/bash
# atasos-75: Kubuntu GRUB menusunde atasOS icin yalniz "atasOS v34 (kurulu)" (p4) kalsin.
#   44_atasos           (p5 gelistirme sistemi)     -> /etc/grub.d-atasos-yedek/ altina tasinir
#   46_atasos_iso_canli (v35 ISO dosyasindan canli) -> /etc/grub.d-atasos-yedek/ altina tasinir
# Hicbir bolume, EFI'ye ya da p5'e dokunmaz; yalniz /etc/grub.d dosyalari + update-grub.
# Geri almak: sudo mv /etc/grub.d-atasos-yedek/* /etc/grub.d/ && sudo update-grub
# Calistir (Konsole'da): sudo bash ~/atasos-75-grub-tek-girdi.sh
set -u
export LC_ALL=C
[ "$(id -u)" = 0 ] || { echo "HATA: root gerekli: sudo bash $0"; exit 1; }

G=/etc/grub.d; Y=/etc/grub.d-atasos-yedek
[ -x $G/45_atasos_kurulu ] || { echo "HATA: $G/45_atasos_kurulu yok; kalacak girdi bulunamadi, hicbir sey yapilmadi."; exit 1; }
grep -q 'atasOS v34 (kurulu)' $G/45_atasos_kurulu || { echo "HATA: 45_atasos_kurulu beklenen girdi degil; hicbir sey yapilmadi."; exit 1; }

mkdir -p $Y
for f in 44_atasos 46_atasos_iso_canli; do
    if [ -e $G/$f ]; then mv -v $G/$f $Y/$f || { echo "HATA: $f tasinamadi"; exit 1; }
    else echo "  $f zaten yok"; fi
done

echo "== update-grub"
update-grub 2>&1 | grep -iE 'error|done' | sed 's/^/  /'

echo "== /boot/grub/grub.cfg icindeki atasOS girdileri:"
grep -n 'menuentry .*atasOS' /boot/grub/grub.cfg | sed 's/^/  /'
n=$(grep -c 'menuentry .*atasOS' /boot/grub/grub.cfg)
if [ "$n" = 1 ] && grep -q 'menuentry "atasOS v34 (kurulu)"' /boot/grub/grub.cfg; then
    echo "TAMAM: menude yalniz 'atasOS v34 (kurulu)' var. Yedek: $Y"
else
    echo "UYARI: beklenmeyen sayida atasOS girdisi ($n). Bu ciktiyi Claude'a yapistir."; exit 1
fi
