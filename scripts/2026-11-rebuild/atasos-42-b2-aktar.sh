#!/usr/bin/env bash
# GRUP B2: v20 ISO'da olup p5'te olmayan masaustu/sistem parcalari, v20 squashfs'ten aktarilir.
#   udisks2 (+ libblockdev crypto/dm/lvm/btrfs/mpath eklentileri), cryptsetup, lvm2/devmapper, keyutils araclari,
#   Xwayland, alsa-utils, PipeWire oynat/kaydet araclari (pw-play/pw-record...) + ALSA->PipeWire eklentisi,
#   Kate + KWrite (+ eklentiler, Turkce ceviriler).
# v20 ile p5'in ortak kutuphane surumleri birebir ayni (KF6 6.13.0, Qt 6.8.1, libblockdev 3, PipeWire 1.2.7,
# glib 2.82.4, systemd 257, alsa-lib). SADECE p5'te OLMAYAN dosyalar yazilir: mevcut hicbir dosyanin uzerine yazilmaz.
# Ayrica: fontinst / kcmclock / ksysguard / katetextbuffer icin eksik polkit politikalari uretilir.
# Kullanim: sudo bash /home/eren/atasos-42-b2-aktar.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir. Hicbir sey yapilmadi."; exit 1; }
A=/mnt/atasos
W=/home/eren/atas3-loglar/iso-inceleme
SQ=$W/filesystem.squashfs
R=/home/eren/atas3-loglar/b2-aktarim
AK=/home/eren/atas3-loglar/indirme/kauth-actions
LST=/var/lib/atasos-paketler/b2-v20.list
mkdir -p $A "$R"
[ -f "$SQ" ] && [ -s "$W/liste.txt" ] && [ -s "$W/baglar.tsv" ] || { echo "HATA: $SQ / liste.txt / baglar.tsv yok"; exit 1; }
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir. Hicbir sey yapilmadi."; exit 1; }
mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount $m; done
           chown -R eren:eren "$R" 2>/dev/null; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
[ -e $A$LST ] && { echo "  B2 zaten aktarilmis ($LST var). Hicbir sey yapilmadi."; exit 0; }

DESEN='(^|/)(lib)?cryptsetup|veritysetup|integritysetup|(^|/)libdevmapper|devmapper\.pc|dmsetup|(^|/)lvm|liblvm2|/(lv|vg|pv)[a-z]+$|dm-event|dmeventd|/1[0-3]-dm-|/(11|69)-dm-lvm|/95-dm-notify|libbd_|/libblockdev|udisks|UDisks2|/Xwayland$|xwayland\.pc|/alsa-(restore|state)\.service|sound\.target\.wants|90-alsa-restore|90-pipewire-alsa|libasound_module_(pcm|ctl)_pipewire|alsa\.conf\.d/(50|99)-pipewire|^usr/share/alsa/init|^usr/share/sounds/alsa|alsa-topology|/(aconnect|alsaloop|alsamixer|alsatplg|alsaucm|amixer|aplay|aplaymidi2?|arecord|arecordmidi2?|aseqdump|aseqnet|iecset|speaker-test|alsactl|alsa-info\.sh|alsabat|axfer|nhlt-dmic-info)$|/pw-(cat|play|record|midiplay|midirecord|dsdplay|encplay)$|kate|kwrite|/ktexteditor/|keyctl|request-key|^etc/keyutils'
# var/run -> /run bagi (yazmak Kubuntu'nun /run'ina yazmak olur), v20'nin cekirdek dokumu, kpmcore (grup C),
# lvm-dbus (lvmdbusd yok; libblockdev'i LVM icin onu kullanmaya zorlar)
HARIC='^usr/share/(doc|man|help|gtk-doc|info)/|\.la$|\.a$|^usr/share/locale/|^usr/lib/grub/|^opt/|^home/|^root/|^tmp/|^sources/|katex|^var/run(/|$)|^var/lib/systemd/|^usr/include/kpmcore|lvm-dbus'
CEVIRI='^usr/share/locale/tr/LC_MESSAGES/.*(kate|kwrite|ktexteditor_|udisks|cryptsetup|lvm2|alsa-utils)'

echo "########## 1/6  SECIM ##########"
sed 's|^squashfs-root/||' "$W/liste.txt" | grep -E '^.' > "$R/v20.txt"
{ grep -E "$DESEN" "$R/v20.txt" | grep -vE "$HARIC"; grep -E "$CEVIRI" "$R/v20.txt"; } | sort -u > "$R/aday.txt"
p5de(){ [ -e "$A/$1" ] || [ -L "$A/$1" ]; }
: > "$R/liste.txt"; ortak=0
while read -r f; do if p5de "$f"; then ortak=$((ortak+1)); else echo "$f" >> "$R/liste.txt"; fi; done < "$R/aday.txt"
echo "  aday: $(wc -l < "$R/aday.txt")   p5'te zaten var (dokunulmaz): $ortak   aktarilacak: $(wc -l < "$R/liste.txt")"

