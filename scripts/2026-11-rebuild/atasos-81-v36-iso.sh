#!/usr/bin/env bash
# atasOS v36 CANLI ISO = v35 + YAMALI CALAMARES 3.3.14 (kaynaktan, overlay icinde derlenir; p5'e dokunulmaz):
#   - "Yanina kur": yeni bolum 1 MiB sinirindan baslar (eskiden kuculen bolumun sonu + 2 sektor: hizasiz)
#   - "Yanina kur": cubugun varsayilani bolumdeki verinin altina inemez (eskiden %45'ten dolu bolumde imkansiz kucultme)
#   - "Diski sil": son "Simdi kur" onayinda silinecek disk adiyla kirmizi DIKKAT uyarisi
#   - menude "Firefox'u Guncelle": Mozilla'nin imzali en yeni Firefox'u /opt/firefox'a kurar (pkexec, Konsole)
#   - GUNCELLEME KANALI GUVEN TEMELI (atasos-79): atspkg 0.3.0 + depo acik anahtari (atasos-78 uretir):
#     depo dizini (atspkg.index) yalniz bu anahtarla imzaliysa kabul edilir; indirmelerde TLS her zaman dogrulanir
#   - kurulan sistemin GRUB'u: diskte baska isletim sistemi yoksa menu gizli (1 sn, Esc ile acilir), varsa 3 sn
#   - (atasos-81) "Sistemi sifrele" kutusu gizli: initramfs yok -> LUKS kok acilista cozulemez. Otomatik secenekler
#     partition.conf enableLuksAutomatedPartitioning: false; elle bolumlemede ayni ayar yamayla uygulanir
#   Kaynaklar + yama: /veri/atasos-iso/calamares-yama/ (sha256 denetlenir). Kubuntu GRUB'una ISO girdisi EKLENMEZ (atasos-75).
# v35 = v34 + Calamares'in diger sistemlere saygisi (v34 sanal NVMe testlerinde bulundu, atasos-73):
#   - EFI yedek onyukleyicisi (EFI/BOOT/BOOTX64.EFI) artik YALNIZ YOKSA yazilir; vardi ise (Kubuntu shim'i) dokunulmaz
#   - kurulan GRUB root=PARTUUID=... kullanir (eskiden root=/dev/nvme0n1pN: disk sirasi degisirse acilmazdi)
#   - kurulan sisteme gereksiz /tcl-backup klasoru girmez
# v34 = v33 + kurulumda BOS SIFRE ENGELI ve calisan "parolasiz otomatik giris" kutusu
# (v33 sanal makine kurulum testinde bulundu: bos sifre kabul ediliyordu -> kurulan sisteme hic girilemiyordu).
# v33 = v32 + Flatpak 1.16.1 ve Flathub deposu (atasos-65; Steam: flatpak install flathub com.valvesoftware.Steam).
# v32 = v31 + giris ekraninda Wayland oturumu gizli (v31 kurulum testinde: Wayland calismiyor ama
# yeni sistemde varsayilan seciliydi -> ilk giris acilmiyordu). v31: v30 + atas6 cekirdegi (AMD/NVIDIA/MediaTek), atasos-59 masaustu: koyu tema,
# duvar kagidi, panel, GRUB temasi; v30 kurulum testinde bulunan duzeltmeler: sudo, varsayilan X11 oturumu, simge, renkler). Temmuz hattinin (v20 /root/.bash_history'den kurtarilan build-live-iso.sh +
# finalize5.sh) yeniden kurulmus hali; araclar (mksquashfs, grub-mkrescue, xorriso, mtools) atasOS'un KENDISINDEN calisir.
#
# p5'e DOKUNMAZ: ISO, p5'in ustune kurulan bir overlay gorunumunden (/veri/atasos-iso/kaynak) uretilir. Canliya ozel
# degisiklikler ve kisisel veri temizligi yalniz bu gorunumde yapilir:
#   - /home: yalniz eren, /etc/skel'den TEMIZ (senin dosyalarin, Firefox profili, olcek ayarin ISO'ya girmez)
#   - /root bos; sifre hash'leri silinir (eren sifresiz canli kullanici, digerleri kilitli)
#   - kayitli WiFi sifreleri, SSH anahtarlari, machine-id, bluetooth eslesmeleri, gunlukler silinir
#   - /boot ve /usr/lib/modules: yalniz en yeni atas cekirdegi
#   - canliya ozel: sifresiz kurulum (sudoers + polkit); Calamares bunlari kurulan sistemden siler
#   - kurulan sisteme GRUB gfxpayload=keep (gercek donanimda siyah ekran duzeltmesi)
#   - kurulan sistemde Calamares (program, kutuphaneler, ayarlar, menu girdisi) kurulumun sonunda silinir
# Cikti: /veri/atasos-iso/atasos-live-v36.iso (+ .sha256)
# Kullanim: sudo bash /home/eren/atasos-81-v36-iso.sh  (once: bash ~/atasos-78-depo-anahtari.sh)
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
SUR=36
A=/mnt/atasos
I=/veri/atasos-iso
CY=$I/calamares-yama  # kaynak arsivleri (ar/) + atasos-calamares-3.3.14.patch
K=$I/kaynak          # overlay birlesik gorunum (p5 + canli degisiklikler)
U=$I/ust; WK=$I/is   # overlay ust katman + calisma dizini
O=$I/cikti           # ISO agaci + ara dosyalar
ISO=$I/atasos-live-v$SUR.iso
BB=/home/eren/atas3-loglar/iso-inceleme/initrd/bin/busybox
LOG=$I/v$SUR-uretim.log
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
[ -x "$BB" ] && file "$BB" | grep -q 'statically linked' || { echo "HATA: statik busybox yok: $BB"; exit 1; }
# v36: Calamares kaynaklari + yama (indirilen resmi arsivler; sha256 sabit)
for kv in "ar/calamares-3.3.14.tar.gz 5547f80db067dea923ae693ba6bb88eb2b2eeac1da3ebec42fce453e31c290c0" \
          "ar/kpmcore-25.04.3.tar.xz 6c22e9068fa1e7a4a4a64def7636bb3498b977cf77752d126f1b4e1143f48c95" \
          "ar/yaml-cpp-0.8.0.tar.gz fbe74bbdcee21d656715688706da3c8becfd946d92cd44705cc6098bb23b3a16" \
          "atasos-calamares-3.3.14.patch 0fcc9a5272e275aca305593651f83c3e85302442ffaf3611a78917515c4577fc"; do
    f=$CY/${kv%% *}; h=${kv##* }
    [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$h" ] || { echo "HATA: $f yok ya da sha256 tutmuyor. Hicbir sey yapilmadi."; exit 1; }
done
# v36: guncelleme kanali (atspkg 0.3.0 + depo acik anahtari; anahtar atasos-78 ile kullanicinin bilgisayarinda uretilir)
KN=$I/kanal
[ "$(sha256sum $KN/atspkg-0.3.0 2>/dev/null | cut -d' ' -f1)" = 9fd185ccca487009508847ce0b3ac15efeabb11dc4c012e62b93db585b634049 ] \
    || { echo "HATA: $KN/atspkg-0.3.0 yok ya da sha256 tutmuyor. Hicbir sey yapilmadi."; exit 1; }
[ -s $KN/depo-anahtari.gpg ] && [ -s $KN/parmak-izi.txt ] \
    || { echo "HATA: depo anahtari yok. Once (root DEGIL): bash /home/eren/atasos-78-depo-anahtari.sh . Hicbir sey yapilmadi."; exit 1; }
DFPR=$(cat $KN/parmak-izi.txt)
GH=$(mktemp -d); KFPR=$(gpg --homedir "$GH" --batch --with-colons --show-keys $KN/depo-anahtari.gpg 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}'); rm -rf "$GH"
[ -n "$DFPR" ] && [ "$KFPR" = "$DFPR" ] || { echo "HATA: depo-anahtari.gpg parmak izi ($KFPR) parmak-izi.txt ($DFPR) ile tutmuyor"; exit 1; }
GH=$(mktemp -d); gpg --homedir "$GH" --batch --list-packets $KN/depo-anahtari.gpg 2>/dev/null | grep -c 'secret key packet' >/dev/null; GS=$?; rm -rf "$GH"; [ $GS -eq 0 ] \
    && { echo "HATA: depo-anahtari.gpg GIZLI anahtar iceriyor; ISO'ya konmaz"; exit 1; }
if [ -e "$ISO" ]; then mv -f "$ISO" "$ISO.onceki"; rm -f "$ISO.sha256"; echo "  onceki ISO kenara alindi: $ISO.onceki"; fi
mkdir -p $A "$I"
mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){
    for m in $A/mnt/iso-cikti $A/mnt/iso-kaynak $A/tmp $A/sys $A/proc $A/dev/pts $A/dev "$K/sys" "$K/proc" "$K/dev/pts" "$K/dev" "$K"; do mountpoint -q "$m" && umount "$m"; done
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
# v30 testinde bulundu: dile ozel Icon[tr_TR]=calamares satirlari Icon=atasos'u eziyordu -> hepsi silinir
sed -i '/^Icon\[/d' $K/usr/share/applications/calamares.desktop
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
# kurulu sistemde kurulum programina gerek yok (menude "atasOS Kur" kalmasin)
rm -rf /etc/calamares /usr/lib64/calamares /usr/share/calamares
rm -f /usr/bin/calamares /usr/bin/atasos-kurulum /usr/lib64/libcalamares.so* /usr/lib64/libcalamaresui.so* \
      /usr/share/applications/calamares.desktop* /usr/share/icons/hicolor/scalable/apps/calamares.svg \
      /usr/share/polkit-1/actions/com.github.calamares.calamares.policy /usr/share/polkit-1/actions/org.atasos.kurulum.policy
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications
ldconfig 2>/dev/null
# v35: EFI yedek onyukleyici (bazi bilgisayarlar NVRAM girdisini unutunca buna bakar). Calamares'te kapali
# (installEFIFallback: false) cunku VARSA ustune yaziyordu: gercek diskte EFI/BOOT/BOOTX64.EFI Kubuntu'nun shim'i.
# Burada yalniz YOKSA (bos disk, "Diski sil") atasOS'un GRUB'u kopyalanir. vfat buyuk/kucuk harf duyarsiz.
if [ -f /boot/efi/EFI/atasOS/grubx64.efi ] && [ ! -e /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    mkdir -p /boot/efi/EFI/BOOT && cp /boot/efi/EFI/atasOS/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI \
        && echo "atasOS: EFI/BOOT/BOOTX64.EFI yoktu, atasOS GRUB'u yedek onyukleyici olarak yazildi"
else
    echo "atasOS: EFI/BOOT/BOOTX64.EFI zaten var (baska sistemin) ya da EFI yok -> dokunulmadi"
fi
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
echo "  Calamares shellprocess: /usr/lib/atasos/kurulum-temizle.sh (canli kullanicilar, [Autologin], canli kurallar, Calamares, EFI yedegi yalniz yoksa)"
# v35: Calamares EFI yedek onyukleyicisini VARSA DA ustune yaziyordu (v34 NVMe testi: EFI/boot/bootx64.efi her secenekte
# yazildi; gercek diskte orada Kubuntu'nun shim'i var). Kapatildi; yoksa yazma isi kurulum-temizle.sh'de.
BL=$K/etc/calamares/modules/bootloader.conf
sed -i -E 's/^(\s*installEFIFallback:).*/\1 false/' $BL
grep -qE '^\s*installEFIFallback:' $BL || echo 'installEFIFallback: false' >> $BL
echo "  bootloader.conf: $(grep -E '^\s*(installEFIFallback|efiBootloaderId):' $BL | tr -s ' ' | tr '\n' ' ')"
# Calamares 3.3 renk anahtarlari buyuk harfle (Sidebar...); v20'den gelen kucuk harfliler yok sayiliyordu (siyah kenar cubugu)
BD=$K/etc/calamares/branding/atasos/branding.desc
sed -i -E '/^\s*(sidebar|Sidebar)[A-Za-z]*:/d' $BD
sed -i -E 's/^style:\s*$/style:\n    SidebarBackground: "#1b2733"\n    SidebarText: "#ffffff"\n    SidebarBackgroundCurrent: "#3daee9"\n    SidebarTextCurrent: "#ffffff"/' $BD
grep -q '^style:' $BD || printf 'style:\n    SidebarBackground: "#1b2733"\n    SidebarText: "#ffffff"\n    SidebarBackgroundCurrent: "#3daee9"\n    SidebarTextCurrent: "#ffffff"\n' >> $BD
echo "  Calamares renkleri: $(grep -cE '^\s*Sidebar' $BD) anahtar"
# bilgisayar adi sanal makine/donanim adindan degil: <kullanici>-atasos
U_=$K/etc/calamares/modules/users.conf
sed -i '/^hostname:/,/^[^ ]/{/^hostname:/d;/^ /d}' $U_
printf 'hostname:\n    location: EtcFile\n    writeHostsFile: true\n    template: "${first}-atasos"\n    forbidden_names: [ localhost ]\n' >> $U_
# v30 kurulum testinde bulundu: kurulan kullanici wheel'de ama sudoers'ta %wheel kurali yoktu -> sudo calismiyordu.
# Calamares bu ayarla hedefe /etc/sudoers.d/10-installer yazar (@includedir yukarida ekleniyor).
sed -i '/^sudoersGroup:/d' $U_; echo 'sudoersGroup: wheel' >> $U_
echo "  users.conf: bilgisayar adi sablonu $(grep -E 'template:' $U_ | tr -s ' ')"
# v30 testinde bulundu: giris ekraninda iki "Plasma (X11)" (xsessions/plasma.desktop eski kopya) ve yeni sistemde
# varsayilan Wayland seciliydi. atasOS'un oturumu plasmax11.
[ -f $K/usr/share/xsessions/plasmax11.desktop ] && rm -f $K/usr/share/xsessions/plasma.desktop
grep -q '^DefaultSession=' $K/etc/sddm.conf.d/30-atasos-klavye.conf || sed -i 's/^\[General\]$/[General]\nDefaultSession=plasmax11.desktop/' $K/etc/sddm.conf.d/30-atasos-klavye.conf
# v31 kurulum testinde bulundu: Plasma Wayland oturumu atasOS'ta acilmiyor (giris ekranina geri donuyor), SDDM ise
# yeni sistemde onu secili getiriyordu. Wayland oturumlari giris ekranindan gizlenir (bos klasor) -> tek oturum X11.
mkdir -p $K/usr/share/atasos/wayland-oturum-yok
grep -q '^\[Wayland\]' $K/etc/sddm.conf.d/30-atasos-klavye.conf || printf '\n[Wayland]\n# atasOS: Plasma Wayland calismiyor; giris ekraninda yalniz X11\nSessionDir=/usr/share/atasos/wayland-oturum-yok\n' >> $K/etc/sddm.conf.d/30-atasos-klavye.conf
echo "  oturumlar: $(ls $K/usr/share/xsessions | tr '\n' ' ')/ $(grep -h '^DefaultSession=' $K/etc/sddm.conf.d/*.conf)"
# eski betiklerin biraktigi .yedek-* menu dosyalari ISO'ya girmesin
find $K/usr/share/applications -maxdepth 1 -name '*.yedek-*' -print -delete | sed 's|^|  silindi: |'
# DISK GUVENLIGI: v21-28 ISO'lari, kurulumda disk silindigi icin kayboldu. v20'den gelen ayarda "Diski sil" ONCEDEN
# SECILI geliyordu (initialPartitioningChoice: erase). Artik hicbir secenek secili gelmez; kullanici bilerek secmeden
# ilerleyemez. Kurulum baslamadan once son onay penceresi (prompt-install) de zorunlu.
sed -i 's|^\(\s*initialPartitioningChoice:\).*|\1 none|' $K/etc/calamares/modules/partition.conf
# v36 (atasos-81): sifreleme kapali (initramfs yok; sifreli kok acilmaz)
P_=$K/etc/calamares/modules/partition.conf
sed -i -E '/^\s*#?\s*enableLuksAutomatedPartitioning:/d; /^\s*#?\s*preCheckEncryption:/d' $P_
printf 'enableLuksAutomatedPartitioning: false\npreCheckEncryption: false\n' >> $P_
echo "  sifreleme: $(grep -E '^(enableLuksAutomatedPartitioning|preCheckEncryption):' $P_ | tr '\n' ' ')(initramfs yok)"
grep -q '^\s*initialPartitioningChoice:' $K/etc/calamares/modules/partition.conf || echo 'initialPartitioningChoice: none' >> $K/etc/calamares/modules/partition.conf
sed -i 's|^\(\s*prompt-install:\).*|\1 true|' $K/etc/calamares/settings.conf
grep -q '^\s*prompt-install:' $K/etc/calamares/settings.conf || echo 'prompt-install: true' >> $K/etc/calamares/settings.conf
echo "  disk guvenligi: $(grep -h -E '^\s*(initialPartitioningChoice|prompt-install):' $K/etc/calamares/modules/partition.conf $K/etc/calamares/settings.conf | tr -s ' ' | tr '\n' ' ')"
# v34 (v33 kurulum testinde bulundu): Calamares BOS sifreyi kabul ediyordu (allowWeakPasswords: true, kural yok;
# kutular bosken yesil onay isareti). Kullanici bos sifre hash'iyle olusuyor, PAM'de nullok olmadigi icin giris
# ekrani ve konsol girisi reddediyor, root da kilitli kaliyordu -> kurulan sisteme hic girilemiyordu.
# Artik tek kural "en az 1 karakter" ve zorunlu; zayif ama dolu sifreler kabul edilir.
# DIKKAT: Calamares 3.3.14 "nonempty: true" kuralini YOK SAYAR ("nonempty check is ignored; use minLength: 1");
# v34'un ilk uretimi bu yuzden bos sifreyi hala kabul ediyordu (VM testinde bulundu). minLength: 1 ile kutular
# bosken "Parola pek kisa" + Sonraki kapali (VM'de dogrulandi).
U_=$K/etc/calamares/modules/users.conf
sed -i -E '/^(allowWeakPasswords|allowWeakPasswordsDefault):/d' $U_
sed -i '/^passwordRequirements:/,/^[^ ]/{/^passwordRequirements:/d;/^ /d}' $U_
printf 'allowWeakPasswords: false\nallowWeakPasswordsDefault: false\npasswordRequirements:\n    minLength: 1\n' >> $U_
echo "  users.conf: bos sifre engelli ($(grep -E '^(allowWeakPasswords|  +minLength):' $U_ | tr -s ' ' | tr '\n' ' '))"
# v34: "Parolayi sormadan kendiliginden oturum ac" kutusu ise yaramiyordu: ayari giris ekranina yazan displaymanager
# adimi kurulum sirasinda hic calismiyordu. Calamares bunu /etc/sddm.conf [Autologin] olarak yazar (kutu bossa
# User satirini siler). kurulum-temizle.sh yalniz /etc/sddm.conf.d/*.conf'taki (canli sistemden kalan) [Autologin]'i
# siler, /etc/sddm.conf'a dokunmaz. displaymanager, shellprocess'ten SONRA calisir.
cat > $K/etc/calamares/modules/displaymanager.conf <<'EOF'
---
displaymanagers:
  - sddm
defaultDesktopEnvironment:
    executable: "startplasma-x11"
    desktopFile: "plasmax11"
basicSetup: false
sysconfigSetup: false
EOF
S_=$K/etc/calamares/settings.conf
grep -qE '^\s*-\s*displaymanager\s*$' $S_ || sed -i -E 's/^(\s*)-\s*shellprocess\s*$/&\n\1- displaymanager/' $S_
echo "  otomatik giris: $(grep -E '^\s*-\s*(shellprocess|displaymanager)\s*$' $S_ | tr -d ' ' | tr '\n' ' ')"
# kurulan sistemin GRUB'u: gercek donanimda siyah ekran duzeltmesi (simpledrm GRUB'un cerceve tamponunu devralir)
G=$K/etc/default/grub; mkdir -p $K/etc/default; touch $G
for kv in 'GRUB_DISTRIBUTOR="atasOS"' 'GRUB_TIMEOUT=3' 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"' 'GRUB_TERMINAL_OUTPUT="gfxterm"' 'GRUB_GFXMODE="auto"' 'GRUB_GFXPAYLOAD_LINUX="keep"' 'GRUB_DISABLE_OS_PROBER=false' 'GRUB_THEME="/usr/share/grub/themes/atasos/theme.txt"' 'GRUB_DISABLE_LINUX_PARTUUID=false'; do
    k=${kv%%=*}; grep -q "^$k=" $G && sed -i "s|^$k=.*|$kv|" $G || echo "$kv" >> $G; done
# v35: initramfs yok -> root=UUID= calismaz; 10_linux PARTUUID'yi yalniz bu ayar false ise kullanir, yoksa
# root=/dev/nvme0n1pN yaziyordu (v34 NVMe testi). PARTUUID'yi cekirdek initramfs'siz cozer (72 betigi de boyle).
echo "  /etc/default/grub: $(grep -E '^GRUB_(GFXPAYLOAD_LINUX|TERMINAL_OUTPUT|DISABLE_LINUX_PARTUUID)=' $G | tr '\n' ' ')"
HARIC=(sources tcl-backup 'tmp/*' 'var/tmp/*' 'var/cache/*' 'var/log/*' 'lost+found' kurtarma 'var/lib/atasos-paketler/yedek-*' 'mnt/iso-kaynak/*' 'mnt/iso-cikti/*' swapfile 'proc/*' 'sys/*' 'dev/*' 'run/*')
KB=$(du -sxk $K 2>/dev/null | cut -f1)
for h in $K/sources $K/var/cache $K/var/log $K/var/tmp $K/tmp $K/kurtarma $K/lost+found $K/swapfile $K/var/lib/atasos-paketler/yedek-*; do
    [ -e "$h" ] && KB=$(( KB - $(du -sxk "$h" 2>/dev/null | cut -f1) )); done
GB=$(( (KB * 13 / 10) / 1024 / 1024 + 2 ))
sed -i "s|^\(\s*requiredStorage:\).*|\1 $GB.0|" $K/etc/calamares/modules/welcome.conf
echo "  kurulu boyut ~$((KB/1024/1024)) GB -> Calamares gereken disk: $GB GB"

# v36: Firefox guncelleme menusu (Mozilla'nin imzali resmi surumu; /opt/firefox root'a ait oldugu icin
# Firefox kendini guncelleyemiyordu). Firefox'un kendi "guncelleme yapilamadi" uyarisi kapatilir.
cat > $K/usr/bin/atasos-firefox-guncelle <<'FFG'
#!/bin/bash
# atasOS: Firefox'u Mozilla'nin resmi en yeni surumuyle gunceller (/opt/firefox, Turkce).
# Indirme Mozilla'nin imzali SHA512SUMS dosyasiyla dogrulanir (anahtar parmak izi asagida sabit).
# Menu: "Firefox'u Guncelle" (Konsole icinde; parola pkexec ile sorulur). Elle: atasos-firefox-guncelle [--zorla]
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || exec pkexec /usr/bin/atasos-firefox-guncelle "$@"
F=/opt/firefox
MOZ_FPR=14F26682D0916CDD81E37B6D61B7B526D98F0353   # Mozilla Software Releases <release@mozilla.com>
Y=""; T=""
son(){ [ -n "$T" ] && gpgconf --homedir "$T/gnupg" --kill all 2>/dev/null; [ -n "$T" ] && rm -rf "$T"; [ -n "$Y" ] && rm -rf "$Y"; }
trap son EXIT
dur(){ echo; echo "  HATA: $*"; echo "  Firefox degistirilmedi."; exit 1; }

echo "== Firefox guncelleme =="
MEVCUT=$(sed -n 's/^Version=//p' $F/application.ini 2>/dev/null | head -1)
echo "  kurulu surum : ${MEVCUT:-yok}"
U=$(curl -sSIL --max-time 30 -o /dev/null -w '%{url_effective}' 'https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=tr') \
    || dur "Mozilla'ya ulasilamadi (internet bagli mi?)"
case "$U" in https://download-installer.cdn.mozilla.net/pub/firefox/releases/*|https://archive.mozilla.org/pub/firefox/releases/*) ;;
    *) dur "beklenmeyen indirme adresi: $U" ;; esac
V=$(printf '%s\n' "$U" | grep -oE 'releases/[0-9][0-9.a-z]*[0-9]' | cut -d/ -f2); D=$(basename "$U")
[ -n "$V" ] && [ -n "$D" ] || dur "surum okunamadi ($U)"
echo "  en yeni surum: $V"
if [ "$V" = "$MEVCUT" ] && [ "${1:-}" != "--zorla" ]; then echo; echo "  Firefox zaten guncel. Yapilacak bir sey yok."; exit 0; fi
if pgrep -f '^/opt/firefox/firefox' >/dev/null; then dur "Firefox acik. Once Firefox'u kapatin, sonra yeniden deneyin."; fi

T=$(mktemp -d /var/tmp/atasos-ff.XXXXXX) || dur "gecici klasor acilamadi"
R=https://archive.mozilla.org/pub/firefox/releases/$V
echo; echo "== indiriliyor: $D"
curl -fL --retry 3 --progress-bar -o "$T/$D" "$U" || dur "indirilemedi"
for f in SHA512SUMS SHA512SUMS.asc KEY; do curl -sSfL --retry 3 -o "$T/$f" "$R/$f" || dur "$f indirilemedi"; done

echo "== dogrulaniyor"
G=$T/gnupg; mkdir -m 700 "$G"
gpg --homedir "$G" --batch --quiet --import "$T/KEY" 2>/dev/null || dur "Mozilla anahtari okunamadi"
gpg --homedir "$G" --batch --with-colons --fingerprint 2>/dev/null | grep -q "^fpr:*$MOZ_FPR:" || dur "Mozilla anahtari beklenen anahtar degil"
IMZA=$(gpg --homedir "$G" --batch --status-fd 1 --verify "$T/SHA512SUMS.asc" "$T/SHA512SUMS" 2>/dev/null | awk '$2=="VALIDSIG"{print $NF}')
[ "$IMZA" = "$MOZ_FPR" ] || dur "SHA512SUMS imzasi gecersiz"
echo "  imza: Mozilla (gecerli)"
BEK=$(awk -v y="linux-x86_64/tr/$D" '$2==y{print $1}' "$T/SHA512SUMS")
[ -n "$BEK" ] || dur "SHA512SUMS'ta linux-x86_64/tr/$D yok"
[ "$(sha512sum "$T/$D" | cut -d' ' -f1)" = "$BEK" ] || dur "indirilen dosya bozuk (sha512 tutmuyor)"
echo "  sha512: tutuyor"

echo "== kuruluyor"
Y=$(mktemp -d /opt/.firefox-yeni.XXXXXX) || dur "gecici kurulum klasoru acilamadi"
tar -xf "$T/$D" -C "$Y" || dur "arsiv acilamadi"
[ -x "$Y/firefox/firefox" ] && grep -qx "Version=$V" "$Y/firefox/application.ini" || dur "acilan arsivde Firefox $V yok"
chown -R root:root "$Y/firefox"; chmod 755 "$Y/firefox"
rm -rf "$F.eski"
if [ -d "$F" ]; then mv "$F" "$F.eski" || dur "eski surum kenara alinamadi"; fi
if ! mv "$Y/firefox" "$F"; then [ -d "$F.eski" ] && mv "$F.eski" "$F"; dur "yeni surum yerine konamadi (eski surum geri alindi)"; fi
rm -rf "$F.eski"
echo; echo "  TAMAM: Firefox ${MEVCUT:-?} -> $V. Firefox'u acabilirsiniz."
FFG
chmod 755 $K/usr/bin/atasos-firefox-guncelle
cat > $K/usr/share/polkit-1/actions/org.atasos.firefox-guncelle.policy <<'POL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>atasOS</vendor>
  <action id="org.atasos.firefox-guncelle.run">
    <description>Update Firefox</description>
    <description xml:lang="tr">Firefox'u guncelle</description>
    <message>Authentication is required to update Firefox</message>
    <message xml:lang="tr">Firefox'u guncellemek icin parolaniz gerekiyor</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/atasos-firefox-guncelle</annotate>
  </action>
</policyconfig>
POL
cat > $K/usr/share/applications/atasos-firefox-guncelle.desktop <<'DSK'
[Desktop Entry]
Type=Application
Name=Firefox'u Güncelle
Name[en]=Update Firefox
Comment=Firefox'u Mozilla'nın en yeni sürümüne günceller
Comment[en]=Updates Firefox to Mozilla's latest release
Exec=konsole --hold -e /usr/bin/atasos-firefox-guncelle
Icon=firefox
Terminal=false
Categories=System;Network;
DSK
mkdir -p $K/etc/firefox/policies
[ -e $K/etc/firefox/policies/policies.json ] && { echo "HATA: $K/etc/firefox/policies/policies.json zaten var; elle birlestir"; exit 1; }
printf '{\n  "policies": {\n    "DisableAppUpdate": true\n  }\n}\n' > $K/etc/firefox/policies/policies.json
echo "  Firefox guncelleme: menu 'Firefox'u Guncelle' + /usr/bin/atasos-firefox-guncelle (imzali indirme), Firefox ici guncelleme kapali"
# v36: guncelleme kanali guven temeli
install -m 755 $KN/atspkg-0.3.0 $K/usr/bin/atspkg
install -d -m 755 $K/usr/share/atspkg
install -m 644 $KN/depo-anahtari.gpg $K/usr/share/atspkg/depo-anahtari.gpg
DB=$K/var/lib/atspkg/db/atspkg
[ -f $DB/PKGINFO ] || { echo "HATA: $DB/PKGINFO yok"; exit 1; }
sed -i -E "s/^version = .*/version = 0.3.0/; s/^builddate = .*/builddate = $(date -u '+%F %T') UTC (atasos-79)/" $DB/PKGINFO
printf 'usr/bin/atspkg\nusr/share/atspkg//\nusr/share/atspkg/depo-anahtari.gpg\nusr/share/doc/atspkg//\nusr/share/doc/atspkg/README.md\n' > $DB/files
( cd $K && sha256sum usr/bin/atspkg usr/share/atspkg/depo-anahtari.gpg usr/share/doc/atspkg/README.md ) > $DB/sums
rm -f $K/var/lib/atspkg/index $K/var/lib/atspkg/index.sig
echo "  guncelleme kanali: atspkg 0.3.0 + depo anahtari ${DFPR:0:16}... (imzasiz dizin reddedilir)"
# v36: GRUB menu suresi (kurulan sistem). 30_os-prober'dan sonra calisir; 00_header'in timeout'unu ezer.
cat > $K/etc/grub.d/31_atasos_menu_suresi <<'GRS'
#!/bin/sh
# atasOS: diskte baska isletim sistemi yoksa menu gizli (1 sn; Esc ile acilir), varsa 3 sn menu gosterilir.
if [ "${GRUB_DISABLE_OS_PROBER:-true}" = "false" ] && command -v os-prober >/dev/null 2>&1 && [ -n "$(os-prober 2>/dev/null)" ]; then
    echo "atasOS: baska isletim sistemi bulundu -> menu 3 sn" >&2
    printf 'set timeout_style=menu\nset timeout=3\n'
else
    echo "atasOS: baska isletim sistemi yok -> menu gizli (1 sn, Esc ile acilir)" >&2
    printf 'set timeout_style=hidden\nset timeout=1\n'
fi
GRS
chmod 755 $K/etc/grub.d/31_atasos_menu_suresi
echo "  GRUB menu suresi: tek sistemde gizli (Esc), cok sistemde 3 sn"

echo
echo "########## 3b  CALAMARES 3.3.14 + atasOS YAMASI (overlay icinde derlenir, ~15-30 dk) ##########"
CB=$K/tmp/cal; rm -rf $CB; mkdir -p $CB/src
for a in calamares-3.3.14.tar.gz kpmcore-25.04.3.tar.xz yaml-cpp-0.8.0.tar.gz; do tar -xf $CY/ar/$a -C $CB/src || { echo "HATA: $a acilamadi"; exit 1; }; done
patch -d $CB/src/calamares-3.3.14 -p1 --no-backup-if-mismatch < $CY/atasos-calamares-3.3.14.patch | sed 's/^/  /' || { echo "HATA: yama uygulanamadi"; exit 1; }
cat > $CB/derle.sh <<'DERLE'
#!/bin/bash
# atasos-77 bunu chroot icinde (/tmp/cal) calistirir. Sistemdeki hicbir dosyaya yazmaz:
#   yaml-cpp: yalniz basliklar /tmp/cal/onek/include'a (kutuphane sistemde var: libyaml-cpp.so.0.8;
#             0.8.0'in kaynagi GCC 15 ile derlenmiyor, basliklari sorunsuz)
#   kpmcore : /tmp/cal/onek'e (baslik + cmake; calisma aninda sistemdeki ayni surum libkpmcore.so.13 kullanilir)
#   Calamares (yamali): DESTDIR=/tmp/cal/kur
set -euo pipefail
J=$(nproc); P=/tmp/cal/onek; S=/tmp/cal/src
export CMAKE_BUILD_PARALLEL_LEVEL=$J LANG=C.UTF-8
echo "== yaml-cpp 0.8.0 basliklari"
mkdir -p $P/include
cp -r $S/yaml-cpp-0.8.0/include/yaml-cpp $P/include/
[ -f $P/include/yaml-cpp/yaml.h ]
echo "== kpmcore 25.04.3"
cmake -S $S/kpmcore-25.04.3 -B $S/kpmcore-25.04.3/b -DCMAKE_INSTALL_PREFIX=$P -DKDE_INSTALL_LIBDIR=lib64 \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF >/tmp/cal/kpmcore.log 2>&1
cmake --build $S/kpmcore-25.04.3/b >>/tmp/cal/kpmcore.log 2>&1
cmake --install $S/kpmcore-25.04.3/b >>/tmp/cal/kpmcore.log 2>&1
echo "== Calamares 3.3.14 + atasOS yamasi (yapilandirma)"
cmake -S $S/calamares-3.3.14 -B $S/calamares-3.3.14/b -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib64 \
      -DCMAKE_BUILD_TYPE=Release -DWITH_QT6=ON -DCMAKE_PREFIX_PATH=$P -DYAMLCPP_DIR=$P -DBUILD_TESTING=OFF \
      -DBUILD_SCHEMA_TESTING=OFF -DINSTALL_CONFIG=OFF -DINSTALL_POLKIT=OFF -DCMAKE_SKIP_INSTALL_RPATH=ON >/tmp/cal/calamares.log 2>&1
grep -E "YAMLCPP|KPMcore" /tmp/cal/calamares.log | grep -iE "found" | sed 's/^/   /' || true
echo "== Calamares derleniyor"
cmake --build $S/calamares-3.3.14/b >>/tmp/cal/calamares.log 2>&1
DESTDIR=/tmp/cal/kur cmake --install $S/calamares-3.3.14/b >>/tmp/cal/calamares.log 2>&1
echo "== derleme bitti"
DERLE
chmod 755 $CB/derle.sh
for m in dev dev/pts proc sys; do mkdir -p $K/$m; done
mount --bind /dev $K/dev; mount --bind /dev/pts $K/dev/pts; mount -t proc proc $K/proc; mount -t sysfs sysfs $K/sys
crk(){ chroot $K /usr/bin/env -i HOME=/tmp/cal TERM=${TERM:-dumb} LC_ALL=C PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }
B=$(date +%s)
crk /tmp/cal/derle.sh || { echo "HATA: derleme basarisiz. Son satirlar:"
    for l in kpmcore calamares; do [ -f $CB/$l.log ] && { echo "  --- $l.log"; grep -E "error|Error|not found|NOT find" $CB/$l.log | tail -n 15 | sed 's/^/    /'; tail -n 8 $CB/$l.log | sed 's/^/    /'; }; done
    echo "  Kayitlar: $U/tmp/cal/*.log (overlay ust katmani)"; exit 1; }
echo "  derleme: $(( ($(date +%s)-B) / 60 )) dk"
R=$CB/kur
for y in usr/bin/calamares usr/lib64/libcalamares.so.3.3.14 usr/lib64/libcalamaresui.so.3.3.14 usr/lib64/calamares/modules/partition/libcalamares_viewmodule_partition.so; do
    [ -f $R/$y ] || { echo "HATA: derlenen kurulumda /$y yok"; exit 1; }; done
{ strings -a -el $R/usr/lib64/libcalamaresui.so.3.3.14 | grep -c atasosEraseDisk >/dev/null; } && { strings -a -el $R/usr/lib64/calamares/modules/partition/libcalamares_viewmodule_partition.so | grep -c atasosEraseDisk >/dev/null; } \
    || { echo "HATA: yama derlenen kutuphanelerde yok"; exit 1; }
if readelf -d $R/usr/bin/calamares $R/usr/lib64/libcalamares*.so.3.3.14 $R/usr/lib64/calamares/modules/*/*.so 2>/dev/null | grep -E 'R(UN)?PATH' | grep -c /tmp/cal >/dev/null; then
    echo "HATA: derlenen dosyalarda /tmp/cal RPATH'i var"; exit 1; fi
ESKI=$(ls $K/usr/lib64/calamares/modules | sort); YENI=$(ls $R/usr/lib64/calamares/modules | sort)
EKSIK=$(comm -23 <(echo "$ESKI") <(echo "$YENI") | tr '\n' ' ')
echo "  moduller: eski $(echo "$ESKI" | wc -l), yeni $(echo "$YENI" | wc -l)${EKSIK:+; derlenmeyen (eskisi kalir): $EKSIK}"
# yalniz Calamares'in kendi dosyalari; /etc/calamares (atasOS ayarlari, marka) DOKUNULMAZ
cp -a $R/usr/bin/calamares $K/usr/bin/calamares
cp -a $R/usr/lib64/libcalamares*.so* $K/usr/lib64/
cp -a $R/usr/lib64/calamares/. $K/usr/lib64/calamares/
[ -d $R/usr/share/calamares/qml ] && cp -a $R/usr/share/calamares/qml/. $K/usr/share/calamares/qml/
EKS=$(crk sh -c 'ldd /usr/bin/calamares /usr/lib64/libcalamaresui.so.3.3 /usr/lib64/calamares/modules/*/*.so 2>/dev/null | grep "not found" | sort -u')
[ -z "$EKS" ] || { echo "HATA: eksik kutuphane:"; echo "$EKS" | sed 's/^/    /'; exit 1; }
V=$(crk sh -c 'QT_QPA_PLATFORM=offscreen calamares --version 2>&1' | grep -oE '3\.3\.14[^ ]*' | head -1)
echo "  kuruldu: Calamares ${V:-?} (yamali), eksik kutuphane yok"
umount $K/sys $K/proc $K/dev/pts $K/dev
rm -rf $CB

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
# ISO DOSYASINDAN ACILIS (USB'siz donanim testi): GRUB "atasos.iso=/yol/atasos-live.iso" verirse ISO'yu
# disk bolumlerinde arar ve loop ile baglar. Bolum SALT-OKUNUR baglanir; bu modda kurulum programi kapatilir.
ISOF=$(busybox sed -n 's/.*atasos\.iso=\([^ ]*\).*/\1/p' /proc/cmdline)
if [ -n "$ISOF" ]; then
  log "ISO dosyasi araniyor: $ISOF"
  busybox mkdir -p /mnt/host
  n=0
  while [ $n -lt 80 ] && [ -z "${MED:-}" ]; do
    for d in /dev/nvme[0-9]n[0-9]p[0-9]* /dev/sd[a-z][0-9]* /dev/vd[a-z][0-9]* /dev/mmcblk[0-9]p[0-9]*; do
      [ -b "$d" ] || continue
      busybox mount -o ro "$d" /mnt/host 2>/dev/null || continue
      if [ -f "/mnt/host$ISOF" ] && busybox mount -t iso9660 -o ro,loop "/mnt/host$ISOF" /mnt/medium 2>/dev/null; then
        if [ -f /mnt/medium/live/filesystem.squashfs ]; then MED="$d:$ISOF"; ISOMOD=1; break 2; fi
        busybox umount /mnt/medium 2>/dev/null
      fi
      busybox umount /mnt/host 2>/dev/null
    done
    n=$((n+1)); busybox sleep 0.25
  done
  [ -n "${MED:-}" ] || log "ISO dosyasi bulunamadi, USB/CD aranacak"
fi
# USB bellek / CD / sanal disk: 30 sn boyunca tum blok aygitlari dene (USB'nin taninmasi birkac saniye surer)
n=0
while [ -z "${MED:-}" ] && [ $n -lt 120 ]; do
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
if [ "${ISOMOD:-0}" = 1 ]; then
  busybox mkdir -p /newroot/run/live/host
  busybox mount --move /mnt/host /newroot/run/live/host 2>/dev/null
  # dahili diskin bir bolumu bagliyken kurulum guvenli degil -> bu modda kurulum programi yok
  busybox rm -f /newroot/home/eren/Desktop/atasos-kurulum.desktop /newroot/usr/share/applications/calamares.desktop
  for b in /newroot/usr/bin/atasos-kurulum /newroot/usr/bin/calamares; do
    printf '#!/bin/sh\necho "atasOS: ISO dosyasindan acildi; kurulum bu modda kapali. Kurmak icin ISO yu USB ye yazip oradan acin."\nexit 1\n' > $b
  done
  log "ISO dosyasindan acildi ($MED): kurulum kapali"
fi
log "systemd'ye geciliyor"
exec busybox switch_root /newroot /sbin/init
INIT
chmod 755 $IR/init
(cd $IR && find . | cpio -o -H newc -R 0:0 --quiet | gzip -9 > $O/agac/boot/initramfs.img) || { echo "HATA: initramfs"; exit 1; }
cp "$VMZ" $O/agac/boot/vmlinuz
echo "  initramfs: $(stat -c%s $O/agac/boot/initramfs.img) bayt, vmlinuz: $(stat -c%s $O/agac/boot/vmlinuz) bayt"
# canli ISO'nun GRUB'u da atasOS temasiyla (yazi tipleri tek tek: GRUB joker (*) acmaz)
mkdir -p $O/agac/boot/grub/themes; cp -r $K/usr/share/grub/themes/atasos $O/agac/boot/grub/themes/
cat > $O/agac/boot/grub/grub.cfg <<GCFG
set default=0
set timeout=10
insmod all_video
insmod gfxterm
insmod png
set gfxmode=auto
if loadfont unicode ; then terminal_output gfxterm ; fi
loadfont /boot/grub/themes/atasos/dejavu-16.pf2
loadfont /boot/grub/themes/atasos/dejavu-24.pf2
loadfont /boot/grub/themes/atasos/dejavu-bold-24.pf2
loadfont /boot/grub/themes/atasos/dejavu-bold-32.pf2
set theme=/boot/grub/themes/atasos/theme.txt
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
         etc/calamares/settings.conf etc/systemd/system/multi-user.target.wants/atasos-live-medium.service boot/vmlinuz-$KVER usr/lib/modules/$KVER usr/bin/plasmashell usr/bin/mksquashfs \
         usr/share/icons/hicolor/256x256/apps/atasos.png usr/share/icons/hicolor/scalable/apps/atasos.svg etc/calamares/branding/atasos/show.qml \
         usr/share/sddm/themes/atasOS/Main.qml usr/share/sddm/themes/atasOS/logo.png etc/sddm.conf.d/30-atasos-klavye.conf \
         etc/xdg/plasma-workspace/env/atasos-hidpi.sh etc/atasos/olcek \
         usr/share/wallpapers/atasOS/contents/images/1920x1080.jpg usr/share/grub/themes/atasos/theme.txt usr/share/grub/themes/atasos/dejavu-24.pf2 \
         usr/share/sddm/themes/atasOS/background.jpg etc/xdg/kdeglobals etc/xdg/plasmarc etc/X11/xorg.conf.d/30-atasos-dokunmatik.conf; do
    grep -qE "^squashfs-root/$y$" $O/icerik.txt && printf '  var : /%s\n' "$y" || { printf '  YOK : /%s <<<\n' "$y"; H=1; }
done
for y in 'etc/NetworkManager/system-connections/' 'etc/ssh/ssh_host_' 'home/eren/.mozilla' 'root/.' 'sources/' 'plasma-workspace/env/atasos-olcek'; do
    c=$(grep -cF "squashfs-root/$y" $O/icerik.txt); printf '  temiz (%s): %s\n' "$y" "$([ "$c" -eq 0 ] && echo evet || { H=1; echo "HAYIR, $c girdi <<<"; })"
done
grep -qE '^\s*initialPartitioningChoice:\s*none' $K/etc/calamares/modules/partition.conf && grep -qE '^\s*prompt-install:\s*true' $K/etc/calamares/settings.conf \
    && echo "  disk guvenligi: on-secim yok + son onay var" || { echo "  disk guvenligi: AYAR TUTMADI <<<"; H=1; }
grep -q '^ColorScheme=BreezeDark' $K/etc/xdg/kdeglobals && grep -q 'icon=atasos' $K/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc && echo "  masaustu: koyu tema + panel logosu (atasos-59)" || { echo "  masaustu ayarlari YOK (atasos-59 calismamis) <<<"; H=1; }
grep -q '^SessionDir=/usr/share/atasos/wayland-oturum-yok' $K/etc/sddm.conf.d/30-atasos-klavye.conf && echo "  giris ekrani: Wayland gizli, yalniz X11" || { echo "  Wayland gizleme YOK <<<"; H=1; }
grep -q 'x11Secildi' $K/usr/share/sddm/themes/atasOS/Main.qml && echo "  giris temasi: guncel (X11 varsayilan)" || { echo "  giris temasi eski <<<"; H=1; }
[ -f $O/agac/boot/grub/themes/atasos/theme.txt ] && echo "  ISO GRUB temasi: var" || { echo "  ISO GRUB temasi YOK <<<"; H=1; }
case "$KVER" in *atas[6-9]*) echo "  cekirdek: $KVER (AMD/NVIDIA)";; *) echo "  cekirdek $KVER: atas6 degil (AMD/NVIDIA yok) <<<"; H=1;; esac
grep -q 'InputPanel' $K/usr/share/sddm/themes/atasOS/Main.qml && echo "  SDDM temasi: ekran klavyesi var" || { echo "  SDDM temasi eski (atasos-56 calismamis) <<<"; H=1; }
grep -q 'rm -rf /etc/calamares' $K/usr/lib/atasos/kurulum-temizle.sh && echo "  kurulum-temizle: Calamares'i kaldiriyor" || { echo "  kurulum-temizle: Calamares kaldirma YOK <<<"; H=1; }
[ -z "$(find $K/usr/share/applications -maxdepth 1 -name '*.yedek-*')" ] && echo "  menu: .yedek dosyasi yok" || { echo "  menu: .yedek dosyasi var <<<"; H=1; }
grep -q '^Icon\[' $K/usr/share/applications/calamares.desktop && { echo "  calamares.desktop: Icon[xx] satiri kaldi <<<"; H=1; } || echo "  calamares.desktop: yalniz Icon=atasos"
grep -q '^sudoersGroup: wheel' $K/etc/calamares/modules/users.conf && echo "  sudo: kurulan kullanici (wheel) sudo kullanabilir" || { echo "  sudoersGroup YOK <<<"; H=1; }
[ -x $K/usr/bin/grub-mount ] && [ -x $K/usr/bin/os-prober ] && echo "  os-prober + grub-mount var" || { echo "  os-prober/grub-mount YOK <<<"; H=1; }
grep -qE '^[@#]includedir[[:space:]]+/etc/sudoers\.d' $K/etc/sudoers && echo "  sudoers: @includedir var" || { echo "  sudoers: @includedir YOK <<<"; H=1; }
# v34: bos sifre engeli + otomatik giris (displaymanager, shellprocess'ten hemen sonra)
grep -q '^allowWeakPasswords: false' $K/etc/calamares/modules/users.conf && grep -qE '^ +minLength: [1-9]' $K/etc/calamares/modules/users.conf \
    && ! grep -qE '^ +nonempty:' $K/etc/calamares/modules/users.conf \
    && echo "  users.conf: bos sifre engelli" || { echo "  bos sifre engeli YOK <<<"; H=1; }
