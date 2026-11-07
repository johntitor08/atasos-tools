#!/usr/bin/env bash
# GRUP C: ISO uretim araclari + Calamares kurulum programi, v20 squashfs'ten aktarilir.
#   squashfs-tools, xorriso, mtools, efivar/efibootmgr, GRUB (i386-pc + x86_64-efi modulleri, araclar, unicode.pf2),
#   Calamares 3.3.14 (+ /etc/calamares, atasOS branding), kpmcore 25.04.3, yaml-cpp, /etc/skel, atasos-live-medium,
#   atspkg, KWIN_FORCE_SW_CURSOR (v15).
# v28 duzeltmesi: Calamares /usr/bin/atasos-kurulum ile yazilim cizimiyle (QT_QUICK_BACKEND=software) baslar.
# KURAL: p5'teki hicbir dosyanin uzerine yazilmaz. TEK ISTISNA GRUB: p5'in GRUB araclari baska bir derlemeden ve
#   modulleri yok; v20'nin araclari+modulleri tutarli bir kume olarak yazilir, farkli olan p5 dosyalari once yedeklenir.
# Bilerek ALINMAYANLAR (yalniz canli ISO'ya ait, v29 ISO betigi ekler): live sudoers, sifresiz Calamares polkit
#   kurali, eren autologin, eski VM baslaticisi plasma-start.sh, XDG/PAM gecici cozumleri, systemd-networkd.
# Kullanim: sudo bash /home/eren/atasos-43-c-aktar.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
W=/home/eren/atas3-loglar/iso-inceleme
SQ=$W/filesystem.squashfs
R=/home/eren/atas3-loglar/c-aktarim
LST=/var/lib/atasos-paketler/c-v20.list
TS=$(date +%m%d-%H%M)
mkdir -p $A "$R"
[ -f "$SQ" ] && [ -s "$W/liste.txt" ] && [ -s "$W/baglar.tsv" ] || { echo "HATA: $SQ / liste.txt / baglar.tsv yok"; exit 1; }
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
           chown -R eren:eren "$R" 2>/dev/null; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
[ -e $A$LST ] && { echo "  C zaten aktarilmis ($LST var). Hicbir sey yapilmadi."; exit 0; }

DESEN='/(mksquashfs|unsquashfs|sqfstar|sqfscat)$|/(xorriso|xorrisofs|osirrox|xorrecord|xorriso-dd-target|xorriso-tcltk)$|^usr/bin/(mtools|mformat)$|^etc/mtools\.conf$|/(efivar|efibootmgr|efibootdump)$|libefivar|libefiboot|^usr/lib/grub/(i386-pc|x86_64-efi)/|^usr/(s)?bin/grub-|^usr/share/grub/|^etc/bash_completion\.d/grub$|^usr/bin/calamares$|libcalamares|^usr/lib64/calamares/|^usr/share/calamares/|^etc/calamares/|^usr/share/applications/calamares\.desktop$|/apps/calamares\.(svg|png)$|com\.github\.calamares\.calamares\.policy$|kpmcore|libyaml-cpp|^etc/skel/|^etc/systemd/system/(multi-user\.target\.wants/)?atasos-live-medium\.service$|^usr/bin/atspkg$|^etc/atspkg|^var/lib/atspkg|^usr/share/doc/atspkg|^etc/profile\.d/kwin-sw-cursor\.sh$|^etc/fonts/conf\.d/70-no-bitmaps-except-emoji\.conf$'
HARIC='^usr/share/(man|help|gtk-doc|info)/|\.la$|\.a$|^usr/share/locale/|^usr/include/|^usr/lib(64)?/cmake/|^usr/lib(64)?/pkgconfig/|^boot/|^opt/|^home/|^root/|^tmp/|^sources/|^var/run(/|$)|^var/lib/atspkg/kilit$'
CEVIRI='^usr/share/locale/tr/LC_MESSAGES/.*(calamares|kpmcore|xorriso|mtools|grub)'
# GRUB: p5'te olup farkli olan dosyalar da yazilir (yedekle)
GRUB_DEG='^usr/(s)?bin/grub-|^usr/share/grub/|^usr/lib/grub/'

echo "########## 1/7  SECIM ##########"
sed 's|^squashfs-root/||' "$W/liste.txt" | grep -E '^.' > "$R/v20.txt"
{ grep -E "$DESEN" "$R/v20.txt" | grep -vE "$HARIC"; grep -E "$CEVIRI" "$R/v20.txt"
  awk -F'\t' '$2=="mtools" && $1 ~ /^usr\/bin\//{print $1}' "$W/baglar.tsv"; } | sort -u > "$R/aday.txt"
