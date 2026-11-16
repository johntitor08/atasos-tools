#!/usr/bin/env bash
# atasOS v35'i p4'e (etiket "atasos-kurulu") YENIDEN kurar: p4'teki v34'un yerine.
# atasos-72'nin aynisi; farklar:
#   - ISO sabit: /veri/atasos-iso/atasos-live-v35.iso
#   - p4 bos degil (v34 var) -> once ICINI GOSTERIR, istersen /home'u /veri'ye yedekler, sonra p4'u AYNI UUID ile
#     bicimlendirir (mkfs.ext4 -U). Bolum tablosuna dokunulmaz; PARTUUID degismez.
#   - GRUB girdisi: "atasOS v35 (kurulu)" (45_atasos_kurulu dosyasinin yerine)
# KORUMALAR: hedef YALNIZCA /dev/nvme0n1p4; etiket atasos-kurulu, PARTUUID b0607002-..., baslangic sektoru 677552128,
#   boyut 30 GiB hepsi tutmazsa HICBIR SEY yapmaz. Bicimlendirmeden once 'evet' yazman gerekir.
#   p1/p2/p3/p5'e yazilmaz; EFI bolumune ve UEFI kayitlarina dokunulmaz (/boot/efi chroot'a baglanmaz).
# Kullanim (Konsole'da): sudo bash /home/eren/atasos-76-v35-p4e-yeniden-kur.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. Hicbir sey yapilmadi."; exit 1; }
LOG=/home/eren/atas3-loglar/atasos-76-v35-p4e-yeniden-kur.log
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS 76: v35'i p4'e yeniden kur  ($(date '+%F %T')) ##########"

D=/dev/nvme0n1; P4=${D}p4
ISO=/veri/atasos-iso/atasos-live-v35.iso
T=/mnt/atasos-kurulu; M=/mnt/atasos-iso-oku
KVER=6.16.1-atas6
BEK_PUUID=b0607002-8d08-4410-8356-277cb661c3b1
BEK_BAS=677552128; BEK_BOY=62914560
YEDEK=/veri/atasos-kurulu-v34-home-yedek
dur(){ echo; echo "  DURDU: $*"; echo "  Kayit: $LOG"; exit 1; }
temizle(){ cd /; for m in $T/run $T/sys $T/proc $T/dev/pts $T/dev $T $M; do mountpoint -q "$m" && umount "$m"; done; sync; }
trap temizle EXIT
cr(){ chroot $T /usr/bin/env -i HOME=/root TERM=linux LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }

echo
echo "########## 1/9  DENETIM (hicbir sey yazilmaz) ##########"
[ -b $P4 ] || dur "$P4 yok"
[ "$(blkid -s LABEL -o value $P4)" = atasos-kurulu ] || dur "$P4 etiketi 'atasos-kurulu' degil"
[ "$(blkid -s TYPE -o value $P4)" = ext4 ] || dur "$P4 ext4 degil"
PU4=$(blkid -s PARTUUID -o value $P4)
[ "$PU4" = $BEK_PUUID ] || dur "$P4 PARTUUID'i beklenen degil ($PU4); bolum degismis olabilir"
[ "$(cat /sys/class/block/nvme0n1p4/start)" = $BEK_BAS ] || dur "$P4 baslangic sektoru beklenen degil"
[ "$(cat /sys/class/block/nvme0n1p4/size)" = $BEK_BOY ] || dur "$P4 boyutu beklenen degil"
findmnt -rn -S $P4 >/dev/null && dur "$P4 bagli; once ayir"
[ "$(findmnt -rn -o SOURCE /)" = $P4 ] && dur "su an p4'ten acilmissin; Kubuntu'dan calistir"
U4=$(blkid -s UUID -o value $P4); [ -n "$U4" ] || dur "UUID okunamadi"
[ -f "$ISO" ] && [ -f "$ISO.sha256" ] || dur "ISO ya da .sha256 yok: $ISO"
echo "  hedef: $P4 (30 GiB, UUID $U4, PARTUUID $PU4)"
echo "  ISO  : $ISO"
echo -n "  sha256 denetleniyor... "; (cd "${ISO%/*}" && sha256sum -c --quiet "${ISO##*/}.sha256") && echo tamam || dur "ISO bozuk"
mkdir -p $T $M
mount -o ro $P4 $T || dur "$P4 baglanamadi"
echo "  p4'te simdi: $(. $T/etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo 'tanimsiz sistem')"
EVLER=$(ls -A $T/home 2>/dev/null | tr '\n' ' ')
HBOY=$(du -sh --exclude='.cache' $T/home 2>/dev/null | cut -f1)
echo "  /home: ${EVLER:-bos}  (boyut, .cache haric: ${HBOY:-0})"
echo "  p4'te kullanilan: $(df -h --output=used $T | tail -1 | tr -d ' ')"

