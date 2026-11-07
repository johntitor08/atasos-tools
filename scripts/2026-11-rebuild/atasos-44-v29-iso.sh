#!/usr/bin/env bash
# atasOS v29 CANLI ISO + Calamares kurulum. Temmuz hattinin (v20 /root/.bash_history'den kurtarilan build-live-iso.sh +
# finalize5.sh) yeniden kurulmus hali; araclar (mksquashfs, grub-mkrescue, xorriso, mtools) atasOS'un KENDISINDEN calisir.
#
# p5'e DOKUNMAZ: ISO, p5'in ustune kurulan bir overlay gorunumunden (/veri/atasos-iso/kaynak) uretilir. Canliya ozel
# degisiklikler ve kisisel veri temizligi yalniz bu gorunumde yapilir:
#   - /home: yalniz eren, /etc/skel'den TEMIZ (senin dosyalarin, Firefox profili, olcek ayarin ISO'ya girmez)
#   - /root bos; sifre hash'leri silinir (eren sifresiz canli kullanici, digerleri kilitli)
#   - kayitli WiFi sifreleri, SSH anahtarlari, machine-id, bluetooth eslesmeleri, gunlukler silinir
#   - /boot ve /usr/lib/modules: yalniz calisan cekirdek (atas3)
#   - canliya ozel: sifresiz kurulum (sudoers + polkit); Calamares bunlari kurulan sistemden siler
#   - kurulan sisteme GRUB gfxpayload=keep (gercek donanimda siyah ekran duzeltmesi)
# Cikti: /veri/atasos-iso/atasos-live-v29.iso (+ .sha256)
# Kullanim: sudo bash /home/eren/atasos-44-v29-iso.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
SUR=29
A=/mnt/atasos
I=/veri/atasos-iso
K=$I/kaynak          # overlay birlesik gorunum (p5 + canli degisiklikler)
U=$I/ust; WK=$I/is   # overlay ust katman + calisma dizini
O=$I/cikti           # ISO agaci + ara dosyalar
ISO=$I/atasos-live-v$SUR.iso
BB=/home/eren/atas3-loglar/iso-inceleme/initrd/bin/busybox
LOG=$I/v$SUR-uretim.log
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
[ -x "$BB" ] && file "$BB" | grep -q 'statically linked' || { echo "HATA: statik busybox yok: $BB"; exit 1; }
if [ -e "$ISO" ]; then mv -f "$ISO" "$ISO.onceki"; rm -f "$ISO.sha256"; echo "  onceki ISO kenara alindi: $ISO.onceki"; fi
mkdir -p $A "$I"
mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){
    for m in $A/mnt/iso-cikti $A/mnt/iso-kaynak $A/tmp $A/sys $A/proc $A/dev/pts $A/dev "$K"; do mountpoint -q "$m" && umount "$m"; done
    umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"
    chown eren:eren "$I" "$ISO" "$ISO.sha256" "$LOG" 2>/dev/null; true; }
trap temizle EXIT
for d in $A/mnt/iso-kaynak $A/mnt/iso-cikti; do [ -d $d ] || { echo "  p5'te $d yok; bir kerelik olusturuluyor."; mount -o remount,rw $A && mkdir -p $d && mount -o remount,ro $A || { echo "HATA: $d olusturulamadi"; exit 1; }; }; done
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS v$SUR CANLI ISO  ($(date '+%F %T')) ##########"