p5de(){ [ -e "$A/$1" ] || [ -L "$A/$1" ]; }
: > "$R/liste.txt"; : > "$R/grub-ortak.txt"; ortak=0
while read -r f; do
    if ! p5de "$f"; then echo "$f" >> "$R/liste.txt"
    elif [[ "$f" =~ $GRUB_DEG ]] && [ -f "$A/$f" ] && [ ! -L "$A/$f" ]; then echo "$f" >> "$R/grub-ortak.txt"
    else ortak=$((ortak+1)); fi
done < "$R/aday.txt"
# GRUB: ortak dosyalardan icerigi FARKLI olanlari bul
TMPG=$(mktemp -d -p "$R")
: > "$R/grub-degisecek.txt"
if [ -s "$R/grub-ortak.txt" ]; then
    unsquashfs -q -f -d "$TMPG" -ef "$R/grub-ortak.txt" "$SQ" >/dev/null 2>&1
    while read -r f; do cmp -s "$TMPG/$f" "$A/$f" || echo "$f" >> "$R/grub-degisecek.txt"; done < "$R/grub-ortak.txt"
fi
rm -rf "$TMPG"
echo "  aday: $(wc -l < "$R/aday.txt")   p5'te ayni/korunan: $ortak   yeni: $(wc -l < "$R/liste.txt")   degisecek GRUB dosyasi: $(wc -l < "$R/grub-degisecek.txt")"

echo
echo "########## 2/7  BAGIMLILIK KAPANISI ##########"
p5_bulur(){ for d in usr/lib64 usr/lib lib64 usr/local/lib; do [ -e "$A/$d/$1" ] && return 0; done; return 1; }
TMP=$(mktemp -d -p "$R")
for tur in 1 2 3 4 5 6; do
    # degisecek GRUB araclarinin bagimliliklari da (grub-mkfont -> freetype, grub-mount -> fuse...)
    sort -u "$R/liste.txt" "$R/grub-degisecek.txt" > "$R/kapanis.txt"
    unsquashfs -q -f -d "$TMP" -ef "$R/kapanis.txt" "$SQ" >/dev/null 2>&1
    yeni=0
    for so in $(find "$TMP" -type f \( -path '*/bin/*' -o -name '*.so*' -o -path '*/libexec/*' \) -exec sh -c 'head -c4 "$1" | grep -q ELF && readelf -d "$1"' _ {} \; 2>/dev/null | grep NEEDED | grep -oE '\[[^]]+\]' | tr -d '[]' | sort -u); do
        p5_bulur "$so" && continue
        grep -qE "/$(printf '%s' "$so" | sed 's/[.+]/\\&/g')\$" "$R/liste.txt" && continue
        taban=${so%%.so*}
        esl=$(grep -E "^usr/lib(64)?/$(printf '%s' "$taban" | sed 's/[.+]/\\&/g')\.so[^/]*$" "$R/v20.txt" | grep -vE '\.la$')
        if [ -n "$esl" ]; then echo "$esl" >> "$R/liste.txt"; yeni=1; printf '  + %-30s (tur %s)\n' "$so" "$tur"
        else printf '  ! %-30s ne p5 ne v20 <<<\n' "$so"; fi
    done
    sort -u -o "$R/liste.txt" "$R/liste.txt"
    [ "$yeni" -eq 0 ] && break