grep -A1 -E '^\s*-\s*shellprocess\s*$' $K/etc/calamares/settings.conf | grep -qE '^\s*-\s*displaymanager\s*$' \
    && grep -q '^ *- sddm' $K/etc/calamares/modules/displaymanager.conf && [ -f $K/usr/share/xsessions/plasmax11.desktop ] \
    && echo "  otomatik giris: displaymanager adimi (sddm, plasmax11)" || { echo "  otomatik giris ayari YOK <<<"; H=1; }
# v33: Flatpak (atasos-65)
for y in usr/bin/flatpak usr/bin/bwrap usr/bin/xdg-dbus-proxy usr/bin/gpg usr/bin/ostree var/lib/flatpak/repo/config \
         etc/xdg/plasma-workspace/env/atasos-flatpak.sh etc/profile.d/flatpak.sh usr/share/polkit-1/rules.d/org.freedesktop.Flatpak.rules; do
    grep -qE "^squashfs-root/$y$" $O/icerik.txt && printf '  var : /%s\n' "$y" || { printf '  YOK : /%s <<<\n' "$y"; H=1; }
done
grep -q '^flatpak:' $K/etc/passwd && echo "  flatpak sistem kullanicisi var" || { echo "  flatpak kullanicisi YOK <<<"; H=1; }
grep -q 'flathub' $K/var/lib/flatpak/repo/config && echo "  Flathub deposu tanimli" || { echo "  Flathub deposu YOK <<<"; H=1; }
c=$(grep -cE '^squashfs-root/var/lib/flatpak/(app|runtime)/[^/]+$' $O/icerik.txt)
[ "$c" -eq 0 ] && echo "  flatpak: ISO'da kurulu uygulama/runtime yok (temiz)" || { echo "  flatpak: $c uygulama/runtime ISO'ya girdi (Steam vb. kurulmus) <<<"; H=1; }
# v35
grep -qE '^\s*installEFIFallback:\s*false' $K/etc/calamares/modules/bootloader.conf && grep -q 'EFI/BOOT/BOOTX64.EFI' $K/usr/lib/atasos/kurulum-temizle.sh \
    && echo "  EFI yedegi: Calamares yazmiyor, kurulum-temizle yalniz yoksa yaziyor" || { echo "  EFI yedegi ayari YOK <<<"; H=1; }
