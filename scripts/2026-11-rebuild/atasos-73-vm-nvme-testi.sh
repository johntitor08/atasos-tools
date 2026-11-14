#!/usr/bin/env bash
# atasOS Calamares kurulumunu, GERCEK DISKIN BIR KOPYASI GIBI DUZENLENMIS SANAL NVMe diskte denemek icin.
# GERCEK DISKLERE DOKUNMAZ: sanal makine yalnizca /veri/atasos-iso/vm-nvme/nvme.img (sanal NVMe) ve ISO'yu gorur.
# root GEREKMEZ.
#
# Sanal NVMe diskin duzeni gercek diskin aynisi (boyutlar kucuk, sira/etiketler ayni):
#   nvme0n1p1  300 MB  vfat  EFI            (bos; Calamares'in buraya ne yazdigini gormek icin)
#   nvme0n1p3   16 GB  ext4  veri           (isaret dosyalari)
#   nvme0n1p4   30 GB  ext4  atasos-kurulu  (BOS: kurulumun HEDEFI)
#   nvme0n1p2   20 GB  ext4  kubuntu_2510   (isaret dosyalari)
#   nvme0n1p5   10 GB  ext4  atasOS         (isaret dosyalari)
# Test: Calamares'te YALNIZCA p4'e kur; sonra 'denetle' p1/p2/p3/p5'in bozulup bozulmadigini soyler.
#
# Kullanim:
#   bash ~/atasos-73-vm-nvme-testi.sh            -> ISO'dan canli acilis (kurulum masaustundeki simgeden)
#   bash ~/atasos-73-vm-nvme-testi.sh denetle    -> kurulumdan sonra: diger bolumler saglam mi, p4'e ne kuruldu
#   bash ~/atasos-73-vm-nvme-testi.sh kurulu     -> ISO'suz, sanal NVMe'ye KURULAN sistemi ac
#   bash ~/atasos-73-vm-nvme-testi.sh sifirla    -> sanal NVMe'yi bastaki gercekci duzene dondur
#   bash ~/atasos-73-vm-nvme-testi.sh sil        -> test klasorunu tamamen sil
# Ayarlar (istege bagli): RAM=4096 (MB)  CPU=4  ISO=/veri/atasos-iso/atasos-live-vNN.iso
#
# Fare pencereye takilirsa: Ctrl+Alt+G birakir. Tam ekran: Ctrl+Alt+F.
set -uo pipefail
export LC_ALL=C   # tr_TR'de grep -i 'I'yi 'ı' sayar (EFI != efi)
V=${V:-/veri/atasos-iso/vm-nvme}
IMG=$V/nvme.img
ISO=${ISO:-$(ls -1 /veri/atasos-iso/atasos-live-v*.iso 2>/dev/null | sort -V | tail -1)}
RAM=${RAM:-4096}; CPU=${CPU:-4}
KOD=/usr/share/OVMF/OVMF_CODE_4M.fd; DEG=/usr/share/OVMF/OVMF_VARS_4M.fd
K=${1:-canli}
LIN=0FC63DAF-8483-4772-8E79-3D69D8477DE4; EFI=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
# no:baslangic:boyut(sektor):tip:etiket
DUZEN="1:4096:614400:$EFI:EFI
3:618496:33554432:$LIN:veri
4:34172928:62914560:$LIN:atasos-kurulu
2:97087488:41943040:$LIN:kubuntu_2510
5:139030528:20971520:$LIN:atasOS"
SON=160004096   # disk boyutu (sektor): son bolum + 1 MiB (yedek GPT)

onay(){ local c; c=$(printf '%s' "$1" | tr -d '[:space:]' | sed 's/E/e/g; s/V/v/g; s/T/t/g'); [ "$c" = evet ]; }
calisiyor(){ pgrep -f "file=$V/nvme.im[g]" >/dev/null; }

