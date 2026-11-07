#!/usr/bin/env bash
# atasOS canli ISO'yu (varsayilan: en yeni /veri/atasos-iso/atasos-live-vNN.iso) USB bellege yazar.
# USB'DEKI HER SEY SILINIR. Korumalar: sadece TRAN=usb diskler, NVMe reddedilir, cihaz adini elle yazman
# istenir + 'evet' onayi; yazmadan once ISO'nun sha256'si, yazdiktan sonra USB'den geri okuma dogrulanir.
# Kullanim: USB'yi tak, sonra: sudo bash /home/eren/atasos-61-usb-yaz.sh [iso-yolu]
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
ISO=${1:-$(ls /veri/atasos-iso/atasos-live-v[0-9]*.iso 2>/dev/null | sort -V | tail -1)}
[ -f "$ISO" ] && [ -f "$ISO.sha256" ] || { echo "HATA: ISO ya da $ISO.sha256 yok"; exit 1; }
SHA=$(awk '{print $1}' "$ISO.sha256")
BOY=$(stat -c %s "$ISO")
echo "  ISO: $ISO ($((BOY/1024/1024)) MB)"

echo "########## 1/4  ISO DOGRULAMA ##########"
G=$(sha256sum "$ISO" | awk '{print $1}')
[ "$G" = "$SHA" ] && echo "  sha256 .sha256 dosyasiyla ayni" || { echo "  HATA: ISO bozuk/degismis, iptal."; exit 1; }

echo
echo "########## 2/4  USB BELLEK SECIMI ##########"
mapfile -t U < <(lsblk -dn -o NAME,TRAN | awk '$2=="usb"{print $1}')
[ ${#U[@]} -gt 0 ] || { echo "  Takili USB bellek YOK. Tak ve tekrar calistir."; exit 1; }
for d in "${U[@]}"; do
    printf '  /dev/%-6s %8s  %s %s\n' "$d" "$(lsblk -dn -o SIZE /dev/$d)" \
        "$(lsblk -dn -o VENDOR /dev/$d | xargs)" "$(lsblk -dn -o MODEL /dev/$d | xargs)"
    lsblk -n -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS /dev/$d | tail -n +2 | sed 's/^/        /'
done
echo
read -r -p "  Yazilacak cihazin adini yaz (ornek: sda) — ICINDEKI HER SEY SILINECEK: " D
D=${D#/dev/}
printf '%s\n' "${U[@]}" | grep -qx "$D" || { echo "  '$D' listedeki USB cihazlardan biri degil. Iptal."; exit 1; }
case "$D" in nvme*|zram*|loop*) echo "  Bu bir USB bellek degil. Iptal."; exit 1 ;; esac
[ "$(lsblk -bdn -o SIZE /dev/$D)" -ge "$BOY" ] || { echo "  USB cok kucuk (ISO $((BOY/1024/1024)) MB). Iptal."; exit 1; }
read -r -p "  Son onay: /dev/$D ($(lsblk -dn -o SIZE /dev/$D)) tamamen silinecek. 'evet' yaz: " C
[ "$C" = "evet" ] || { echo "  Iptal edildi, hicbir sey yazilmadi."; exit 0; }

echo
echo "########## 3/4  YAZMA ##########"
for p in $(lsblk -ln -o NAME /dev/$D | tail -n +2); do umount /dev/$p 2>/dev/null; done
dd if="$ISO" of=/dev/$D bs=4M conv=fsync oflag=direct status=progress || { echo "  HATA: yazma basarisiz"; exit 1; }
sync

echo
echo "########## 4/4  GERI OKUMA DOGRULAMASI ##########"
echo 3 > /proc/sys/vm/drop_caches
R=$(head -c "$BOY" /dev/$D | sha256sum | awk '{print $1}')
if [ "$R" = "$SHA" ]; then
    echo "  USB'deki veri ISO ile BAYT BAYT AYNI."
    echo
    echo "  Simdi: bilgisayari kapat, USB takiliyken ac, Huawei logosunda F12'ye bas,"
    echo "  listeden USB bellegi sec."
else
    echo "  HATA: geri okunan veri farkli <<< USB bellek arizali olabilir."
fi
