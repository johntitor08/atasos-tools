#!/usr/bin/env bash
# atasOS v34'u GERCEK DISKE, atasos-71'in actigi p4 bolumune (ext4, etiket "atasos-kurulu") Kubuntu'dan kurar.
# Calamares KULLANILMAZ; betik Calamares'in yaptigini adim adim yapar:
#   ISO'daki sistemi bolume acar (unsquashfs) -> canliya ozel her seyi kaldirir (ISO'daki kurulum-temizle.sh) ->
#   kullanici + parola (parolayi SEN yazarsin) + sudo -> bilgisayar adi, saat dilimi, dil, klavye -> fstab ->
#   istege bagli parolasiz otomatik giris -> Kubuntu GRUB'una "atasOS v34 (kurulu)" girdisi.
# KORUMALAR: hedef YALNIZCA /dev/nvme0n1p4 ve etiketi "atasos-kurulu" olmali, boyutu 20-40 GiB, bos olmali
#   (yalniz lost+found). p1/p2/p3/p5'e yazilmaz; EFI bolumune ve UEFI kayitlarina dokunulmaz (atasOS kendi GRUB'unu
#   kurmaz, Kubuntu GRUB'undan acilir). ISO sha256'si once denetlenir.
# Kullanim (Konsole'da): sudo bash /home/eren/atasos-72-v34-diske-kur.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. Hicbir sey yapilmadi."; exit 1; }
LOG=/home/eren/atas3-loglar/atasos-72-v34-diske-kur.log
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS 72: v34'u p4'e kur  ($(date '+%F %T')) ##########"

D=/dev/nvme0n1; P4=${D}p4
ISO=$(ls -1 /veri/atasos-iso/atasos-live-v*.iso 2>/dev/null | sort -V | tail -1)
T=/mnt/atasos-kurulu; M=/mnt/atasos-iso-oku
KVER=6.16.1-atas6
dur(){ echo; echo "  DURDU: $*"; echo "  Kayit: $LOG"; exit 1; }
temizle(){ cd /; for m in $T/run $T/sys $T/proc $T/dev/pts $T/dev $T $M; do mountpoint -q "$m" && umount "$m"; done; sync; }
trap temizle EXIT
cr(){ chroot $T /usr/bin/env -i HOME=/root TERM=linux LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }

echo
echo "########## 1/8  DENETIM ##########"
[ -b $P4 ] || dur "$P4 yok. Once: sudo bash /home/eren/atasos-71-veri-kucult-yer-ac.sh"
[ "$(blkid -s LABEL -o value $P4)" = atasos-kurulu ] || dur "$P4 etiketi 'atasos-kurulu' degil; bu betik yalniz atasos-71'in actigi bolume kurar"
[ "$(blkid -s TYPE -o value $P4)" = ext4 ] || dur "$P4 ext4 degil"
BOY=$(( $(blockdev --getsize64 $P4) / 1024 / 1024 / 1024 ))
[ $BOY -ge 20 ] && [ $BOY -le 40 ] || dur "$P4 boyutu beklenmedik: $BOY GiB"
findmnt -rn -S $P4 >/dev/null && dur "$P4 bagli; once ayir"
[ -f "$ISO" ] && [ -f "$ISO.sha256" ] || dur "ISO ya da .sha256 yok: $ISO"
U4=$(blkid -s UUID -o value $P4); PU4=$(blkid -s PARTUUID -o value $P4)
[ -n "$U4" ] && [ -n "$PU4" ] || dur "UUID/PARTUUID okunamadi"
echo "  hedef: $P4 ($BOY GiB, UUID $U4)"
echo "  ISO  : $ISO"
echo -n "  sha256 denetleniyor... "; (cd "${ISO%/*}" && sha256sum -c --quiet "${ISO##*/}.sha256") && echo tamam || dur "ISO bozuk"
mkdir -p $T $M
mount $P4 $T || dur "$P4 baglanamadi"
ICERIK=$(ls -A $T | grep -vx 'lost+found')
[ -z "$ICERIK" ] || dur "$P4 bos degil (icinde: $(echo $ICERIK | head -c 200)). Yeniden kurmak icin once bicimlendir: sudo mkfs.ext4 -L atasos-kurulu $P4"

