#!/usr/bin/env bash
# atasOS canli ISO'yu (varsayilan: en yeni /veri/atasos-iso/atasos-live-vNN.iso) archive.org'daki
# 'atasos-live' item'ina yukler, yuklenen dosyayi dogrular, sonra eski ISO'lari TEK TEK sorarak siler.
# Siralama v14 yayinindaki gibi guvenli: yeni ISO archive.org'da dogrulanmadan hicbir sey silinmez.
#
# ROOT DEGIL, normal kullanici olarak calistir (archive.org kimligi ~/.config/internetarchive/ia.ini'de):
#   bash /home/eren/atasos-63-archive-yukle.sh [iso-yolu]
# Ilk calismada ia.ini yoksa 'ia configure' archive.org e-posta + parolani SORAR (sen yazarsin, betik saklamaz;
# ia bunlarla S3 anahtarlarini alip ia.ini'ye yazar). Hesap: atasOS'un archive.org hesabi.
set -uo pipefail
[ "$(id -u)" -ne 0 ] || { echo "root olarak calistirma (ia.ini root'un evine gider): bash $0"; exit 1; }

ITEM=atasos-live
ISO=${1:-$(ls /veri/atasos-iso/atasos-live-v[0-9]*.iso 2>/dev/null | sort -V | tail -1)}
[ -n "$ISO" ] && [ -f "$ISO" ] && [ -f "$ISO.sha256" ] || { echo "HATA: ISO ya da $ISO.sha256 yok"; exit 1; }
AD=$(basename "$ISO")
BOY=$(stat -c %s "$ISO")
SHA=$(awk '{print $1}' "$ISO.sha256")
URL=https://archive.org/download/$ITEM/$AD
VENV=$HOME/.local/share/atasos/ia-venv
IA=$VENV/bin/ia
LOG=$(dirname "$ISO")/${AD%.iso}-yukleme.log
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS ISO -> archive.org/$ITEM  ($(date '+%F %T')) ##########"
echo "  ISO: $ISO ($((BOY/1024/1024)) MB)"

echo
echo "########## 1/5  YEREL DOGRULAMA ##########"
G=$(sha256sum "$ISO" | awk '{print $1}')
[ "$G" = "$SHA" ] && echo "  sha256 ayni: ${SHA:0:12}..." || { echo "  HATA: ISO .sha256 ile uyusmuyor, iptal."; exit 1; }
# .sha256 dosyasi yalniz dosya adini icersin (indiren 'sha256sum -c' calistirabilsin)
grep -q " [ *]\?$AD\$" "$ISO.sha256" || { echo "  UYARI: .sha256 icinde '$AD' adi yok:"; cat "$ISO.sha256"; }

echo
echo "########## 2/5  ia ARACI ##########"
if [ ! -x "$IA" ]; then
    python3 -m venv "$VENV" 2>/dev/null || { echo "  python3-venv yok: sudo apt install python3-venv"; exit 1; }
    "$VENV/bin/pip" install -q --upgrade internetarchive || { echo "  HATA: internetarchive kurulamadi"; exit 1; }
fi
echo "  $("$IA" --version 2>&1 | head -1)  ($IA)"
if [ ! -f "$HOME/.config/internetarchive/ia.ini" ] && [ ! -f "$HOME/.ia" ]; then
    echo "  archive.org kimligi yok. Simdi archive.org e-posta ve parolani gir (atasOS hesabi):"
    "$IA" configure || { echo "  HATA: ia configure basarisiz"; exit 1; }
fi
"$IA" metadata "$ITEM" >/dev/null 2>&1 || { echo "  HATA: '$ITEM' item'ina ulasilamadi (ag/kimlik?)"; exit 1; }
echo "  item'daki ISO'lar (liste gecikmeli tazelenebilir):"
mapfile -t ESKI < <("$IA" list "$ITEM" 2>/dev/null | grep -E '^atasos-live-v[0-9]+\.iso$' | grep -vx "$AD" | sort -V)
"$IA" list "$ITEM" 2>/dev/null | grep -E '\.iso$' | sed 's/^/    /'

echo
echo "########## 3/5  YUKLEME ##########"
# --checksum: ayni dosya zaten tam yuklenmisse atlar (yarida kalan bir denemeden sonra tekrar calistirmak guvenli).
# --retries 10: v14'te ilk deneme %94'te RemoteDisconnected ile dusmustu.
"$IA" upload "$ITEM" "$ISO" "$ISO.sha256" --checksum --retries 10 \
    || { echo "  HATA: yukleme basarisiz. Betigi tekrar calistir; --checksum biten dosyalari atlar."; exit 1; }

echo
echo "########## 4/5  ARCHIVE.ORG'DA DOGRULAMA ##########"
# 'ia list' gecikmeli; kesin yol dogrudan indirme adresi: HTTP 200 + birebir boyut + .sha256 icerigi.
TAMAM=0
for i in $(seq 1 60); do
    H=$(curl -sIL --max-time 60 "$URL" | tr -d '\r')
    KOD=$(printf '%s\n' "$H" | awk '/^HTTP/{k=$2} END{print k}')
    UZ=$(printf '%s\n' "$H" | awk 'tolower($1)=="content-length:"{l=$2} END{print l}')
    if [ "$KOD" = 200 ] && [ "$UZ" = "$BOY" ]; then TAMAM=1; break; fi
    echo "  bekleniyor ($i/60): HTTP ${KOD:-?}, boyut ${UZ:-?} / $BOY"
    sleep 30
done
[ $TAMAM = 1 ] || { echo "  HATA: $URL 30 dakikada dogrulanamadi. Eski ISO'lara DOKUNULMADI."; exit 1; }
echo "  $URL -> HTTP 200, $BOY bayt (birebir)"
USHA=$(curl -sSfL --max-time 60 "$URL.sha256" | awk '{print $1}')
[ "$USHA" = "$SHA" ] && echo "  uzak .sha256 ayni: ${SHA:0:12}..." \
    || { echo "  HATA: uzak .sha256 '$USHA' != '$SHA'. Eski ISO'lara DOKUNULMADI."; exit 1; }

echo
echo "########## 5/5  ESKI ISO'LAR ##########"
if [ ${#ESKI[@]} -eq 0 ]; then
    echo "  item'da baska ISO yok."
else
    # --no-backup: silinen dosya history/ altina tasinmaz, KALICI silinir (v13-v15'te history'ye tasinip yer kaplamaya devam etmisti)
    echo "  Silinen dosya KALICI olarak silinir (history/ yedegi tutulmaz, geri alinamaz)."
    for f in "${ESKI[@]}"; do
        read -r -p "  $f (+ .sha256) silinsin mi? 'evet' yaz, baska her sey = birak: " C
        if [ "$C" = "evet" ]; then
            S=("$f"); "$IA" list "$ITEM" 2>/dev/null | grep -qx "$f.sha256" && S+=("$f.sha256")
            "$IA" delete "$ITEM" --no-backup "${S[@]}" && echo "    silindi: ${S[*]}" || echo "    HATA: silinemedi: ${S[*]}"
        else
            echo "    birakildi: $f"
        fi
    done
fi

echo
echo "  BITTI. Indirme: $URL"
echo "  Dogrulama (indiren icin): sha256sum -c $AD.sha256"
echo "  Kayit: $LOG"
