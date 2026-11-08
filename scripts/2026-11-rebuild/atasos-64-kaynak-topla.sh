#!/usr/bin/env bash
# atasOS v32 kaynak paketi: p5'teki (SALT OKUNUR baglanir) kaynak arsivlerini, yamalari, atas6 cekirdek
# ayarini ve kurulu sistemin surum listesini /veri/atasos-kaynak/ altina toplar. p5'te HICBIR SEY degismez.
# Kullanim: sudo bash /home/eren/atasos-64-kaynak-topla.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock; flock -n 9 || { echo "baska bir atasOS betigi calisiyor"; exit 1; }

H=/veri/atasos-kaynak
M=$(mktemp -d /run/atasos-ro.XXXX)
trap 'cd /; umount "$M" 2>/dev/null; rmdir "$M" 2>/dev/null; chown -R 1000:1000 "$H" 2>/dev/null' EXIT
mount -o ro /dev/nvme0n1p5 "$M" || { echo "HATA: p5 baglanamadi"; exit 1; }
S=$M/sources
mkdir -p "$H/arsivler" "$H/cekirdek"

echo "########## 1/4  KAYNAK ARSIVLERI ##########"
# Ust duzey + atasos-A/B + gtk-zinciri. Acilmis kaynak agaclarinin icindeki test arsivleri alinmaz.
# Ayni ad iki yerde varsa bir kez alinir; 'x.1' gibi wget tekrar kopyalari atlanir.
n=0
while IFS= read -r -d '' f; do
    b=$(basename "$f")
    case "$b" in *.[0-9]) continue ;; esac
    [ -e "$H/arsivler/$b" ] && continue
    cp --preserve=timestamps "$f" "$H/arsivler/$b" && n=$((n+1))
done < <(find "$S" -maxdepth 1 -type f \( -name '*.tar.*' -o -name '*.tgz' -o -name '*.patch' -o -name '*.zip' \) -print0
         find "$S/atasos-A" "$S/atasos-B" "$S/gtk-zinciri" -maxdepth 1 -type f \( -name '*.tar.*' -o -name '*.tgz' -o -name '*.patch' -o -name '*.zip' \) -print0 2>/dev/null)
echo "  $n dosya, $(du -sh "$H/arsivler" | cut -f1)"

echo "########## 2/4  CEKIRDEK ##########"
cp "$M/boot/config-6.16.1-atas6" "$H/cekirdek/config-6.16.1-atas6"
[ -f "$H/arsivler/linux-6.16.1.tar.xz" ] && echo "  linux-6.16.1.tar.xz + config-6.16.1-atas6" || echo "  UYARI: linux-6.16.1.tar.xz yok"
# Kaynak agacinda tarball'a gore degisen dosya var mi? (yama uygulanmis mi)
if [ -d "$S/linux-6.16.1" ]; then
    T=$(mktemp -d /veri/atasos-kaynak-gecici.XXXX); tar -xf "$S/linux-6.16.1.tar.xz" -C "$T"
    diff -rq "$T/linux-6.16.1" "$S/linux-6.16.1" 2>/dev/null | grep -v -E '^Only in '"$S"'/linux-6.16.1' > "$H/cekirdek/agac-farki.txt"
    rm -rf "$T"
    echo "  kaynak agaci farki: $(wc -l < "$H/cekirdek/agac-farki.txt") satir (0 = yamasiz)"
fi

echo "########## 3/4  SURUM LISTESI ##########"
L=$H/surumler
mkdir -p "$L"
# pkg-config: Name + Version
find "$M/usr/lib/pkgconfig" "$M/usr/share/pkgconfig" "$M/usr/lib64/pkgconfig" -name '*.pc' 2>/dev/null | sort | while read -r pc; do
    v=$(awk -F': *' '$1=="Version"{print $2; exit}' "$pc"); printf '%s\t%s\n' "$(basename "$pc" .pc)" "$v"
done > "$L/pkgconfig.tsv"
# CMake paketleri (KF6, Plasma, Qt6 modulleri ...)
find "$M/usr/lib/cmake" "$M/usr/lib64/cmake" "$M/usr/share/cmake" -name '*ConfigVersion.cmake' 2>/dev/null | sort | while read -r c; do
    v=$(grep -m1 -oE 'PACKAGE_VERSION "[^"]+"' "$c" | cut -d'"' -f2); printf '%s\t%s\n' "$(basename "$(dirname "$c")")" "$v"
done > "$L/cmake.tsv"
# Uygulamalar
for ini in "$M"/usr/lib*/firefox*/application.ini; do [ -f "$ini" ] && grep -E '^(Name|Version)=' "$ini"; done > "$L/firefox.txt" 2>/dev/null
ls "$M"/usr/lib*/libQt6Core.so.* 2>/dev/null | xargs -n1 basename > "$L/qt6.txt"
ls "$M/var/lib/atasos-paketler" > "$L/atasos-paketler.txt" 2>/dev/null
cp "$M/etc/os-release" "$L/os-release" 2>/dev/null
grep -h -E '^(Version|Name)' "$M"/usr/share/plasma/look-and-feel/*/metadata.desktop 2>/dev/null | head -4 > "$L/plasma.txt"
for p in calamares sddm plasmashell kwin_x11 dolphin konsole kate; do
    b=$(ls "$M/usr/bin/$p" 2>/dev/null) && strings "$b" 2>/dev/null | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sed "s/^/$p\t/"
done > "$L/uygulamalar.tsv"
wc -l "$L"/*.tsv

echo "########## 4/4  SHA256 ##########"
( cd "$H" && find arsivler cekirdek -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )
echo "  $(wc -l < "$H/SHA256SUMS") dosya; toplam $(du -sh "$H" | cut -f1)"
echo "TAMAM: $H"