grep -q '^GRUB_DISABLE_LINUX_PARTUUID=false' $K/etc/default/grub && grep -q 'GRUB_DISABLE_LINUX_PARTUUID' $K/etc/grub.d/10_linux \
    && echo "  GRUB: root=PARTUUID" || { echo "  GRUB PARTUUID ayari YOK <<<"; H=1; }
grep -q '^squashfs-root/tcl-backup' $O/icerik.txt && { echo "  /tcl-backup ISO'ya girdi <<<"; H=1; } || echo "  /tcl-backup: yok"
# v36: yamali Calamares
{ strings -a -el $K/usr/lib64/libcalamaresui.so.3.3.14 | grep -c atasosEraseDisk >/dev/null; } && { strings -a -el $K/usr/lib64/calamares/modules/partition/libcalamares_viewmodule_partition.so | grep -c atasosEraseDisk >/dev/null; } \
    && echo "  Calamares: atasOS yamasi var (hizalama, cubuk alt siniri, Diski sil uyarisi)" || { echo "  Calamares yamasi YOK <<<"; H=1; }
grep -qE '^enableLuksAutomatedPartitioning: false$' $K/etc/calamares/modules/partition.conf \
    && [ "$(grep -cE '^\s*enableLuksAutomatedPartitioning:' $K/etc/calamares/modules/partition.conf)" = 1 ] \
    && echo "  sifreleme kutusu: kapali (otomatik + elle bolumleme)" || { echo "  sifreleme ayari YOK <<<"; H=1; }
