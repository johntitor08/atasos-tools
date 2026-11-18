#!/usr/bin/env bash
# atasos-85: paketleri ZATEN archive.org'da olan (atasos-84 dogruladi) bir yayinin YALNIZ dizinini imzalar ve yukler.
#   - mevcut dizin indirilir, imzasi depo acik anahtariyla dogrulanir
#   - /veri/atasos-paket/paketler/SHA256SUMS'taki ve dizinde olmayan paketler eklenir
#   - her paket icin archive.org'daki boyut yerel dosyayla karsilastirilir (hizli; tam sha256 denetimini 84 yapti)
#   - 'evet' -> gpg parolasi HEMEN sorulur (pencere arkada kalabilir; gorev cubuguna bak) -> dizin + imza yuklenir
# Kullanim (sudo YOK): bash ~/atasos-85-dizin-imzala-yukle.sh [paket.atspkg.tar.zst ...]  (arguman yoksa SHA256SUMS'taki hepsi)
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -ne 0 ] || { echo "Root olarak DEGIL calistir: bash $0"; exit 1; }
export GNUPGHOME=$HOME/.atasos-depo-imza
P=/veri/atasos-paket/paketler
KN=/veri/atasos-iso/kanal
IA=$HOME/atas3-loglar/ia-venv/bin/ia
DEPO=https://archive.org/download/atasos-depo
FPR=$(cat $KN/parmak-izi.txt 2>/dev/null)
[ -d "$GNUPGHOME" ] && [ -n "$FPR" ] && [ -x "$IA" ] && [ -f $P/SHA256SUMS ] || { echo "HATA: anahtar/ia/SHA256SUMS eksik"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o $T/atspkg.index "$DEPO/atspkg.index" && curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o $T/atspkg.index.sig "$DEPO/atspkg.index.sig" \
    && gpgv --keyring $KN/depo-anahtari.gpg $T/atspkg.index.sig $T/atspkg.index >/dev/null 2>&1 \
    || { echo "HATA: mevcut dizin indirilemedi ya da imzasi gecersiz"; exit 1; }
cp $T/atspkg.index $T/yeni.index
# arguman verilirse YALNIZ o paket dosyalari eklenir (SHA256SUMS'ta yayinlanmamis baska paketler de olabilir)
SECILEN=" $* "
while read -r h f; do
    [ $# -eq 0 ] || [[ "$SECILEN" == *" $f "* ]] || continue
    pk=$(tar -xOf "$P/$f" .PKGINFO 2>/dev/null) || { echo "HATA: $f okunamadi"; exit 1; }
    ad=$(awk -F' = ' '$1=="name"{print $2}' <<< "$pk"); sr=$(awk -F' = ' '$1=="version"{print $2}' <<< "$pk"); yy=$(awk -F' = ' '$1=="release"{print $2}' <<< "$pk")
    awk -v a="$ad" -v s="$sr" -v y="$yy" '$1==a && $2==s && $3==y{f=1} END{exit !f}' $T/yeni.index && continue
    [ "$(sha256sum "$P/$f" | cut -d' ' -f1)" = "$h" ] || { echo "HATA: $f yerel sha256 tutmuyor"; exit 1; }
    u=$(curl -sIL --retry 5 --retry-all-errors --retry-delay 5 "$DEPO/$f" | awk 'tolower($1)=="content-length:"{v=$2} END{gsub("\r","",v); print v}')
    [ "$u" = "$(stat -c%s "$P/$f")" ] || { echo "HATA: $f archive.org'da yok ya da boyutu farkli ($u); once atasos-84"; exit 1; }
    echo "$ad $sr $yy $f $h" >> $T/yeni.index
    echo "  eklenecek: $ad $sr-$yy (archive.org'da, boyut ayni)"
done < $P/SHA256SUMS
cmp -s $T/atspkg.index $T/yeni.index && { echo "  Dizin zaten guncel; yapilacak bir sey yok."; exit 0; }
echo "  Yeni dizin:"; sed 's/^/    /' $T/yeni.index
read -r -p "  Imzalanip yuklensin mi? 'evet' yaz (sonra gpg parolasini HEMEN soracak): " C
[ "$C" = evet ] || { echo "  iptal."; exit 0; }
gpg --local-user "$FPR" --detach-sign -o $T/yeni.index.sig $T/yeni.index || { echo "HATA: imzalanamadi (parola penceresi zaman asimi olduysa yeniden calistir)"; exit 1; }
gpgv --keyring $KN/depo-anahtari.gpg $T/yeni.index.sig $T/yeni.index >/dev/null 2>&1 || { echo "HATA: imza dogrulanamadi"; exit 1; }
mkdir -p $T/y && cp $T/yeni.index $T/y/atspkg.index && cp $T/yeni.index.sig $T/y/atspkg.index.sig
(cd $T/y && "$IA" upload atasos-depo atspkg.index atspkg.index.sig --retries 5) || { echo "HATA: dizin yuklenemedi"; exit 1; }
cp $T/yeni.index $P/atspkg.index.yayinlanan
echo "  TAMAM: imzali dizin yuklendi. archive.org'da gorunmesi birkac dakika - yarim saat surebilir."