echo
echo "########## 2/8  KULLANICI BILGILERI ##########"
while :; do
    read -r -p "  Giris adi (kucuk harf, ornek: eren): " KUL
    printf '%s' "$KUL" | grep -qE '^[a-z_][a-z0-9_-]{0,31}$' && [ "$KUL" != root ] && break
    echo "    gecersiz ad: kucuk harf/rakam/-/_ , harfle baslamali"
done
read -r -p "  Tam adin (bos birakilabilir): " TAM
read -r -p "  Acilista parola sormadan otomatik giris olsun mu? (e/h): " OTO
case "$OTO" in e|E|evet|Evet|EVET) OTO=1;; *) OTO=0;; esac
echo "  ad: $KUL  | otomatik giris: $([ $OTO = 1 ] && echo evet || echo hayir)  | parolayi birazdan sistem soracak"
read -r -p "  Kurulum baslasin mi? Yalnizca $P4 yazilacak. 'evet' yaz: " C
C=$(printf '%s' "$C" | tr -d '[:space:]' | sed 's/E/e/g; s/V/v/g; s/T/t/g')
[ "$C" = evet ] || dur "iptal (yazilan: '$C'). Hicbir sey yazilmadi."

echo
echo "########## 3/8  SISTEM BOLUME ACILIYOR (unsquashfs, ~8 GB) ##########"
mount -o loop,ro "$ISO" $M || dur "ISO baglanamadi"
SQ=$M/live/filesystem.squashfs; [ -f $SQ ] || dur "ISO'da live/filesystem.squashfs yok"
S0=$(date +%s)
unsquashfs -f -q -d $T $SQ || dur "unsquashfs basarisiz"
umount $M
[ -f $T/boot/vmlinuz-$KVER ] || dur "acilan sistemde cekirdek yok (/boot/vmlinuz-$KVER)"
echo "  acildi: $(du -sh $T 2>/dev/null | cut -f1), $(( $(date +%s)-S0 )) sn"

echo
echo "########## 4/8  CANLIYA OZEL HER SEY KALDIRILIYOR ##########"
for m in dev dev/pts proc sys run; do mkdir -p $T/$m; done
mount --bind /dev $T/dev; mount --bind /dev/pts $T/dev/pts; mount -t proc proc $T/proc; mount -t sysfs sys $T/sys; mount -t tmpfs tmpfs $T/run
[ -x $T/usr/lib/atasos/kurulum-temizle.sh ] || dur "kurulum-temizle.sh yok"
cr /usr/lib/atasos/kurulum-temizle.sh || echo "  UYARI: kurulum-temizle.sh hata kodu $?"
for y in usr/bin/calamares usr/bin/atasos-kurulum etc/calamares etc/sudoers.d/40-live-calamares etc/polkit-1/rules.d/49-atasos-live.rules home/eren; do
    [ -e $T/$y ] && { echo "  KALDI: /$y <<<"; } ; done
grep -rqs '^\[Autologin\]' $T/etc/sddm.conf.d/ && echo "  KALDI: sddm.conf.d'de [Autologin] <<<" || echo "  canli kullanici, canli otomatik giris, canli kurallar ve Calamares kaldirildi"

echo
echo "########## 5/8  KULLANICI + PAROLA + SUDO ##########"
for g in users wheel audio video network; do cr getent group $g >/dev/null || cr groupadd $g; done
cr useradd -m -s /bin/bash -G users,wheel,audio,video,network ${TAM:+-c "$TAM"} "$KUL" || dur "useradd basarisiz"
echo "  kullanici '$KUL' olusturuldu (wheel: sudo kullanabilir)"
echo "  Simdi '$KUL' icin parola belirle (ekranda gorunmez; iki kez):"
n=0; until chroot $T /usr/bin/passwd "$KUL"; do n=$((n+1)); [ $n -ge 3 ] && dur "parola 3 kez belirlenemedi. Kurulum yarim; yeniden: sudo mkfs.ext4 -L atasos-kurulu $P4, sonra bu betik"; echo "  tekrar dene:"; done
# bos_mu: 0 = parola bos/yok, 1 = dolu. Ozet bicimi taninmazsa (crypt "*" dondururse) uyarir ve dolu sayar.
bos_mu(){ H=$(awk -F: -v u="$KUL" '$1==u{print $2}' $T/etc/shadow)
    case "$H" in '$'*) ;; *) return 0;; esac
    perl -e 'my $c = crypt("", $ARGV[0]); exit(!defined $c || $c =~ /^\*/ ? 2 : ($c eq $ARGV[0] ? 0 : 1))' "$H"; local r=$?
    [ $r = 2 ] && { echo "  UYARI: parola ozeti denetlenemedi (${H:0:4}...); bos birakmadigindan emin ol"; return 1; }
    return $r; }