echo
echo "########## 2/6  BAGIMLILIK KAPANISI ##########"
p5_bulur(){ for d in usr/lib64 usr/lib lib64 usr/local/lib opt/lib; do [ -e "$A/$d/$1" ] && return 0; done; return 1; }
TMP=$(mktemp -d -p "$R")
for tur in 1 2 3 4 5 6; do
    unsquashfs -q -f -d "$TMP" -ef "$R/liste.txt" "$SQ" >/dev/null 2>&1
    yeni=0
    for so in $(find "$TMP" -type f -exec sh -c 'head -c4 "$1" | grep -q ELF && readelf -d "$1"' _ {} \; 2>/dev/null | grep NEEDED | grep -oE '\[[^]]+\]' | tr -d '[]' | sort -u); do
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
# baglarin hedeflerini ekle (yoksa kirik bag aktarilir)
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
# kapanis p5'te zaten olan bir hedef eklediyse onu cikar (uzerine yazma yok)
: > "$R/liste.txt"; while read -r f; do p5de "$f" || echo "$f" >> "$R/liste.txt"; done < "$R/liste.yeni"; rm -f "$R/liste.yeni"
# kirik bag kontrolu: bag hedefi ne listede ne p5'te ise dur
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
TEHLIKE=$(grep -E '/(ld-linux[^/]*|libc\.so[^/]*|libm\.so[^/]*|libstdc\+\+\.so[^/]*|libgcc_s\.so[^/]*|libz\.so[^/]*|libzstd\.so[^/]*|libffi\.so[^/]*|libxml2\.so[^/]*|libexpat\.so[^/]*|libX11[^/]*|libxcb[^/]*|libdrm\.so[^/]*|libglib-2[^/]*|libQt6[^/]*|libKF6[^/]*|libsystemd[^/]*|libudev[^/]*)$' "$R/liste.txt")
[ -z "$TEHLIKE" ] || { echo "  DURDU: temel kutuphaneler p5'te bulunamadi ve v20'den yazilacakti:"; echo "$TEHLIKE" | sed 's/^/    /'; echo "  Hicbir sey degistirilmedi."; exit 1; }
echo "  toplam aktarilacak: $(wc -l < "$R/liste.txt") dosya/bag/dizin"
echo "  --- gruplar ---"
for g in 'udisks|UDisks2' 'libbd_' 'cryptsetup|veritysetup|integritysetup' 'lvm|devmapper|dmsetup|dm-|/(lv|vg|pv)[a-z]+$' 'keyctl|request-key|keyutils' 'Xwayland|xwayland' 'alsa|/a(play|record|mixer|connect|seq)|speaker-test|iecset|sounds/' 'pw-' 'kate|kwrite|ktexteditor'; do
    printf '    %-62s %4s\n' "$g" "$(grep -cE "$g" "$R/liste.txt")"; done
echo "  --- kapanistan gelen ek kutuphaneler ---"
grep -E '^usr/lib(64)?/lib[^/]+\.so\.[0-9.]+$' "$R/liste.txt" | grep -vE 'libbd_|libcryptsetup|libdevmapper|liblvm2|libudisks|libkateprivate' | sed 's/^/    /'
read -r -p "  Aktarima devam edilsin mi? 'evet' yaz: " C
[ "$C" = "evet" ] || { echo "  Iptal. Hicbir sey degistirilmedi."; exit 0; }

echo
echo "########## 3/6  AKTARIM ##########"
unsquashfs -q -f -d "$A" -ef "$R/liste.txt" "$SQ" >/dev/null 2>"$R/unsquashfs-hata.txt"
mkdir -p $A/var/lib/atasos-paketler $A/var/lib/alsa
cp "$R/liste.txt" $A$LST
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin QT_QPA_PLATFORM=offscreen /bin/bash -uo pipefail -c "$1"; }
cr 'ldconfig; command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf /usr/share/icons/hicolor; command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications; true'
eksik=0; while read -r f; do p5de "$f" || eksik=$((eksik+1)); done < "$R/liste.txt"
echo "  aktarildi: $(wc -l < "$R/liste.txt") girdi, yazilamayan: $eksik, unsquashfs hata satiri: $(wc -l < "$R/unsquashfs-hata.txt")"
echo "  liste: $LST"