done
rm -rf "$TMP"
awk -F'\t' '
  function hedef(p, t,   d, h) {
      if (t ~ /^\//) h = substr(t, 2)
      else { d = p; sub(/\/[^\/]*$/, "", d); h = d "/" t }
      while (match(h, /[^\/]+\/\.\.\//)) h = substr(h, 1, RSTART-1) substr(h, RSTART+RLENGTH)
      gsub(/\/\.\//, "/", h)
      return h
  }
  NR==FNR { var[$0]=1; next }
  { bag[$1]=$2 }
  END {
      do { deg=0; for (p in bag) if (p in var) { h=hedef(p, bag[p]); if (!(h in var)) { var[h]=1; deg=1 } } } while (deg)
      for (k in var) print k
  }' "$R/liste.txt" "$W/baglar.tsv" | sort -u > "$R/liste.yeni"
: > "$R/liste.txt"; while read -r f; do p5de "$f" || echo "$f" >> "$R/liste.txt"; done < "$R/liste.yeni"; rm -f "$R/liste.yeni"
KIRIK=$(awk -F'\t' '
  function hedef(p, t,   d, h) {
      if (t ~ /^\//) h = substr(t, 2)
      else { d = p; sub(/\/[^\/]*$/, "", d); h = d "/" t }
      while (match(h, /[^\/]+\/\.\.\//)) h = substr(h, 1, RSTART-1) substr(h, RSTART+RLENGTH)
      gsub(/\/\.\//, "/", h)
      return h
  }
  NR==FNR { var[$0]=1; next }
  ($1 in var) { print $1 "\t" hedef($1,$2) }' "$R/liste.txt" "$W/baglar.tsv" \
  | while IFS=$'\t' read -r b h; do grep -qxF "$h" "$R/liste.txt" || p5de "$h" || echo "  KIRIK BAG: $b -> $h"; done)
[ -z "$KIRIK" ] || { echo "$KIRIK"; echo "  DURDU: kirik bag olusacakti. Hicbir sey degistirilmedi."; exit 1; }
TEHLIKE=$(grep -E '/(ld-linux[^/]*|libc\.so[^/]*|libm\.so[^/]*|libstdc\+\+\.so[^/]*|libgcc_s\.so[^/]*|libz\.so[^/]*|libzstd\.so[^/]*|libffi\.so[^/]*|libglib-2[^/]*|libsystemd[^/]*|libudev[^/]*|libpython3[^/]*)$' "$R/liste.txt")
[ -z "$TEHLIKE" ] || { echo "  DURDU: temel kutuphaneler p5'te bulunamadi ve v20'den yazilacakti:"; echo "$TEHLIKE" | sed 's/^/    /'; echo "  Hicbir sey degistirilmedi."; exit 1; }
echo "  toplam yeni: $(wc -l < "$R/liste.txt")   degisecek GRUB: $(wc -l < "$R/grub-degisecek.txt")"
echo "  --- gruplar (yeni) ---"
for g in 'squashfs|sqfs' 'xorr|osirrox' '^usr/bin/m[a-z]+$|mtools' 'efivar|efiboot' '^usr/lib/grub/i386-pc/' '^usr/lib/grub/x86_64-efi/' 'grub-|share/grub' 'calamares' 'kpmcore' 'yaml-cpp' '^etc/skel' 'atasos-live-medium' 'atspkg'; do
    printf '    %-34s %5s\n' "$g" "$(grep -cE "$g" "$R/liste.txt")"; done
echo "  --- kapanistan gelen ek kutuphaneler ---"
grep -E '^usr/lib(64)?/lib[^/]+\.so\.[0-9.]+$' "$R/liste.txt" | grep -vE 'libcalamares|libkpmcore|libyaml-cpp|libefi' | sed 's/^/    /'
if [ -s "$R/grub-degisecek.txt" ]; then echo "  --- DEGISECEK p5 GRUB dosyalari (yedeklenecek) ---"; sed 's/^/    /' "$R/grub-degisecek.txt" | head -40; fi
read -r -p "  Aktarima devam edilsin mi? 'evet' yaz: " C
[ "$C" = "evet" ] || { echo "  Iptal. Hicbir sey degistirilmedi."; exit 0; }

echo
echo "########## 3/7  YEDEK + AKTARIM ##########"
Y=$A/var/lib/atasos-paketler/yedek-43-grub-$TS
if [ -s "$R/grub-degisecek.txt" ]; then
    mkdir -p "$Y"; (cd $A && tar -cf "$Y/grub-eski.tar" -T "$R/grub-degisecek.txt")
    echo "  $(wc -l < "$R/grub-degisecek.txt") GRUB dosyasi yedeklendi -> ${Y#$A}/grub-eski.tar"
fi
cat "$R/liste.txt" "$R/grub-degisecek.txt" | sort -u > "$R/yazilacak.txt"
unsquashfs -q -f -d "$A" -ef "$R/yazilacak.txt" "$SQ" >/dev/null 2>"$R/unsquashfs-hata.txt"
mkdir -p $A/var/lib/atasos-paketler; cp "$R/yazilacak.txt" $A$LST
eksik=0; while read -r f; do p5de "$f" || eksik=$((eksik+1)); done < "$R/yazilacak.txt"
echo "  yazildi: $(wc -l < "$R/yazilacak.txt") girdi, yazilamayan: $eksik, unsquashfs hata satiri: $(wc -l < "$R/unsquashfs-hata.txt")"

echo
echo "########## 4/7  v28 DUZELTMESI: Calamares yazilim cizimi ##########"
cat > $A/usr/bin/atasos-kurulum <<'EOF'
#!/bin/sh
# atasOS kurulum baslaticisi. v28 duzeltmesi: bazi GPU/surucu ikililerinde Calamares'in Qt Quick penceresi
# OpenGL baglami kuramiyor ("QRhiGles2: Failed to create temporary context") ve pencere hic acilmiyor.
# Kurulum ekrani basit oldugu icin yazilim cizimi her donanimda guvenli.
export QT_QUICK_BACKEND=software
exec /usr/bin/calamares "$@"
EOF
chmod 755 $A/usr/bin/atasos-kurulum
# pkexec ortam degiskenlerini siler; bu yuzden ayar .desktop'ta degil sarmalayicida. Yuklu sistemde sifre ister
# (auth_admin); canli ISO'da sifresiz calistirma kurali ISO betigiyle eklenir.
cat > $A/usr/share/polkit-1/actions/org.atasos.kurulum.policy <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>atasOS</vendor>
  <action id="org.atasos.kurulum.run">
    <description>Run the atasOS installer</description>
    <description xml:lang="tr">atasOS kurulum programini calistir</description>
    <message>Authentication is required to run the atasOS installer</message>
    <message xml:lang="tr">atasOS kurulum programini calistirmak icin kimlik dogrulamasi gerekiyor</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/atasos-kurulum</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
EOF
D=$A/usr/share/applications/calamares.desktop
if [ -f "$D" ]; then
    sed -i 's|^Exec=.*|Exec=sh -c "pkexec /usr/bin/atasos-kurulum \|\| sudo -n /usr/bin/atasos-kurulum"|' "$D"
    echo "  calamares.desktop: $(grep '^Exec=' "$D")"
fi
printf '%s\n' usr/bin/atasos-kurulum usr/share/polkit-1/actions/org.atasos.kurulum.policy >> $A$LST
echo "  /usr/bin/atasos-kurulum + org.atasos.kurulum.policy yazildi"

echo
echo "########## 5/7  CHROOT ISLERI ##########"
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin QT_QPA_PLATFORM=offscreen /bin/bash -uo pipefail -c "$1"; }
cr 'ldconfig
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor 2>/dev/null
    command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications
    # canli olmayan sistemde no-op (ISOIMAGE etiketi yoksa hemen cikar)
    systemctl is-enabled atasos-live-medium.service 2>/dev/null | sed "s/^/  atasos-live-medium: /"; true'

echo
echo "########## 6/7  DOGRULAMA ##########"
H=0
for f in usr/bin/mksquashfs usr/bin/unsquashfs usr/bin/xorriso usr/bin/mtools usr/bin/efibootmgr usr/bin/grub-mkfont usr/bin/grub-mkrescue usr/bin/grub-mkimage usr/sbin/grub-install \
         usr/bin/calamares usr/lib64/libcalamares.so.3.3 usr/lib64/libcalamaresui.so.3.3 usr/lib64/libkpmcore.so.13 usr/lib64/libexec/kpmcore_externalcommand usr/plugins/kpmcore/pmsfdiskbackendplugin.so; do
    [ -e "$A/$f" ] || { printf '  %-50s YOK <<<\n' "/$f"; H=1; continue; }
    e=$(chroot $A /usr/bin/ldd "/$f" 2>&1 | grep -c 'not found')
    printf '  %-50s %s\n' "/$f" "$([ "$e" -eq 0 ] && echo TAMAM || echo "$e EKSIK <<<")"
    [ "$e" -eq 0 ] || { H=1; chroot $A /usr/bin/ldd "/$f" | grep 'not found' | sort -u | sed 's/^/      /'; }
done
echo "  Calamares modul kutuphaneleri: $(find $A/usr/lib64/calamares/modules -name '*.so' 2>/dev/null | wc -l) adet, eksik bagimliligi olan:"
for so in $(find $A/usr/lib64/calamares/modules -name '*.so' 2>/dev/null); do
    chroot $A /usr/bin/ldd "${so#$A}" 2>&1 | grep -q 'not found' && { echo "    ${so#$A}"; H=1; }
done
echo "  GRUB modulleri: i386-pc $(ls $A/usr/lib/grub/i386-pc/*.mod 2>/dev/null | wc -l), x86_64-efi $(ls $A/usr/lib/grub/x86_64-efi/*.mod 2>/dev/null | wc -l), unicode.pf2 $(stat -c%s $A/usr/share/grub/unicode.pf2 2>/dev/null || echo YOK)"
echo "  --- surumler ---"
cr 'mksquashfs -version 2>&1 | head -1; xorriso -version 2>&1 | head -1; mtools --version 2>&1 | head -1; efibootmgr --version 2>&1 | head -1
    grub-mkrescue --version; grub-install --version; calamares --version 2>&1 | grep -iE "^calamares|3\.3" | head -1; atspkg surum 2>&1 | head -1' 2>&1 | sed 's/^/    /'
echo "  --- Calamares ayarlari ---"
ls $A/etc/calamares/modules/ | tr '\n' ' ' | sed 's/^/    /'; echo
grep -E '^\s*(sequence|- (show|exec)|  - )' $A/etc/calamares/settings.conf | head -30 | tr '\n' ' ' | sed 's/^/    /'; echo

echo
echo "########## 7/7  OZET ##########"
sync
[ $H -eq 0 ] && echo "  Tum parcalar tamam." || echo "  Bazi parcalarda eksik var (yukarida <<< ile isaretli)."
echo "  liste: $LST$( [ -s "$R/grub-degisecek.txt" ] && echo "   GRUB yedegi: ${Y#$A}/grub-eski.tar")"
echo "  Siradaki adim: v29 canli ISO betigi (atasos-44)."