grep -q '^squashfs-root/tmp/cal' $O/icerik.txt && { echo "  derleme dosyalari ISO'ya girdi <<<"; H=1; } || echo "  derleme dosyalari: yok"
grep -q '^ATSPKG_VERSION="0.3.0"' $K/usr/bin/atspkg && grep -q dizin_dogrula $K/usr/bin/atspkg && ! grep -qE 'curl -fskL|wget --no-check-certificate|_create_unverified_context' $K/usr/bin/atspkg \
    && cmp -s $K/usr/share/atspkg/depo-anahtari.gpg $KN/depo-anahtari.gpg && grep -q '^version = 0.3.0' $K/var/lib/atspkg/db/atspkg/PKGINFO \
    && echo "  atspkg 0.3.0: imzali dizin + TLS dogrulama + depo anahtari" || { echo "  atspkg 0.3.0 / depo anahtari YOK <<<"; H=1; }
[ -x $K/etc/grub.d/31_atasos_menu_suresi ] && grep -q '^GRUB_TIMEOUT=3' $K/etc/default/grub && echo "  GRUB menu suresi betigi var" || { echo "  GRUB menu suresi YOK <<<"; H=1; }
grep -qE '^squashfs-root/var/lib/atspkg/index' $O/icerik.txt && { echo "  eski paket dizini ISO'ya girdi <<<"; H=1; } || true
for y in usr/bin/atasos-firefox-guncelle usr/share/polkit-1/actions/org.atasos.firefox-guncelle.policy usr/share/applications/atasos-firefox-guncelle.desktop etc/firefox/policies/policies.json; do
    grep -qE "^squashfs-root/$y$" $O/icerik.txt && printf '  var : /%s\n' "$y" || { printf '  YOK : /%s <<<\n' "$y"; H=1; }
done
grep -q '14F26682D0916CDD81E37B6D61B7B526D98F0353' $K/usr/bin/atasos-firefox-guncelle && bash -n $K/usr/bin/atasos-firefox-guncelle \
    && echo "  Firefox guncelleyici: imza denetimi var, sozdizimi tamam" || { echo "  Firefox guncelleyici bozuk <<<"; H=1; }
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
echo "  Test: sanal NVMe (atasos-73) ya da USB. Kubuntu GRUB'una ISO girdisi eklenmedi (atasos-75 karari)."
echo "  YAYINDAN ONCE: depodaki atspkg.index imzalanip atspkg.index.sig yuklenmeli (yoksa v36'da 'atspkg guncelle' reddeder)."