echo
echo "########## 1/8  CEKIRDEK + OVERLAY ##########"
# en yeni atas cekirdegi (atas5: FUSE var -> canli ortamda grub-mount/os-prober calisir)
VMZ=$(ls $A/boot/vmlinuz-*-atas[0-9]* 2>/dev/null | sort -V | tail -1)
[ -n "$VMZ" ] || { echo "HATA: /boot/vmlinuz-*-atasN yok"; exit 1; }
grep -q '^CONFIG_FUSE_FS=y' $A/boot/config-${VMZ##*/vmlinuz-} 2>/dev/null || echo "  UYARI: ${VMZ##*/} cekirdeginde FUSE yok -> canlida os-prober calismaz"
KVER=${VMZ##*/vmlinuz-}
[ -d $A/usr/lib/modules/$KVER ] || { echo "HATA: /usr/lib/modules/$KVER yok"; exit 1; }
echo "  cekirdek: $KVER ($(stat -c%s "$VMZ") bayt)"
rm -rf "$U" "$WK" "$O"; mkdir -p "$U" "$WK" "$K" "$O/agac/boot/grub" "$O/agac/live"
mount -t overlay overlay -o lowerdir=$A,upperdir="$U",workdir="$WK" "$K" || { echo "HATA: overlay kurulamadi"; exit 1; }
echo "  overlay: $K (alt: p5 salt-okunur, ust: $U)"

echo
echo "########## 2/8  KISISEL VERI TEMIZLIGI (yalniz ISO gorunumunde) ##########"
EUID_=$(awk -F: '$1=="eren"{print $3}' $K/etc/passwd); EGID_=$(awk -F: '$1=="eren"{print $4}' $K/etc/passwd)
[ -n "$EUID_" ] || { echo "HATA: eren kullanicisi yok"; exit 1; }
find $K/home -mindepth 1 -maxdepth 1 -exec rm -rf {} +
find $K/root -mindepth 1 -maxdepth 1 -exec rm -rf {} +
echo "  /home ve /root bosaltildi"
rm -rf $K/etc/NetworkManager/system-connections/* $K/var/lib/NetworkManager/* $K/var/lib/iwd/* $K/var/lib/bluetooth/* 2>/dev/null
rm -f $K/etc/ssh/ssh_host_* $K/var/lib/systemd/random-seed $K/var/lib/systemd/credential.secret 2>/dev/null
rm -rf $K/var/lib/sddm/* $K/var/lib/systemd/coredump/* $K/var/lib/upower/* 2>/dev/null
: > $K/etc/machine-id; chmod 444 $K/etc/machine-id
# bu laptopa ozgu %200 giris ekrani (atasos-51) baska bilgisayarlarda dev gorunur
rm -f $K/etc/sddm.conf.d/20-atasos-olcek.conf
echo "  WiFi sifreleri, SSH anahtarlari, machine-id, bluetooth, sddm durumu temizlendi"
# sifre hash'leri: eren = sifresiz canli kullanici, hash'i olan herkes (root dahil) kilitli
cp -a $K/etc/shadow $K/etc/shadow.yeni
awk -F: 'BEGIN{OFS=":"} $1=="eren"{$2=""} $1!="eren" && $2 ~ /^\$/{$2="!"} {print}' $K/etc/shadow > $K/etc/shadow.yeni && cat $K/etc/shadow.yeni > $K/etc/shadow; rm -f $K/etc/shadow.yeni
echo "  shadow: $(awk -F: '$2 ~ /^\$/' $K/etc/shadow | wc -l) hash kaldi (0 olmali)"
# yalniz calisan cekirdek
for f in $K/boot/vmlinuz-* $K/boot/System.map-* $K/boot/config-*; do [ -e "$f" ] || continue; case "$f" in *-$KVER) ;; *) rm -f "$f"; echo "  /boot'tan cikarildi: ${f#$K}";; esac; done
for d in $K/usr/lib/modules/*; do [ "${d##*/}" = "$KVER" ] || { rm -rf "$d"; echo "  modul dizini cikarildi: ${d#$K}"; }; done
for f in $K/boot/grub/grub.cfg $K/boot/grub/grubenv; do [ -e "$f" ] && rm -f "$f"; done

echo
echo "########## 3/8  CANLI KULLANICI + KURULUM AYARLARI ##########"
install -d -m 700 -o $EUID_ -g $EGID_ $K/home/eren
cp -a $K/etc/skel/. $K/home/eren/
mkdir -p $K/home/eren/.config $K/home/eren/Desktop
# canli oturumda ekran kilidi kapali (sifresiz kullanici kilidi acamaz)
printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > $K/home/eren/.config/kscreenlockerrc
cp $K/usr/share/applications/calamares.desktop $K/home/eren/Desktop/atasos-kurulum.desktop
sed -i 's|^Name=.*|Name=atasOS Kur|; s|^Name\[tr_TR\]=.*|Name[tr_TR]=atasOS Kur|' $K/home/eren/Desktop/atasos-kurulum.desktop
chmod 755 $K/home/eren/Desktop/atasos-kurulum.desktop
chown -R $EUID_:$EGID_ $K/home/eren
echo "  /home/eren (canli) /etc/skel'den kuruldu + masaustunde 'atasOS Kur'"
mkdir -p $K/etc/sudoers.d
echo "eren ALL=(root) NOPASSWD: /usr/bin/atasos-kurulum, /usr/bin/calamares" > $K/etc/sudoers.d/40-live-calamares
chmod 440 $K/etc/sudoers.d/40-live-calamares
# LFS'nin sudoers'inda includedir yok -> sudoers.d hic okunmuyordu (v29 ilk uretimde sanal makinede bulundu)
grep -qE '^[@#]includedir[[:space:]]+/etc/sudoers\.d' $K/etc/sudoers || echo '@includedir /etc/sudoers.d' >> $K/etc/sudoers
chmod 440 $K/etc/sudoers
mkdir -p $K/etc/polkit-1/rules.d
cat > $K/etc/polkit-1/rules.d/49-atasos-live.rules <<'EOF'
// YALNIZ CANLI ISO: kurulum programi sifresiz calisir. Calamares bu dosyayi kurulan sistemden siler.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.atasos.kurulum.run" || action.id == "com.github.calamares.calamares.pkexec.run") &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF
echo "  canliya ozel: sudoers.d/40-live-calamares + polkit 49-atasos-live.rules"
echo "  sddm autologin: $(grep -hE '^(User|Session)=' $K/etc/sddm.conf.d/*.conf 2>/dev/null | tr '\n' ' ')"
# Kurulan sistemde canliya ozel her seyi kaldiran betik (Calamares shellprocess, hedef chroot'ta calistirir).
# v29 ilk kurulum testinde bulundu: p5'in otomatik giris dosyasi 10-atasos-otomatik-giris.conf adinda ve
# icinde DisplayServer=x11 de var -> dosya silinmez, yalniz [Autologin] bolumu cikarilir.
mkdir -p $K/usr/lib/atasos
cat > $K/usr/lib/atasos/kurulum-temizle.sh <<'EOF'
#!/bin/sh
# atasOS: Calamares tarafindan KURULAN sistemde calisir; canli ortama ozel her seyi kaldirir, sonra kendini siler.
userdel -r eren 2>/dev/null
userdel -r oyun 2>/dev/null
for f in /etc/sddm.conf.d/*.conf; do
    [ -f "$f" ] || continue
    awk 'BEGIN{s=0} /^\[/{s=($0=="[Autologin]")} !s' "$f" > "$f.yeni" && mv "$f.yeni" "$f" && chmod 644 "$f"
    grep -q '[^[:space:]]' "$f" || rm -f "$f"
done
rm -f /etc/sudoers.d/40-live-calamares /etc/polkit-1/rules.d/49-atasos-live.rules
rm -f /usr/lib/atasos/kurulum-temizle.sh
exit 0
EOF
chmod 755 $K/usr/lib/atasos/kurulum-temizle.sh
cat > $K/etc/calamares/modules/shellprocess.conf <<'EOF'
---
dontChroot: false
timeout: 120
verbose: true
script:
    - "/usr/lib/atasos/kurulum-temizle.sh"
EOF
echo "  Calamares shellprocess: /usr/lib/atasos/kurulum-temizle.sh (canli kullanicilar, [Autologin], canli kurallar)"
# DISK GUVENLIGI: v21-28 ISO'lari, kurulumda disk silindigi icin kayboldu. v20'den gelen ayarda "Diski sil" ONCEDEN
# SECILI geliyordu (initialPartitioningChoice: erase). Artik hicbir secenek secili gelmez; kullanici bilerek secmeden
# ilerleyemez. Kurulum baslamadan once son onay penceresi (prompt-install) de zorunlu.
sed -i 's|^\(\s*initialPartitioningChoice:\).*|\1 none|' $K/etc/calamares/modules/partition.conf
grep -q '^\s*initialPartitioningChoice:' $K/etc/calamares/modules/partition.conf || echo 'initialPartitioningChoice: none' >> $K/etc/calamares/modules/partition.conf
sed -i 's|^\(\s*prompt-install:\).*|\1 true|' $K/etc/calamares/settings.conf
grep -q '^\s*prompt-install:' $K/etc/calamares/settings.conf || echo 'prompt-install: true' >> $K/etc/calamares/settings.conf
echo "  disk guvenligi: $(grep -h -E '^\s*(initialPartitioningChoice|prompt-install):' $K/etc/calamares/modules/partition.conf $K/etc/calamares/settings.conf | tr -s ' ' | tr '\n' ' ')"
# kurulan sistemin GRUB'u: gercek donanimda siyah ekran duzeltmesi (simpledrm GRUB'un cerceve tamponunu devralir)
G=$K/etc/default/grub; mkdir -p $K/etc/default; touch $G
for kv in 'GRUB_DISTRIBUTOR="atasOS"' 'GRUB_TIMEOUT=5' 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"' 'GRUB_TERMINAL_OUTPUT="gfxterm"' 'GRUB_GFXMODE="auto"' 'GRUB_GFXPAYLOAD_LINUX="keep"' 'GRUB_DISABLE_OS_PROBER=false'; do
    k=${kv%%=*}; grep -q "^$k=" $G && sed -i "s|^$k=.*|$kv|" $G || echo "$kv" >> $G; done
echo "  /etc/default/grub: $(grep -E '^GRUB_(GFXPAYLOAD_LINUX|TERMINAL_OUTPUT)=' $G | tr '\n' ' ')"
HARIC=(sources 'tmp/*' 'var/tmp/*' 'var/cache/*' 'var/log/*' 'lost+found' kurtarma 'var/lib/atasos-paketler/yedek-*' 'mnt/iso-kaynak/*' 'mnt/iso-cikti/*' swapfile 'proc/*' 'sys/*' 'dev/*' 'run/*')
KB=$(du -sxk $K 2>/dev/null | cut -f1)
for h in $K/sources $K/var/cache $K/var/log $K/var/tmp $K/tmp $K/kurtarma $K/lost+found $K/swapfile $K/var/lib/atasos-paketler/yedek-*; do
    [ -e "$h" ] && KB=$(( KB - $(du -sxk "$h" 2>/dev/null | cut -f1) )); done
GB=$(( (KB * 13 / 10) / 1024 / 1024 + 2 ))
sed -i "s|^\(\s*requiredStorage:\).*|\1 $GB.0|" $K/etc/calamares/modules/welcome.conf
echo "  kurulu boyut ~$((KB/1024/1024)) GB -> Calamares gereken disk: $GB GB"

echo
echo "########## 4/8  INITRAMFS (busybox-static) ##########"
IR=$O/initramfs; rm -rf $IR; mkdir -p $IR/{bin,proc,sys,dev,run,newroot,mnt/medium,mnt/squash}
cp "$BB" $IR/bin/busybox; chmod 755 $IR/bin/busybox
mknod -m 600 $IR/dev/console c 5 1; mknod -m 666 $IR/dev/null c 1 3
cat > $IR/init <<'INIT'
#!/bin/busybox sh
# atasOS canli init (v20 init'inin gelistirilmis hali): ortami bul -> squashfs + overlay -> systemd
export PATH=/bin
busybox mount -t proc proc /proc 2>/dev/null
busybox mount -t sysfs sys /sys 2>/dev/null
busybox mount -t devtmpfs dev /dev 2>/dev/null
log(){ echo "[atasOS-live] $*" > /dev/kmsg 2>/dev/null; echo "[atasOS-live] $*"; }
log "init basliyor"
# USB bellek / CD / sanal disk: 30 sn boyunca tum blok aygitlari dene (USB'nin taninmasi birkac saniye surer)
n=0
while [ $n -lt 120 ]; do
  for d in /dev/sr[0-9] /dev/sd[a-z] /dev/sd[a-z][0-9] /dev/vd[a-z] /dev/vd[a-z][0-9] /dev/nvme[0-9]n[0-9] /dev/mmcblk[0-9]; do
    [ -b "$d" ] || continue
    busybox mount -t iso9660 -o ro "$d" /mnt/medium 2>/dev/null || continue
    if [ -f /mnt/medium/live/filesystem.squashfs ]; then MED="$d"; break 2; fi
    busybox umount /mnt/medium 2>/dev/null
  done
  n=$((n+1)); busybox sleep 0.25
done
if [ -z "${MED:-}" ]; then log "KURULUM ORTAMI BULUNAMADI - kabuga dusuluyor"; exec busybox sh; fi
log "ortam: $MED"
busybox mount -t squashfs -o ro,loop /mnt/medium/live/filesystem.squashfs /mnt/squash \
  || { log "squashfs baglanamadi"; exec busybox sh; }
busybox mount -t tmpfs -o mode=0755 tmpfs /run
busybox mkdir -p /run/upper /run/work
busybox mount -t overlay overlay -o lowerdir=/mnt/squash,upperdir=/run/upper,workdir=/run/work /newroot \
  || { log "overlay baglanamadi"; exec busybox sh; }
# canli sistemde fstab bos: systemd kurulum diskine dokunmasin
: > /newroot/etc/fstab 2>/dev/null
busybox mount -t tmpfs -o mode=0755 tmpfs /newroot/run
busybox mkdir -p /newroot/run/live/medium
busybox mount --move /mnt/medium /newroot/run/live/medium 2>/dev/null
log "systemd'ye geciliyor"
exec busybox switch_root /newroot /sbin/init
INIT
chmod 755 $IR/init
(cd $IR && find . | cpio -o -H newc -R 0:0 --quiet | gzip -9 > $O/agac/boot/initramfs.img) || { echo "HATA: initramfs"; exit 1; }
cp "$VMZ" $O/agac/boot/vmlinuz
echo "  initramfs: $(stat -c%s $O/agac/boot/initramfs.img) bayt, vmlinuz: $(stat -c%s $O/agac/boot/vmlinuz) bayt"
cat > $O/agac/boot/grub/grub.cfg <<GCFG
set default=0
set timeout=10
insmod all_video
insmod gfxterm
set gfxmode=auto
if loadfont unicode ; then terminal_output gfxterm ; fi
menuentry "atasOS v$SUR Canli" {
    set gfxpayload=keep
    linux /boot/vmlinuz quiet loglevel=3
    initrd /boot/initramfs.img
}
menuentry "atasOS v$SUR Canli (nomodeset - ekran gelmezse)" {
    linux /boot/vmlinuz nomodeset loglevel=4
    initrd /boot/initramfs.img
}
menuentry "atasOS v$SUR Canli (ayrintili / hata ayiklama)" {
    set gfxpayload=keep
    linux /boot/vmlinuz loglevel=7 console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}
GCFG
# 4 GB'tan buyuk squashfs icin (finalize5.sh): grub-mkrescue'nun xorriso cagrisina -iso-level 3 ekle
cat > $O/xorriso-sarmal.sh <<'W'
#!/bin/bash
args=()
for a in "$@"; do args+=("$a"); [ "$a" = "mkisofs" ] && args+=("-iso-level" "3"); done
exec /usr/bin/xorriso "${args[@]}"
W
chmod 755 $O/xorriso-sarmal.sh

echo
echo "########## 5/8  SQUASHFS (zstd 15 - uzun surer) ##########"
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
mount --bind "$K" $A/mnt/iso-kaynak; mount --bind "$O" $A/mnt/iso-cikti
mount -t tmpfs -o size=4G tmpfs $A/tmp   # p5 salt-okunur; grub-mkrescue /tmp'ye yazar
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=${TERM:-dumb} LC_ALL=C PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }
B=$(date +%s)
cr mksquashfs /mnt/iso-kaynak /mnt/iso-cikti/agac/live/filesystem.squashfs -comp zstd -Xcompression-level 15 -noappend \
   -wildcards -e "${HARIC[@]}" || { echo "HATA: mksquashfs"; exit 1; }
echo "  squashfs: $(( $(stat -c%s $O/agac/live/filesystem.squashfs) / 1024 / 1024 )) MB, $(( ($(date +%s)-B) / 60 )) dk"

echo
echo "########## 6/8  DOGRULAMA (squashfs icerigi) ##########"
cr unsquashfs -l /mnt/iso-cikti/agac/live/filesystem.squashfs > $O/icerik.txt 2>/dev/null
H=0
for y in etc/sudoers.d/40-live-calamares etc/polkit-1/rules.d/49-atasos-live.rules home/eren/Desktop/atasos-kurulum.desktop usr/lib/atasos/kurulum-temizle.sh usr/bin/atasos-kurulum usr/bin/calamares \
         etc/calamares/settings.conf etc/systemd/system/multi-user.target.wants/atasos-live-medium.service boot/vmlinuz-$KVER usr/lib/modules/$KVER usr/bin/plasmashell usr/bin/mksquashfs; do
    grep -qE "^squashfs-root/$y$" $O/icerik.txt && printf '  var : /%s\n' "$y" || { printf '  YOK : /%s <<<\n' "$y"; H=1; }
done
for y in 'etc/NetworkManager/system-connections/' 'etc/ssh/ssh_host_' 'home/eren/.mozilla' 'root/.' 'sources/' 'plasma-workspace/env/atasos-olcek'; do
    c=$(grep -cF "squashfs-root/$y" $O/icerik.txt); printf '  temiz (%s): %s\n' "$y" "$([ "$c" -eq 0 ] && echo evet || { H=1; echo "HAYIR, $c girdi <<<"; })"
done
grep -qE '^\s*initialPartitioningChoice:\s*none' $K/etc/calamares/modules/partition.conf && grep -qE '^\s*prompt-install:\s*true' $K/etc/calamares/settings.conf \
    && echo "  disk guvenligi: on-secim yok + son onay var" || { echo "  disk guvenligi: AYAR TUTMADI <<<"; H=1; }
[ -x $K/usr/bin/grub-mount ] && [ -x $K/usr/bin/os-prober ] && echo "  os-prober + grub-mount var" || { echo "  os-prober/grub-mount YOK <<<"; H=1; }
grep -qE '^[@#]includedir[[:space:]]+/etc/sudoers\.d' $K/etc/sudoers && echo "  sudoers: @includedir var" || { echo "  sudoers: @includedir YOK <<<"; H=1; }
[ $H -eq 0 ] || { echo "  DURDU: squashfs dogrulamasi basarisiz. ISO uretilmedi (squashfs: $O/agac/live/)."; exit 1; }

echo
echo "########## 7/8  ISO (grub-mkrescue, BIOS + UEFI) ##########"
cr grub-mkrescue --xorriso=/mnt/iso-cikti/xorriso-sarmal.sh -o /mnt/iso-cikti/atasos-live-v$SUR.iso /mnt/iso-cikti/agac > $O/mkrescue.log 2>&1
S=$?; tail -4 $O/mkrescue.log | sed 's/^/  /'
[ $S -eq 0 ] && [ -s $O/atasos-live-v$SUR.iso ] || { echo "  HATA: grub-mkrescue (rc=$S, $O/mkrescue.log)"; exit 1; }
cr xorriso -indev /mnt/iso-cikti/atasos-live-v$SUR.iso -report_el_torito plain 2>/dev/null | grep -iE 'El Torito|platform' | head -6 | sed 's/^/  /' || true
mv $O/atasos-live-v$SUR.iso "$ISO"
echo "  etiket: $(blkid -o value -s LABEL "$ISO" 2>/dev/null)  (atasos-live-medium ISOIMAGE bekliyor)"

echo
echo "########## 8/8  OZET ##########"
(cd "$I" && sha256sum "${ISO##*/}" > "${ISO##*/}.sha256")
echo "  ISO   : $ISO ($(( $(stat -c%s "$ISO") / 1024 / 1024 )) MB)"
echo "  sha256: $(cut -c1-16 "$ISO.sha256")..."
echo "  kayit : $LOG"
rm -rf "$O/initramfs"
echo "  Ara dosyalar $O ve overlay ust katmani $U icinde (silinebilir)."
echo "  Test: USB'ye yaz (dd/Ventoy/Impression) veya sanal makinede ac. GRUB'da 'atasOS v$SUR Canli'."
