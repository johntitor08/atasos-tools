#!/usr/bin/env bash
# 1) v20 ISO'daki Mesa 24.3.4 (iris + LLVM 22) yiginini p5'e aktar. Ayni Mesa surumu, ayni glibc 2.42.
#    Eksik bagimliliklar (LLVM, SPIRV-Tools, libsensors, libelf...) ISO'dan kapanis ile bulunur.
#    Degisen her p5 dosyasi once yedeklenir; liste /var/lib/atasos-paketler/mesa-iso-24.3.4.list
# 2) Plasma baslaticisindaki VM ayarlarini (yazilim cizimi, kompozitor kapali) kapat.
# 3) Olcek %200 (3000x2000 panel) + son acilisin ag kaydini topla.
# Kullanim: sudo bash /home/eren/atasos-24-mesa-iris-aktar.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
W=/home/eren/atas3-loglar/iso-inceleme
SQ=$W/filesystem.squashfs
R=/home/eren/atas3-loglar/mesa-aktarim
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p $A "$R"
[ -f "$SQ" ] || { echo "HATA: $SQ yok"; exit 1; }
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev; do mountpoint -q $m && umount $m; done; chown -R eren:eren "$R"; umount $A 2>/dev/null; }
trap temizle EXIT
L=$W/liste.txt
[ -s "$L" ] || unsquashfs -l "$SQ" > "$L"

echo "########## 1/6  AKTARILACAK DOSYALAR (bagimlilik kapanisi) ##########"
iso_var(){ grep -qxF "squashfs-root/$1" "$L"; }
p5_bulur(){ for d in usr/lib64 usr/lib lib64 usr/local/lib opt/lib; do [ -e "$A/$d/$1" ] && return 0; done; return 1; }
grep -E 'squashfs-root/usr/lib(64)?/(libgallium[^/]*|libGL[^/]*|libEGL[^/]*|libGLX[^/]*|libgbm[^/]*|libglapi[^/]*|dri/[^/]+|gbm/[^/]+)$' "$L" \
    | sed 's|^squashfs-root/||' | sort -u > "$R/liste.txt"
TMP=$(mktemp -d -p "$R")
for tur in 1 2 3 4 5 6; do
    unsquashfs -q -f -d "$TMP" -ef "$R/liste.txt" "$SQ" >/dev/null 2>&1
    yeni=0
    for so in $(find "$TMP" -type f \( -name '*.so*' \) -exec readelf -d {} \; 2>/dev/null | grep NEEDED | grep -oE '\[[^]]+\]' | tr -d '[]' | sort -u); do
        p5_bulur "$so" && continue
        grep -qE "/$(printf '%s' "$so" | sed 's/[.+]/\\&/g')\$" "$R/liste.txt" && continue
        taban=${so%%.so*}
        esl=$(grep -E "squashfs-root/usr/lib(64)?/$(printf '%s' "$taban" | sed 's/[.+]/\\&/g')\.so[^/]*$" "$L" | sed 's|^squashfs-root/||')
        if [ -n "$esl" ]; then echo "$esl" >> "$R/liste.txt"; yeni=1; printf '  + %-28s (tur %s)\n' "$so" "$tur"
        else printf '  ! %-28s ne p5 ne ISO <<<\n' "$so"; fi
    done
    sort -u -o "$R/liste.txt" "$R/liste.txt"
    [ "$yeni" -eq 0 ] && break
done
rm -rf "$TMP"
# Rust'in kendi LLVM kopyasi Mesa icin gereksiz (~200 MB)
sed -i '/-rust-/d' "$R/liste.txt"
# Baglarin HEDEFLERINI de ekle (ornek: libelf.so.1 -> libelf-0.193.so), yoksa kirik bag aktarilir
[ -s "$W/baglar.tsv" ] || unsquashfs -lls "$SQ" 2>/dev/null \
    | awk '$1 ~ /^l/ {p=$(NF-2); t=$NF; sub(/^squashfs-root\//,"",p); print p "\t" t}' > "$W/baglar.tsv"
# tek awk gecisi: listedeki her bagin hedefini (../ cozulerek) ekle, degisiklik bitene kadar tekrarla
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
  }' "$R/liste.txt" "$W/baglar.tsv" | sort -u > "$R/liste.yeni" && mv "$R/liste.yeni" "$R/liste.txt"