n=0; while bos_mu; do   # bos parola: giris ekrani ve sudo kabul etmez (v33'teki hata) -> izin verme
    n=$((n+1)); [ $n -ge 3 ] && dur "parola bos ya da kaydedilmedi. Yeniden: sudo mkfs.ext4 -L atasos-kurulu $P4, sonra bu betik"
    echo "  Parola BOS olamaz (atasOS bos parolayla giris kabul etmez). Tekrar:"; chroot $T /usr/bin/passwd "$KUL"; done
echo "  parola kaydedildi"
cr passwd -l root >/dev/null 2>&1; echo "  root hesabi kilitli (yonetici islemleri: sudo)"
echo '%wheel ALL=(ALL:ALL) ALL' > $T/etc/sudoers.d/10-installer; chmod 440 $T/etc/sudoers.d/10-installer
cr visudo -c >/dev/null && echo "  sudoers: %wheel (gecerli)" || echo "  UYARI: visudo -c hata verdi"

echo
echo "########## 6/8  BILGISAYAR ADI, SAAT, DIL, KLAVYE, FSTAB ##########"
echo "$KUL-atasos" > $T/etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 %s-atasos\n::1 localhost\n' "$KUL" > $T/etc/hosts
ln -sf /usr/share/zoneinfo/Europe/Istanbul $T/etc/localtime
printf 'LANG=tr_TR.UTF-8\n' > $T/etc/locale.conf
grep -q '^KEYMAP=' $T/etc/vconsole.conf 2>/dev/null || printf 'KEYMAP=trq\n' >> $T/etc/vconsole.conf
grep -q 'XkbLayout" "tr"' $T/etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null || echo "  UYARI: X klavye ayari tr degil"
: > $T/etc/machine-id; chmod 444 $T/etc/machine-id      # ilk acilista systemd uretir
# fstab: ISO'daki kok satiri p5'i gosteriyordu -> yalniz kok satiri p4 ile degistirilir
sed -i -E "s|^UUID=[0-9a-f-]+[[:space:]]+/[[:space:]].*|UUID=$U4  /  ext4  defaults,noatime  1  1|" $T/etc/fstab
grep -qE "^UUID=$U4[[:space:]]+/[[:space:]]" $T/etc/fstab || dur "fstab kok satiri yazilamadi"
grep -q 652f2262 $T/etc/fstab && dur "fstab hala p5'i gosteriyor"
echo "  ad: $KUL-atasos | saat: Europe/Istanbul | dil: tr_TR.UTF-8 | klavye: trq/tr | kok: UUID=$U4"
if [ $OTO = 1 ]; then
    printf '[Autologin]\nUser=%s\nSession=plasmax11\n' "$KUL" > $T/etc/sddm.conf
    echo "  otomatik giris: acik (/etc/sddm.conf)"
else rm -f $T/etc/sddm.conf; echo "  otomatik giris: kapali"; fi

echo
echo "########## 7/8  KUBUNTU GRUB GIRDISI ##########"
G=/etc/grub.d/45_atasos_kurulu
cat > $G <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "atasOS v34 (kurulu)" --class atasos {
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
echo "########## 8/8  OZET ##########"
sync
echo "  atasOS v34 $P4'e kuruldu. Bilgisayari yeniden baslat, GRUB'da 'atasOS v34 (kurulu)' sec."
echo "  Giris: $KUL $( [ $OTO = 1 ] && echo '(otomatik giris)' || echo '(parolanla)' )"
echo "  Kaldirmak istersen: /etc/grub.d/45_atasos_kurulu sil + update-grub; p4'u bicimlendir."
echo "  Kayit: $LOG"