# mtools (FAT'e root'suz dosya yazmak/okumak icin): sistemde yoksa ISO'daki atasOS'un mtools'u $V/.mtools'a cikarilir
export MTOOLS_SKIP_CHECK=1
MT=""
mtools_al(){ [ -n "$MT" ] && return 0
  if command -v mcopy >/dev/null && command -v mmd >/dev/null; then MT=$(dirname "$(command -v mcopy)"); return 0; fi
  [ -x $V/.mtools/mcopy ] && { MT=$V/.mtools; return 0; }
  [ -f "$ISO" ] || return 1
  local lba T; lba=$(xorriso -indev "$ISO" -find /live/filesystem.squashfs -exec report_lba 2>/dev/null | awk -F, '/File data lba/{gsub(/ /,"",$2); print $2; exit}')
  [ -n "$lba" ] || return 1
  T=$(mktemp -d $V/.mt.XXXX) || return 1
  unsquashfs -o $((lba*2048)) -q -d $T/r "$ISO" usr/bin/mtools >/dev/null 2>&1
  [ -x $T/r/usr/bin/mtools ] || { rm -rf $T; return 1; }
  mkdir -p $V/.mtools && mv $T/r/usr/bin/mtools $V/.mtools/ && rm -rf $T
  for c in mcopy mmd mdir; do ln -sf mtools $V/.mtools/$c; done; MT=$V/.mtools; }

# isaret dosyalari: her ext4 bolumune birkac dosya; sha256'lari $V/isaretler.txt'e
isaret_yaz(){ # $1 bolum no, $2 kaynak klasor
  local d=$2; mkdir -p $d
  case $1 in
    3) mkdir -p $d/Documents $d/atasos-iso
       echo "veri bolumu isaret dosyasi $(date +%s%N)" > $d/Documents/ders-notu.txt
       head -c 8M /dev/urandom > $d/atasos-iso/ornek-buyuk-dosya.bin ;;
    2) mkdir -p $d/etc $d/home/eren
       printf 'NAME="Kubuntu (sanal test kopyasi)"\nID=ubuntu\nVERSION_ID="25.10"\n' > $d/etc/os-release
       echo "kubuntu bolumu isaret dosyasi $(date +%s%N)" > $d/home/eren/onemli.txt ;;
    5) mkdir -p $d/etc $d/sources
       printf 'NAME="atasOS"\nID=atasos\n' > $d/etc/os-release
       head -c 4M /dev/urandom > $d/sources/kaynak-ornek.bin ;;
  esac
  (cd $d && find . -type f | sort | while read -r f; do echo "$1 ${f#.} $(sha256sum "$f" | cut -d' ' -f1)"; done) >> $V/isaretler.txt; }

hazirla(){
  mkdir -p $V; [ -f $V/uefi.fd ] || cp $DEG $V/uefi.fd
  [ -f $IMG ] && return 0
  echo "  Sanal NVMe disk hazirlaniyor (gercek diskin duzeni; ~76 GB gorunur, gercekte birkac MB kaplar)..."
  local T; T=$(mktemp -d $V/.hazir.XXXX) || exit 1
  rm -f $V/isaretler.txt
  truncate -s $((SON*512)) $IMG
  local no s n t e
  # tum tablo tek seferde; bolum numarasi aygit adindan (img3 : ...) -> gercek diskteki 1,3,4,2,5 sirasi
  { echo 'label: gpt'
    while IFS=: read -r no s n t e; do echo "${IMG}$no : start=$s, size=$n, type=$t, name=$e"; done <<< "$DUZEN"
  } | sfdisk -q --no-reread --no-tell-kernel $IMG >/dev/null 2>&1 || { echo "HATA: bolum tablosu yazilamadi"; exit 1; }
  while IFS=: read -r no s n t e; do
    [ "$(bas $no)" = "$s" ] || { echo "HATA: bolum $no beklenen yerde degil"; exit 1; }
    if [ "$t" = "$EFI" ]; then
      mkfs.fat -F 32 -s 8 -n EFI --offset=$s $IMG $((n/2)) >/dev/null 2>&1 || { echo "HATA: EFI bicimlendirilemedi"; exit 1; }
      # gercek EFI'deki gibi: Kubuntu'nun yedek onyukleyicisi EFI/BOOT/BOOTX64.EFI + EFI/kubuntu (sahte icerik)
      if mtools_al; then
        local M="$IMG@@$((s*512))" f
        mkdir -p $T/efi; head -c 64K /dev/urandom > $T/efi/BOOTX64.EFI; head -c 64K /dev/urandom > $T/efi/grubx64.efi
        $MT/mmd -i "$M" ::/EFI ::/EFI/BOOT ::/EFI/kubuntu >/dev/null 2>&1 \
          && $MT/mcopy -i "$M" $T/efi/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI >/dev/null 2>&1 \
          && $MT/mcopy -i "$M" $T/efi/grubx64.efi ::/EFI/kubuntu/grubx64.efi >/dev/null 2>&1 || { echo "HATA: EFI'ye isaret yazilamadi"; exit 1; }
        echo "1 /EFI/BOOT/BOOTX64.EFI $(sha256sum < $T/efi/BOOTX64.EFI | cut -d' ' -f1)" >> $V/isaretler.txt
        echo "1 /EFI/kubuntu/grubx64.efi $(sha256sum < $T/efi/grubx64.efi | cut -d' ' -f1)" >> $V/isaretler.txt
      else echo "  NOT: mtools bulunamadi; EFI'ye sahte Kubuntu dosyalari konmadi (EFI bos)"; fi
    else
      local opt=(); [ "$no" != 4 ] && { isaret_yaz $no $T/p$no; opt=(-d $T/p$no); }
      truncate -s $((n*512)) $T/fs.img
      mke2fs -q -F -t ext4 -L "$e" "${opt[@]}" $T/fs.img >/dev/null || { echo "HATA: bolum $no bicimlendirilemedi"; exit 1; }
      dd if=$T/fs.img of=$IMG bs=1M seek=$((s/2048)) conv=notrunc,sparse status=none || { echo "HATA: bolum $no yazilamadi"; exit 1; }
      rm -f $T/fs.img
    fi
  done <<< "$DUZEN"
  rm -rf $T
  sfdisk -d $IMG > $V/tablo-once.sfdisk
  echo "  Hazir:"; sfdisk -l $IMG 2>/dev/null | sed -n '/^Device/,$p' | sed "s#$IMG#  nvme0n1p#"; }