echo "  toplam: $(wc -l < "$R/liste.txt") dosya/bag"
# kirik bag kontrolu: listedeki bir bagin hedefi ISO'da gercekten var mi
awk '{sub(/^squashfs-root\//,""); print}' "$L" > "$R/iso-yollar.txt"
KIRIK=$(awk -F'\t' '
  function hedef(p, t,   d, h) {
      if (t ~ /^\//) h = substr(t, 2)
      else { d = p; sub(/\/[^\/]*$/, "", d); h = d "/" t }
      while (match(h, /[^\/]+\/\.\.\//)) h = substr(h, 1, RSTART-1) substr(h, RSTART+RLENGTH)
      return h
  }
  FILENAME==ARGV[1] { var[$0]=1; next }
  FILENAME==ARGV[2] { iso[$0]=1; next }
  ($1 in var) { h=hedef($1,$2); if (!(h in var) || !(h in iso)) print "  KIRIK BAG: " $1 " -> " $2 }
' "$R/liste.txt" "$R/iso-yollar.txt" "$W/baglar.tsv")
[ -z "$KIRIK" ] || { echo "$KIRIK"; echo "  DURDU: kirik bag olusacakti. Hicbir sey degistirilmedi."; exit 1; }
# KORUMA: temel sistem kutuphaneleri ASLA ISO'dan yazilmaz. Listeye girdilerse p5'te
# bulunamamis demektir -> beklenmedik durum, dur.
TEHLIKE=$(grep -E '/(ld-linux[^/]*|libc\.so[^/]*|libm\.so[^/]*|libdl\.so[^/]*|libpthread\.so[^/]*|librt\.so[^/]*|libstdc\+\+\.so[^/]*|libgcc_s\.so[^/]*|libz\.so[^/]*|libzstd\.so[^/]*|libffi\.so[^/]*|libxml2\.so[^/]*|libexpat\.so[^/]*|libX11[^/]*|libxcb[^/]*|libdrm\.so[^/]*)$' "$R/liste.txt")
if [ -n "$TEHLIKE" ]; then
    echo "  DURDU: su temel kutuphaneler p5'te bulunamadi ve ISO'dan yazilacakti:"
    echo "$TEHLIKE" | sed 's/^/    /'
    echo "  Hicbir sey degistirilmedi."
    exit 1
fi
echo "  --- p5'e EKLENECEK / DEGISECEK Mesa disi kutuphaneler ---"
grep -vE '/(libgallium|libGL|libEGL|libGLX|libgbm|libglapi)[^/]*$|/dri/|/gbm/' "$R/liste.txt" | sed 's/^/    /'
read -r -p "  Aktarima devam edilsin mi? 'evet' yaz: " C
[ "$C" = "evet" ] || { echo "  Iptal. Hicbir sey degistirilmedi."; exit 0; }

echo
echo "########## 2/6  YEDEK (p5'te degisecek olanlar) ##########"
Y=$A/var/lib/atasos-paketler/yedek-mesa-$TS
mkdir -p "$Y"
n=0; while read -r f; do [ -e "$A/$f" ] || [ -L "$A/$f" ] || continue; cp -a --parents "$A/$f" "$Y/" 2>/dev/null && n=$((n+1)); done < "$R/liste.txt"
echo "  $n dosya yedeklendi -> ${Y#$A}"

echo
echo "########## 3/6  AKTARIM ##########"
unsquashfs -q -f -d "$A" -ef "$R/liste.txt" "$SQ" >/dev/null 2>"$R/unsquashfs-hata.txt"
cp "$R/liste.txt" $A/var/lib/atasos-paketler/mesa-iso-24.3.4.list
mount --bind /dev $A/dev; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
chroot $A /sbin/ldconfig
echo "  aktarildi, ldconfig calisti. hata satiri: $(wc -l < "$R/unsquashfs-hata.txt")"

echo
echo "########## 4/6  DOGRULAMA (ldd, atasOS'un kendi kutuphaneleriyle) ##########"
D=0
for f in usr/lib64/dri/iris_dri.so usr/lib64/libgallium-24.3.4.so usr/lib64/libEGL.so.1 usr/lib64/libGLX_mesa.so.0 usr/lib64/libGL.so.1 usr/lib64/libgbm.so.1; do
    [ -e "$A/$f" ] || continue
    e=$(chroot $A /usr/bin/ldd "/$f" 2>&1 | grep -c 'not found')
    printf '  %-36s %s\n' "/$f" "$([ "$e" -eq 0 ] && echo TAMAM || echo "$e EKSIK <<<")"
    [ "$e" -eq 0 ] || { D=1; chroot $A /usr/bin/ldd "/$f" | grep 'not found' | sed 's/^/      /'; }
done
echo "  iris surucusu: $(ls $A/usr/lib64/dri/iris_dri.so 2>/dev/null || echo YOK)"

echo
echo "########## 5/6  PLASMA BASLATICI + OLCEK ##########"
P=$A/home/eren/.bash_profile.vm-plasma
cp -p "$P" "$P.yedek-$TS"
sed -i -E '/LIBGL_ALWAYS_SOFTWARE=1|KWIN_COMPOSE=N/ s/^([[:space:]]*)(export )/\1# \2/' "$P"
echo "  kapatilan VM ayarlari:"; grep -nE 'LIBGL_ALWAYS_SOFTWARE|KWIN_COMPOSE' "$P" | sed 's/^/    /'
C=$A/home/eren/.config; mkdir -p "$C"
for f in kdeglobals kcmfonts; do [ -f "$C/$f" ] && cp -p "$C/$f" "$C/$f.yedek-$TS"; done
ayarla(){ # dosya grup anahtar deger
    local f=$1 g=$2 k=$3 v=$4
    touch "$f"
    if ! grep -q "^\[$g\]" "$f"; then printf '\n[%s]\n%s=%s\n' "$g" "$k" "$v" >> "$f"
    elif awk -v g="[$g]" -v k="$k" '$0==g{s=1;next} /^\[/{s=0} s && index($0,k"=")==1{f=1} END{exit !f}' "$f"; then
        awk -v g="[$g]" -v k="$k" -v v="$v" '$0==g{s=1;print;next} /^\[/{s=0} s && index($0,k"=")==1{print k"="v;next} {print}' "$f" > "$f.t" && mv "$f.t" "$f"
    else sed -i "/^\[$g\]/a $k=$v" "$f"; fi
}
ayarla "$C/kdeglobals" KScreen ScaleFactor 2
ayarla "$C/kdeglobals" KScreen ScreenScaleFactors "eDP-1=2;"
ayarla "$C/kcmfonts"   General forceFontDPI 192
chown -R 1001:1001 "$C" "$P"
echo "  olcek: %200 (ScaleFactor=2, Xft.dpi=192) -> ~/.config/kdeglobals, kcmfonts"

echo
echo "########## 6/6  INTERNET: son acilisin kaydi ##########"
J=$A/var/log/journal
{
  journalctl -D "$J" -b 0 --no-pager -k | grep -m1 'Linux version'
  echo "--- iwlwifi / wlan ---"
  journalctl -D "$J" -b 0 --no-pager -k | grep -iE 'iwlwifi|wlp|wlan|rfkill|cfg80211|regulatory' | head -30
  echo "--- NetworkManager ---"
  journalctl -D "$J" -b 0 --no-pager -u NetworkManager | grep -viE 'dhcp.*option' | head -80
  echo "--- wpa_supplicant / iwd ---"
  journalctl -D "$J" -b 0 --no-pager | grep -iE 'wpa_supplicant|iwd\[' | head -20
  echo "--- polkit ---"
  journalctl -D "$J" -b 0 --no-pager | grep -iE 'polkit' | head -10
} > "$R/ag-kaydi.txt" 2>&1
echo "  $(wc -l < "$R/ag-kaydi.txt") satir -> $R/ag-kaydi.txt"
echo "  wpa_supplicant ikilisi: $(ls $A/usr/sbin/wpa_supplicant $A/usr/bin/wpa_supplicant 2>/dev/null | head -1 | sed "s|$A||" || echo YOK)"

sync
echo
if [ "$D" -eq 0 ]; then
    echo "  TAMAM. atas3'te masaustunu baslat:  bash ~/.bash_profile.vm-plasma"
    echo "  Bilgi Merkezi > Grafik Isleyicisi satirinda 'Mesa Intel(R) UHD Graphics' gormeliyiz."
else
    echo "  Eksik kutuphane var <<< Geri almak icin yedek: ${Y#$A}"
fi