echo
echo "########## 2/9  KULLANICI BILGILERI ##########"
YED=0
if [ -n "$EVLER" ]; then
    read -r -p "  p4'teki /home ($HBOY) bicimlendirmeden once $YEDEK altina yedeklensin mi? (e/h): " Y
    case "$Y" in e|E|evet|Evet|EVET) YED=1;; esac
fi
while :; do
    read -r -p "  Giris adi (kucuk harf, ornek: ata): " KUL
    printf '%s' "$KUL" | grep -qE '^[a-z_][a-z0-9_-]{0,31}$' && [ "$KUL" != root ] && break
    echo "    gecersiz ad: kucuk harf/rakam/-/_ , harfle baslamali"
done
read -r -p "  Tam adin (bos birakilabilir): " TAM
read -r -p "  Acilista parola sormadan otomatik giris olsun mu? (e/h): " OTO
case "$OTO" in e|E|evet|Evet|EVET) OTO=1;; *) OTO=0;; esac
echo
echo "  OZET: $P4 (p4, 'atasos-kurulu') BICIMLENDIRILECEK -> icindeki v34 ve tum dosyalari SILINIR."
echo "        /home yedegi: $([ $YED = 1 ] && echo "evet -> $YEDEK" || echo HAYIR)"
echo "        yeni: atasOS v35, kullanici $KUL, otomatik giris $([ $OTO = 1 ] && echo evet || echo hayir)"
echo "        Baska hicbir bolume (Kubuntu, /veri, p5, EFI) yazilmaz."
read -r -p "  Devam edilsin mi? 'evet' yaz: " C
C=$(printf '%s' "$C" | tr -d '[:space:]' | sed 's/E/e/g; s/V/v/g; s/T/t/g')
[ "$C" = evet ] || dur "iptal (yazilan: '$C'). Hicbir sey yazilmadi."

echo
echo "########## 3/9  /home YEDEGI ##########"
if [ $YED = 1 ]; then
    [ -e $YEDEK ] && YEDEK=$YEDEK-$(date +%Y%m%d-%H%M%S)
    mkdir -p $YEDEK || dur "$YEDEK olusturulamadi"
    rsync -aHAX --exclude='.cache/' $T/home/ $YEDEK/ || dur "yedek basarisiz; p4'e dokunulmadi"
    A=$(cd $T/home && find . -path '*/.cache' -prune -o -type f -print | wc -l)
    B=$(cd $YEDEK && find . -type f | wc -l)
    [ "$A" = "$B" ] || dur "yedek dosya sayisi tutmuyor ($A / $B); p4'e dokunulmadi"
    echo "  yedeklendi: $YEDEK ($B dosya)"
else echo "  atlandi"; fi
umount $T || dur "$P4 ayrilamadi"