# bolumun baslangic sektoru (guncel tablodan)
bas(){ sfdisk -d $IMG 2>/dev/null | awk -v p="${IMG}$1 " 'index($0,p)==1{match($0,/start= *[0-9]+/); s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); print s}'; }
boy(){ sfdisk -d $IMG 2>/dev/null | awk -v p="${IMG}$1 " 'index($0,p)==1{match($0,/size= *[0-9]+/); s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); print s}'; }
# fscat <bolum> <yol>: dosyayi oku; sembolik baglari izler (atasOS'ta /etc/os-release -> ../usr/lib/os-release)
fscat(){ local f=$2 h=0 d b; b=$(bas $1); [ -n "$b" ] || return 1
  if [ "$1" = 1 ]; then mtools_al || return 1; $MT/mcopy -n -i "$IMG@@$((b*512))" "::$f" - 2>/dev/null; return; fi
  local A="$IMG?offset=$((b*512))"
  while [ $h -lt 8 ]; do
    d=$(debugfs -c -R "stat \"$f\"" "$A" 2>/dev/null | sed -n 's/^Fast link dest: "\(.*\)"$/\1/p')
    [ -z "$d" ] && break
    case "$d" in /*) f=$d;; *) f=$(dirname "$f")/$d;; esac; h=$((h+1)); done
  debugfs -c -R "cat \"$f\"" "$A" 2>/dev/null; }
etiket(){ local b; b=$(bas $1); [ -n "$b" ] || { echo "BOLUM YOK"; return; }
  [ "$1" = 1 ] && { echo EFI; return; }
  debugfs -c -R stats "$IMG?offset=$((b*512))" 2>/dev/null | awk -F': *' '/^Filesystem volume name/{print $2}'; }

bolumler(){ sfdisk -d $IMG 2>/dev/null | grep -E "^${IMG}[0-9]+ " | awk -v I="$IMG" '{sub(I,""); print $1}'; }
hedefler(){ local p; for p in $(bolumler); do [ "$p" = 1 ] && continue; fscat $p /etc/fstab 2>/dev/null | grep -q '[^[:space:]]' && printf '%s ' $p; done; }

denetle(){
  [ -f $IMG ] && [ -f $V/tablo-once.sfdisk ] || { echo "  Sanal disk yok; once: bash $0"; exit 1; }
  calisiyor && { echo "  Sanal makine calisiyor; once pencereyi kapat."; exit 1; }
  local hata=0 no s n t e
  echo "########## BOLUM TABLOSU (once -> simdi) ##########"
  while IFS=: read -r no s n t e; do
    local s2 n2; s2=$(bas $no); n2=$(boy $no)
    if [ "$s2" = "$s" ] && [ "$n2" = "$n" ]; then echo "  p$no ($e): AYNI  baslangic $s, $((n/2048)) MiB"
    elif [ "$no" = 4 ]; then echo "  p$no ($e): DEGISTI  baslangic $s -> ${s2:-YOK}, $((n/2048)) -> $(( ${n2:-0}/2048 )) MiB  (hedef bolum)"
    elif [ "$s2" = "$s" ] && [ -n "$n2" ] && [ "$n2" -lt "$n" ]; then echo "  p$no ($e): KUCULTULDU  $((n/2048)) -> $((n2/2048)) MiB (baslangic ayni; icerik asagida denetleniyor)"
    else echo "  p$no ($e): DEGISTI!  baslangic $s -> ${s2:-YOK}, boyut $((n/2048)) -> $(( ${n2:-0}/2048 )) MiB"; hata=1; fi
  done <<< "$DUZEN"
  local p
  for p in $(bolumler); do
    grep -q "^$p:" <<< "$DUZEN" || echo "  YENI BOLUM: p$p  baslangic $(bas $p), $(( $(boy $p)/2048 )) MiB"
    [ $(( $(bas $p) % 2048 )) = 0 ] || echo "  HIZASIZ: p$p baslangic $(bas $p) (1 MiB'a hizali degil$( [ $(( $(bas $p) % 8 )) = 0 ] || echo '; 4 KiB'"'"'a bile degil'); NVMe'de yavaslik)"
  done
  echo; echo "########## KORUNMASI GEREKEN BOLUMLER + EFI (isaret dosyalari) ##########"
  local f h h2 son=""
  while read -r p f h; do
    [ "$p" != "$son" ] && { echo "  p$p ($(etiket $p)):"; son=$p; }
    h2=$(fscat $p "$f" | sha256sum | cut -d' ' -f1)
    if [ "$h2" = "$h" ]; then echo "    tamam  $f"; else echo "    BOZULDU/KAYIP  $f"; hata=1; fi
  done < $V/isaretler.txt
  echo; echo "########## EFI BOLUMU (p1) ##########"
  local E L; E=$(mktemp $V/.efi.XXXX)
  dd if=$IMG of=$E bs=512 skip=$(bas 1) count=$(boy 1) status=none
  if 7z l -ba $E >/dev/null 2>&1; then
    L=$(7z l -ba $E 2>/dev/null | awk '$3!~/^D/{print $NF}' | sort)
    [ -n "$L" ] && { echo "  EFI'deki dosyalar:"; echo "$L" | sed 's/^/    /'; } || echo "  EFI bos"
    if ! grep -q '^1 /EFI/BOOT/' $V/isaretler.txt && grep -qi '^EFI/BOOT/BOOTX64.EFI$' <<< "$L"; then
      echo "  NOT: EFI/BOOT/BOOTX64.EFI (yedek onyukleyici) yazilmis; gercek diskte Kubuntu'nunkinin USTUNE yazardi."; fi
  else echo "  EFI okunamadi (bicimlendirilmis ya da bozulmus olabilir)"; hata=1; fi
  rm -f $E
  local hedef; hedef=$(hedefler)
  [ -n "$hedef" ] || { echo; echo "########## HEDEF ##########"; echo "  Kurulu atasOS hicbir bolumde bulunamadi"; hata=1; }
  for p in $hedef; do
    echo; echo "########## HEDEF: p$p ##########"
    local os og; os=$(fscat $p /etc/os-release | awk -F= '/^PRETTY_NAME=|^NAME=/{gsub(/"/,"",$2); print $2; exit}')
    echo "  kurulu sistem: ${os:-?}  (etiket: $(etiket $p))"
    echo "  fstab kok satiri: $(fscat $p /etc/fstab | awk '$2=="/"' | head -1)"
    local rt; rt=$(fscat $p /boot/grub/grub.cfg | grep -m1 -oE 'root=[^ ]+')
    echo "  GRUB kok parametresi: ${rt:-?}$(case "$rt" in root=PARTUUID=*) echo '  (kalici)';; root=/dev/*) echo '  (aygit adi: disk sirasi degisirse acilmaz)';; esac)"
    echo "  kullanicilar: $(fscat $p /etc/passwd | awk -F: '$3>=1000 && $3<60000{printf "%s ",$1}')"
    og=$(fscat $p /etc/sddm.conf | awk -F= '/^User=/{print $2; exit}')
    echo "  otomatik giris: ${og:-kapali}"
  done
  echo
  [ $hata = 0 ] && echo "  SONUC: GECTI. Kurulum yalnizca hedefe yapildi; korunmasi gereken bolumler ve EFI dosyalari saglam. Simdi: bash $0 kurulu" \
                || echo "  SONUC: SORUN VAR (yukarida BOZULDU/DEGISTI!/YOK yazan satirlar). Bu ciktiyi Claude'a yapistir."; }

case "$K" in
  sil)
    [ -d $V ] || { echo "  Test klasoru zaten yok."; exit 0; }
    calisiyor && { echo "  Sanal makine calisiyor; once pencereyi kapat."; exit 1; }
    du -sh $V; read -r -p "  $V tamamen silinsin mi? 'evet' yaz: " C
    onay "$C" && rm -rf $V && echo "  Silindi." || echo "  Iptal (yazilan: '$C')."; exit 0 ;;
  sifirla)
    calisiyor && { echo "  Sanal makine calisiyor; once pencereyi kapat."; exit 1; }
    read -r -p "  Sanal NVMe bastaki duzene donsun mu (icindeki kurulum silinir)? 'evet' yaz: " C
    onay "$C" || { echo "  Iptal (yazilan: '$C')."; exit 0; }
    rm -f $IMG $V/uefi.fd $V/tablo-once.sfdisk $V/isaretler.txt; hazirla; echo "  Simdi: bash $0"; exit 0 ;;
  denetle) denetle; exit 0 ;;
  canli|kurulu) ;;
  *) echo "  Bilinmeyen secenek: $K  (canli | denetle | kurulu | sifirla | sil)"; exit 1 ;;
esac

[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "HATA: /dev/kvm erisimi yok (KVM)."; exit 1; }
calisiyor && { echo "  Bu sanal makine zaten acik."; exit 1; }
hazirla
EK=()
if [ "$K" = canli ]; then
  [ -f "$ISO" ] || { echo "HATA: ISO yok: $ISO"; exit 1; }
  EK=(-drive "file=$ISO,if=none,id=cd0,media=cdrom,readonly=on" -device ide-cd,drive=cd0,bootindex=0)
  cat <<EOF
  ISO: $ISO
  Acilis: GRUB'da ilk girdi (atasOS Canli). Masaustunde 'atasOS Kur' simgesine cift tikla.
  BOLUMLEME ADIMINDA (gercek diskte yapacagin gibi; ust tarafta 'QEMU NVMe Ctrl (/dev/nvme0n1)' secili olmali):
    'Elle bolumlendirme' sec.
    - nvme0n1p4 (atasos-kurulu, 30 GB)  -> Duzenle: Bicimlendir, ext4, baglama noktasi /
    - nvme0n1p1 (EFI, 300 MB)           -> Duzenle: Koru (BICIMLENDIRME), baglama noktasi /boot/efi
    - diger bolumlere (veri, kubuntu_2510, atasOS) DOKUNMA
  Kurulum bitince pencereyi kapat, sonra:  bash $0 denetle
EOF
else
  [ -n "$(hedefler)" ] || { echo "  Sanal diskte kurulu sistem yok: once ISO'dan acip kurulumu yap:  bash $0"; exit 1; }
  echo "  Sanal NVMe'deki kurulu atasOS aciliyor (ISO takili degil)."
fi
AV=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
[ "$AV" -lt "$RAM" ] && echo "  NOT: bos bellek ${AV} MB, sanal makineye ${RAM} MB veriliyor; yavaslarsa birkac uygulamayi kapat."

# 69 ile ayni makine/ekran/ses/ag; tek fark disk: virtio yerine NVMe denetleyici (gercek bilgisayardaki gibi nvme0n1)
exec qemu-system-x86_64 -name "atasOS NVMe kurulum testi ($K)" -enable-kvm -cpu host -smp $CPU -m $RAM \
  -drive if=pflash,format=raw,readonly=on,file=$KOD -drive if=pflash,format=raw,file=$V/uefi.fd \
  -drive file=$IMG,if=none,id=nv0,format=raw -device nvme,serial=ATASNVME01,drive=nv0,bootindex=1 "${EK[@]}" \
  -vga none -device VGA,edid=on,xres=1280,yres=800 -display gtk,zoom-to-fit=on \
  -usb -device usb-tablet \
  -audiodev pipewire,id=ses -device intel-hda -device hda-duplex,audiodev=ses \
  -nic user,model=virtio-net-pci \
  -monitor unix:$V/mon.sock,server,nowait
