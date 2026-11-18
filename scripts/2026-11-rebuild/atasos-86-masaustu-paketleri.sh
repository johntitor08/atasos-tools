#!/usr/bin/env bash
# atasos-86: Claude Desktop ve bagimliliklarini atspkg paketi yapar (calisan atasOS'ta, ~/build'deki kaynaklarla).
#   paketler (bu sirayla): nspr sqlite nss libcups atasos-xdg-open claude-desktop
#   - kaynaklar ~/build'den alinir (2026-11-18'de https ile indirilip elle derlenenler), sha256'lari kaydedilir
#   - her tarif 'atspkg derle' ile paketlenir; sisteme HICBIR SEY kurulmaz
#   - paket denetimi: RPATH'te derleme yolu, SONAME/NEEDED, chrome-sandbox setuid root
#   - cikti: ~/atasos-paket/*.atspkg.tar.zst + SHA256SUMS + KAYNAKLAR.sha256
# Kullanim: bash atasos-86-masaustu-paketleri.sh [paket ...]     (root GEREKMEZ)
set -uo pipefail
export LC_ALL=C
R=$(cd "$(dirname "$0")" && pwd)
T=$R/paketler/tarifler
B=${KAYNAK_DIZINI:-$HOME/build}
C=${CIKTI:-$HOME/atasos-paket}
ATSPKG=$(command -v atspkg 2>/dev/null || echo "$R/atspkg-0.3.0")
PAKETLER=("$@"); [ ${#PAKETLER[@]} -gt 0 ] || PAKETLER=(nspr sqlite nss libcups atasos-xdg-open claude-desktop)
mkdir -p "$C"
LOG=$C/derleme-$(date +%Y%m%d-%H%M).log
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS 86: masaustu paketleri ($(date '+%F %T'))  ${PAKETLER[*]} ##########"
echo "  atspkg: $ATSPKG   kaynaklar: $B   cikti: $C"

DEB=$(ls "$B"/claude/claude-desktop_*_amd64.deb "$B"/claude-desktop_*_amd64.deb 2>/dev/null | sort -V | tail -1)
declare -A KAYNAK=(
    [nspr]="$B/nspr-4.36.tar.gz"
    [sqlite]="$B/sqlite-autoconf-3490100.tar.gz"
    [nss]="$B/nss-3.108.tar.gz $B/nss-standalone-1.patch"
    [libcups]="$B/cups-2.4.11-source.tar.gz"
    [atasos-xdg-open]="$R/../xdg-open"
    [claude-desktop]="$DEB"
)
# Bagimsiz ikinci indirmeyle karsilastirilan sha256 (Claude'un ortaminda GitHub'dan indirildi, 2026-11-18)
declare -A BILINEN=( [cups-2.4.11-source.tar.gz]=9a88fe1da3a29a917c3fc67ce6eb3178399d68e1a548c6d86c70d9b13651fd71 )

echo; echo "########## 1/3  KAYNAK DENETIMI ##########"
for p in "${PAKETLER[@]}"; do
    [ -f "$T/$p/tarif" ] || { echo "HATA: tarif yok: $T/$p/tarif"; exit 1; }
    for f in ${KAYNAK[$p]:-}; do
        [ -f "$f" ] || { echo "HATA: kaynak yok: $f  (KAYNAK_DIZINI=... ile baska dizin verilebilir)"; exit 1; }
        b=${f##*/}; h=$(sha256sum "$f" | cut -d' ' -f1)
        if [ -n "${BILINEN[$b]:-}" ]; then
            [ "$h" = "${BILINEN[$b]}" ] && echo "  $b: sha256 bagimsiz indirmeyle ayni" \
                || { echo "HATA: $b sha256 beklenenden farkli ($h)"; exit 1; }
        fi
        grep -q "  $b\$" "$C/KAYNAKLAR.sha256" 2>/dev/null || echo "$h  $b" >> "$C/KAYNAKLAR.sha256"
    done
    want=$(bash -c '. "$1"; printf "%s\n" "${source[@]}"' _ "$T/$p/tarif" | sort | tr '\n' ' ')
    have=$(for f in ${KAYNAK[$p]}; do echo "${f##*/}"; done | sort | tr '\n' ' ')
    [ "$want" = "$have" ] || { echo "HATA: $p tarifi '$want' istiyor, bulunan '$have'"; exit 1; }
done
echo "  kaynaklar tamam (sha256: $C/KAYNAKLAR.sha256)"

echo; echo "########## 2/3  DERLEME ##########"
declare -A DOSYA
for p in "${PAKETLER[@]}"; do
    D=$T/$p
    for f in ${KAYNAK[$p]}; do cp -f "$f" "$D/"; done
    rm -f "$D"/*.atspkg.tar.zst
    S=$(date +%s)
    echo "== $p derleniyor (kayit: $C/$p-derleme.log)"
    if ! bash "$ATSPKG" derle "$D" > "$C/$p-derleme.log" 2>&1; then
        echo "  HATA: $p derlenemedi. Son satirlar:"; tail -n 15 "$C/$p-derleme.log" | sed 's/^/    /'
        for f in ${KAYNAK[$p]}; do rm -f "$D/${f##*/}"; done; exit 1
    fi
    DOSYA[$p]=$(ls "$D"/$p-*.atspkg.tar.zst | head -1)
    mv -f "${DOSYA[$p]}" "$C/"; DOSYA[$p]=$C/${DOSYA[$p]##*/}
    rm -rf "$D/work"; for f in ${KAYNAK[$p]}; do rm -f "$D/${f##*/}"; done
    echo "  tamam: ${DOSYA[$p]##*/} ($(du -h "${DOSYA[$p]}" | cut -f1), $(( ($(date +%s)-S)/60 )) dk)"
done

echo; echo "########## 3/3  PAKET DENETIMI ##########"
H=0
for p in "${PAKETLER[@]}"; do
    F=${DOSYA[$p]}; L=$(tar -tvf "$F")
    X=$(mktemp -d); tar -xf "$F" -C "$X"
    rp=$(find "$X" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c 'readelf -d "$1" 2>/dev/null | grep -E "R(UN)?PATH" | grep -qE "/home/|/tmp|work/" && echo "$1"' _ {} \; | sed "s|$X/||")
    [ -z "$rp" ] && echo "  $p: derleme yolu sizintisi yok" || { echo "  $p: RPATH'te derleme yolu <<<"; echo "$rp" | sed 's/^/      /'; H=1; }
    yasak=$(tar -tf "$F" | sed 's|^\./||' | grep -E '^(etc/apt|tmp|mnt|root|home|run)(/|$)' || true)
    [ -z "$yasak" ] || { echo "  $p: YASAK YOL <<<"; echo "$yasak" | sed 's/^/      /'; H=1; }
    case $p in
        sqlite) readelf -d "$X/usr/lib/libsqlite3.so" | grep -q 'SONAME.*libsqlite3\.so\.0' \
                    && echo "  sqlite: SONAME libsqlite3.so.0" || { echo "  sqlite: SONAME YOK <<<"; H=1; } ;;
        nss)    readelf -d "$X/usr/lib/libsoftokn3.so" | grep -q 'NEEDED.*libsqlite3\.so\.0' \
                    && echo "  nss: libsoftokn3 -> libsqlite3.so.0" || { echo "  nss: sistem sqlite'ina bagli degil <<<"; H=1; }
                [ -f "$X/usr/lib/libsoftokn3.chk" ] && echo "  nss: .chk var" || { echo "  nss: .chk YOK <<<"; H=1; } ;;
        nspr)   [ -f "$X/usr/lib/libnspr4.so" ] && echo "  nspr: libnspr4.so var" || { echo "  nspr: libnspr4.so YOK <<<"; H=1; } ;;
        libcups) [ -f "$X/usr/lib/libcups.so.2" ] && echo "  libcups: libcups.so.2 var" || { echo "  libcups: YOK <<<"; H=1; } ;;
        claude-desktop)
                grep -qE '^-rws..x..x root/root .* (\./)?usr/lib/claude-desktop/chrome-sandbox$' <<< "$L" \
                    && echo "  claude-desktop: chrome-sandbox setuid root" || { echo "  claude-desktop: chrome-sandbox setuid root DEGIL <<<"; H=1; }
                grep -h '^Exec=' "$X"/usr/share/applications/*.desktop 2>/dev/null | sed 's/^/  claude-desktop: /' ;;
    esac
    rm -rf "$X"
done
[ $H -eq 0 ] || { echo "  DURDU: paket denetimi basarisiz."; exit 1; }

(cd "$C" && sha256sum *.atspkg.tar.zst > SHA256SUMS)
echo; echo "########## OZET ##########"
sed 's/^/  /' "$C/SHA256SUMS"
echo "  kayit: $LOG"
echo "  Kurmak (bu sirayla; dosyalar zaten sistemde oldugu icin ayni dosyalarin ustune yazar ve atspkg'ye kaydeder):"
printf '    sudo atspkg kur'; for p in "${PAKETLER[@]}"; do printf ' %s' "${DOSYA[$p]}"; done; echo