echo
echo "########## 4/9  p4 BICIMLENDIRILIYOR (ayni UUID) ##########"
[ "$(blkid -s PARTUUID -o value $P4)" = $BEK_PUUID ] || dur "son denetim: PARTUUID tutmuyor"
mkfs.ext4 -q -F -L atasos-kurulu -U "$U4" $P4 || dur "mkfs.ext4 basarisiz"
[ "$(blkid -s UUID -o value $P4)" = "$U4" ] && [ "$(blkid -s LABEL -o value $P4)" = atasos-kurulu ] || dur "bicimlendirme sonrasi UUID/etiket tutmuyor"
echo "  p4 bos ext4: etiket atasos-kurulu, UUID $U4"
mount $P4 $T || dur "$P4 baglanamadi"

echo
echo "########## 5/9  SISTEM BOLUME ACILIYOR (unsquashfs, ~8 GB) ##########"
mount -o loop,ro "$ISO" $M || dur "ISO baglanamadi"
SQ=$M/live/filesystem.squashfs; [ -f $SQ ] || dur "ISO'da live/filesystem.squashfs yok"
S0=$(date +%s)
unsquashfs -f -q -d $T $SQ || dur "unsquashfs basarisiz"
umount $M
[ -f $T/boot/vmlinuz-$KVER ] || dur "acilan sistemde cekirdek yok (/boot/vmlinuz-$KVER)"
echo "  acildi: $(du -sh $T 2>/dev/null | cut -f1), $(( $(date +%s)-S0 )) sn"

echo
echo "########## 6/9  CANLIYA OZEL HER SEY KALDIRILIYOR ##########"
for m in dev dev/pts proc sys run; do mkdir -p $T/$m; done
mount --bind /dev $T/dev; mount --bind /dev/pts $T/dev/pts; mount -t proc proc $T/proc; mount -t sysfs sys $T/sys; mount -t tmpfs tmpfs $T/run
[ -x $T/usr/lib/atasos/kurulum-temizle.sh ] || dur "kurulum-temizle.sh yok"
cr /usr/lib/atasos/kurulum-temizle.sh || echo "  UYARI: kurulum-temizle.sh hata kodu $?"
for y in usr/bin/calamares usr/bin/atasos-kurulum etc/calamares etc/sudoers.d/40-live-calamares etc/polkit-1/rules.d/49-atasos-live.rules home/eren tcl-backup; do
    [ -e $T/$y ] && { echo "  KALDI: /$y <<<"; } ; done
grep -rqs '^\[Autologin\]' $T/etc/sddm.conf.d/ && echo "  KALDI: sddm.conf.d'de [Autologin] <<<" || echo "  canli kullanici, canli otomatik giris, canli kurallar ve Calamares kaldirildi"

echo
echo "########## 7/9  KULLANICI + PAROLA + SUDO ##########"
for g in users wheel audio video network; do cr getent group $g >/dev/null || cr groupadd $g; done
cr useradd -m -s /bin/bash -G users,wheel,audio,video,network ${TAM:+-c "$TAM"} "$KUL" || dur "useradd basarisiz"
echo "  kullanici '$KUL' olusturuldu (wheel: sudo kullanabilir)"
echo "  Simdi '$KUL' icin parola belirle (ekranda gorunmez; iki kez):"
n=0; until chroot $T /usr/bin/passwd "$KUL"; do n=$((n+1)); [ $n -ge 3 ] && dur "parola 3 kez belirlenemedi. Kurulum yarim; bu betigi yeniden calistir"; echo "  tekrar dene:"; done
bos_mu(){ H=$(awk -F: -v u="$KUL" '$1==u{print $2}' $T/etc/shadow)
    case "$H" in '$'*) ;; *) return 0;; esac
    perl -e 'my $c = crypt("", $ARGV[0]); exit(!defined $c || $c =~ /^\*/ ? 2 : ($c eq $ARGV[0] ? 0 : 1))' "$H"; local r=$?
    [ $r = 2 ] && { echo "  UYARI: parola ozeti denetlenemedi (${H:0:4}...); bos birakmadigindan emin ol"; return 1; }
    return $r; }
