#!/usr/bin/env bash
# atasOS kurulumunu sanal makinede (QEMU/KVM, UEFI) KENDIN denemen icin. Pencere acilir, fare/klavye senin.
# GERCEK DISKLERE DOKUNMAZ: sanal makine yalnizca /veri/atasos-iso/vm-kurulum/disk.qcow2 (20 GB'lik sanal disk)
# ve ISO'yu gorur. Calamares'te gorecegin tek disk o sanal disktir ("Diski sil" burada guvenli).
# root GEREKMEZ.
#
# Kullanim:
#   bash ~/atasos-69-vm-kurulum-testi.sh           -> ISO'dan canli acilis (kurulum masaustundeki simgeden)
#   bash ~/atasos-69-vm-kurulum-testi.sh kurulu    -> ISO'suz, sanal diske KURULAN sistemi ac
#   bash ~/atasos-69-vm-kurulum-testi.sh sifirla   -> sanal diski bosalt (bastan kurmak icin)
#   bash ~/atasos-69-vm-kurulum-testi.sh sil       -> test klasorunu tamamen sil (test bitince)
# Ayarlar (istege bagli): RAM=4096 (MB)  CPU=4  ISO=/veri/atasos-iso/atasos-live-vNN.iso
#
# Fare pencereye takilirsa: Ctrl+Alt+G birakir. Tam ekran: Ctrl+Alt+F. Kapatmak: pencereyi kapat
# (sanal makine aninda kapanir; kurulum sirasinda kapatma).
set -uo pipefail
V=/veri/atasos-iso/vm-kurulum
ISO=${ISO:-$(ls -1 /veri/atasos-iso/atasos-live-v*.iso 2>/dev/null | sort -V | tail -1)}
RAM=${RAM:-4096}; CPU=${CPU:-4}
KOD=/usr/share/OVMF/OVMF_CODE_4M.fd; DEG=/usr/share/OVMF/OVMF_VARS_4M.fd
K=${1:-canli}

hazirla(){ mkdir -p $V
  [ -f $V/disk.qcow2 ] || { qemu-img create -q -f qcow2 $V/disk.qcow2 20G && echo "  Sanal disk olusturuldu: $V/disk.qcow2 (20 GB, gercekte bos yer kaplamaz)"; }
  [ -f $V/uefi.fd ] || cp $DEG $V/uefi.fd; }

# onay: bas/son bosluklar ve buyuk/kucuk harf onemsiz (evet, Evet, EVET, İ'li Türkçe klavye yazimlari dahil)
onay(){ local c; c=$(printf '%s' "$1" | tr -d '[:space:]' | sed 's/E/e/g; s/V/v/g; s/T/t/g'); [ "$c" = evet ]; }

case "$K" in
  sil)
    [ -d $V ] || { echo "  Test klasoru zaten yok."; exit 0; }
    pgrep -f "file=$V/disk.qcow[2]" >/dev/null && { echo "  Sanal makine calisiyor; once pencereyi kapat."; exit 1; }
    du -sh $V; read -r -p "  $V tamamen silinsin mi? 'evet' yaz: " C
    onay "$C" && rm -rf $V && echo "  Silindi." || echo "  Iptal (yazilan: '$C')."; exit 0 ;;
  sifirla)
    pgrep -f "file=$V/disk.qcow[2]" >/dev/null && { echo "  Sanal makine calisiyor; once pencereyi kapat."; exit 1; }
    read -r -p "  Sanal diskteki kurulum silinip bos disk yapilsin mi? 'evet' yaz: " C
    onay "$C" || { echo "  Iptal (yazilan: '$C')."; exit 0; }
    rm -f $V/disk.qcow2 $V/uefi.fd; hazirla; echo "  Hazir. Simdi: bash $0"; exit 0 ;;
  canli|kurulu) ;;
  *) echo "  Bilinmeyen secenek: $K  (canli | kurulu | sifirla | sil)"; exit 1 ;;
esac

[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "HATA: /dev/kvm erisimi yok (KVM)."; exit 1; }
pgrep -f "file=$V/disk.qcow[2]" >/dev/null && { echo "  Bu sanal makine zaten acik."; exit 1; }
if [ "$K" = kurulu ]; then
  # bos sanal disk birkac yuz KB kaplar; kurulu atasOS birkac GB
  B=$(qemu-img info --force-share --output=json $V/disk.qcow2 2>/dev/null | awk -F'[:,]' '/"actual-size"/{gsub(/ /,"",$2); print $2; exit}')
  [ "${B:-0}" -gt 104857600 ] || { echo "  Sanal disk bos: once ISO'dan acip kurulumu yap:  bash $0"; exit 1; }
fi
hazirla
EK=()
if [ "$K" = canli ]; then
  [ -f "$ISO" ] || { echo "HATA: ISO yok: $ISO"; exit 1; }
  EK=(-cdrom "$ISO" -boot d)
  echo "  ISO: $ISO"
  echo "  Acilis: GRUB'da ilk girdi (atasOS Canli). Masaustunde 'atasOS Kur' simgesine cift tikla."
  echo "  Kurulum bitince pencereyi kapat, sonra: bash $0 kurulu"
else
  echo "  Sanal diskteki kurulu atasOS aciliyor (ISO takili degil)."
fi
AV=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
[ "$AV" -lt "$RAM" ] && echo "  NOT: bos bellek ${AV} MB, sanal makineye ${RAM} MB veriliyor; yavaslarsa birkac uygulamayi kapat."

# makine tipi, disk ve USB ayarlari onceki (v29-v33) otomatik testlerle ayni.
# Ekran: sabit 1280x800 (std VGA + EDID). virtio-vga GTK penceresinin boyutunu misafire iletiyordu; pencere ilk
# acilista 640x480 oldugu icin misafir 640x480'e dusuyor, her sey dev gorunuyordu. Pencereyi buyutup kucultmek
# artik misafirin cozunurlugunu degistirmez, yalnizca goruntuyu olcekler (zoom-to-fit).
exec qemu-system-x86_64 -name "atasOS kurulum testi ($K)" -enable-kvm -cpu host -smp $CPU -m $RAM \
  -drive if=pflash,format=raw,readonly=on,file=$KOD -drive if=pflash,format=raw,file=$V/uefi.fd \
  -drive file=$V/disk.qcow2,if=virtio,format=qcow2 "${EK[@]}" \
  -vga none -device VGA,edid=on,xres=1280,yres=800 -display gtk,zoom-to-fit=on \
  -usb -device usb-tablet \
  -audiodev pipewire,id=ses -device intel-hda -device hda-duplex,audiodev=ses \
  -nic user,model=virtio-net-pci \
  -monitor unix:$V/mon.sock,server,nowait
# mon.sock: yalnizca sanal makinenin ekran goruntusu icin (screendump); host ekranina erismez