echo
echo "########## 4/6  POLKIT POLITIKALARI (fontinst, kcmclock, ksysguard, katetextbuffer) ##########"
if (cd "$AK" && sha256sum -c --quiet - <<'EOF'
796350894d02a424886a7d5aa236177b4155de2e8d311cc3ab78499512711326  fontinst.actions
b7f6ab6cf1e1b0cf83bb47ae35c0ae1885e596e505621c766d70e18b66d9e8d9  kcmclock_actions.actions
1d076a3230aab1002bd0ce2172942975bd1ef844eb6406bb498665e4821842c8  ksysguard-processlisthelper.actions
6409f5b5e3982178abbc714be5d533c73cd8b6eaf644ce7b9a96196ddedb5ba7  org.kde.ktexteditor6.katetextbuffer.actions
EOF
); then
    rm -rf $A/tmp/b2-actions; mkdir -p $A/tmp/b2-actions; cp "$AK"/*.actions $A/tmp/b2-actions/
    cr 'GEN=$(find /usr/lib64/libexec /usr/libexec /usr/lib/libexec -name kauth-policy-gen -type f 2>/dev/null | head -1 || true)
        [ -n "$GEN" ] || { echo "  kauth-policy-gen yok (once atasos-41)"; exit 0; }
        for a in /tmp/b2-actions/*.actions; do
            ilk=$(grep -m1 -E "^\[[a-z0-9._-]+\]$" "$a" | tr -d "[]" || true); id=${ilk%.*}
            p=/usr/share/polkit-1/actions/$id.policy
            [ -e /usr/share/dbus-1/system-services/$id.service ] || { echo "  atlandi (yardimci kurulu degil): $id"; continue; }
            [ -e "$p" ] && { echo "  zaten var: $id.policy"; continue; }
            if "$GEN" "$a" "$p" 2>/dev/null && [ -s "$p" ]; then echo "  URETILDI: $id.policy ($(grep -c "<action " "$p") eylem)"; echo "$p" >> /var/lib/atasos-paketler/kauth-politika.list
            else echo "  URETILEMEDI: $id"; rm -f "$p"; fi
        done; rm -rf /tmp/b2-actions'
else
    echo "  actions dosyalari dogrulanamadi ($AK) - atlandi"
fi

echo
echo "########## 5/6  DOGRULAMA ##########"
D=0
for f in usr/libexec/udisks2/udisksd usr/bin/udisksctl usr/lib/libbd_crypto.so.3 usr/sbin/cryptsetup usr/sbin/lvm usr/sbin/dmsetup usr/bin/keyctl \
         usr/bin/Xwayland usr/bin/aplay usr/bin/alsamixer usr/sbin/alsactl usr/bin/pw-cat usr/lib64/alsa-lib/libasound_module_pcm_pipewire.so usr/bin/kate usr/bin/kwrite; do
    [ -e "$A/$f" ] || { printf '  %-52s YOK <<<\n' "/$f"; D=1; continue; }
    e=$(chroot $A /usr/bin/ldd "/$f" 2>&1 | grep -c 'not found')
    printf '  %-52s %s\n' "/$f" "$([ "$e" -eq 0 ] && echo TAMAM || echo "$e EKSIK <<<")"
    [ "$e" -eq 0 ] || { D=1; chroot $A /usr/bin/ldd "/$f" | grep 'not found' | sort -u | sed 's/^/      /'; }
done
echo "  --- surumler ---"
cr 'cryptsetup --version; lvm version 2>/dev/null | head -1; aplay --version; pw-cat --version 2>&1 | head -2 | tail -1; Xwayland -version 2>&1 | grep -m1 -i "version"; udisksctl help >/dev/null 2>&1 && echo "udisksctl calisiyor"; kate --version 2>/dev/null; kwrite --version 2>/dev/null' 2>&1 | sed 's/^/    /'
echo "  --- servisler ---"
for u in etc/systemd/system/graphical.target.wants/udisks2.service usr/lib/systemd/system/sound.target.wants/alsa-restore.service usr/lib/systemd/system/sound.target.wants/alsa-state.service; do
    printf '    %-70s %s\n' "/$u" "$( [ -e "$A/$u" ] && echo etkin || echo YOK)"; done

echo
echo "########## 6/6  OZET ##########"
sync
[ $D -eq 0 ] && echo "  Tum parcalar tamam." || echo "  Bazi parcalarda eksik var (yukarida <<< ile isaretli)."
echo "  atasOS'u ac (GRUB 3. satir): Dolphin'de USB/diskler gorunmeli (udisks2), uygulama menusunde Kate/KWrite olmali,"
echo "  'aplay -l' ses kartini gostermeli, Wayland oturumunda X uygulamalari (Xwayland) acilmali."