n=0; while bos_mu; do
    n=$((n+1)); [ $n -ge 3 ] && dur "parola bos ya da kaydedilmedi. Bu betigi yeniden calistir"
    echo "  Parola BOS olamaz (atasOS bos parolayla giris kabul etmez). Tekrar:"; chroot $T /usr/bin/passwd "$KUL"; done
echo "  parola kaydedildi"
cr passwd -l root >/dev/null 2>&1; echo "  root hesabi kilitli (yonetici islemleri: sudo)"
echo '%wheel ALL=(ALL:ALL) ALL' > $T/etc/sudoers.d/10-installer; chmod 440 $T/etc/sudoers.d/10-installer
cr visudo -c >/dev/null && echo "  sudoers: %wheel (gecerli)" || echo "  UYARI: visudo -c hata verdi"

echo
echo "########## 8/9  BILGISAYAR ADI, SAAT, DIL, KLAVYE, FSTAB, GRUB ##########"
echo "$KUL-atasos" > $T/etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 %s-atasos\n::1 localhost\n' "$KUL" > $T/etc/hosts
ln -sf /usr/share/zoneinfo/Europe/Istanbul $T/etc/localtime
printf 'LANG=tr_TR.UTF-8\n' > $T/etc/locale.conf
grep -q '^KEYMAP=' $T/etc/vconsole.conf 2>/dev/null || printf 'KEYMAP=trq\n' >> $T/etc/vconsole.conf
grep -q 'XkbLayout" "tr"' $T/etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null || echo "  UYARI: X klavye ayari tr degil"
: > $T/etc/machine-id; chmod 444 $T/etc/machine-id
sed -i -E "s|^UUID=[0-9a-f-]+[[:space:]]+/[[:space:]].*|UUID=$U4  /  ext4  defaults,noatime  1  1|" $T/etc/fstab
grep -qE "^UUID=$U4[[:space:]]+/[[:space:]]" $T/etc/fstab || dur "fstab kok satiri yazilamadi"
grep -q 652f2262 $T/etc/fstab && dur "fstab hala p5'i gosteriyor"
echo "  ad: $KUL-atasos | saat: Europe/Istanbul | dil: tr_TR.UTF-8 | klavye: trq/tr | kok: UUID=$U4"
if [ $OTO = 1 ]; then
    printf '[Autologin]\nUser=%s\nSession=plasmax11\n' "$KUL" > $T/etc/sddm.conf
    echo "  otomatik giris: acik (/etc/sddm.conf)"
else rm -f $T/etc/sddm.conf; echo "  otomatik giris: kapali"; fi
G=/etc/grub.d/45_atasos_kurulu
cat > $G <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "atasOS v35 (kurulu)" --class atasos {
    insmod part_gpt
    insmod ext2
    insmod all_video
    insmod gfxterm
    set gfxpayload=keep
    search --no-floppy --fs-uuid --set=root $U4
    linux /boot/vmlinuz-$KVER root=PARTUUID=$PU4 rw rootwait quiet loglevel=3
}
EOF
chmod 755 $G
update-grub 2>&1 | grep -iE 'error|done' | sed 's/^/  /'
grep -n 'menuentry "atasOS' /boot/grub/grub.cfg | sed 's/^/  /'

echo
echo "########## 9/9  OZET ##########"
sync
echo "  atasOS v35 $P4'e kuruldu. Bilgisayari yeniden baslat, GRUB'da 'atasOS v35 (kurulu)' sec."
echo "  Giris: $KUL $( [ $OTO = 1 ] && echo '(otomatik giris)' || echo '(parolanla)' )"
[ $YED = 1 ] && echo "  Eski /home yedegi: $YEDEK (isine yarayanlari al, sonra silebilirsin)"
echo "  Kayit: $LOG"
