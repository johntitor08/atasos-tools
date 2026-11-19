#!/usr/bin/env bash
# atasos-92: archive.org'daki atspkg.index yeni, atspkg.index.sig eskiyse (imza yuklemesi yarida kaldiysa) YALNIZ imzayi onarir.
#   - archive.org'daki dizin indirilir; HER satiri yerel paketler/SHA256SUMS ile birebir denetlenir (ad-surum-yayin dosya adi
#     ve sha256) ve son yayinlanan yerel dizinin (atspkg.index.yayinlanan) tum satirlarini icermelidir -> dizin bizim dizinimiz
#   - 'evet' -> gpg parolasi HEMEN sorulur -> imza depo acik anahtariyla dogrulanir -> yalniz atspkg.index.sig yuklenir
# Kullanim (sudo YOK): bash ~/atasos-92-imza-onar.sh
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
C="curl -fsSL --retry 5 --retry-all-errors --retry-delay 5"
$C -o $T/atspkg.index "$DEPO/atspkg.index" && $C -o $T/eski.sig "$DEPO/atspkg.index.sig" || { echo "HATA: dizin indirilemedi"; exit 1; }
if gpgv --keyring $KN/depo-anahtari.gpg $T/eski.sig $T/atspkg.index >/dev/null 2>&1; then
    echo "  archive.org'daki dizin ($(wc -l < $T/atspkg.index) kayit) imzasi ZATEN gecerli; yapilacak bir sey yok."; exit 0
fi
H=0
while read -r ad sr yy f h; do
    [ "$f" = "$ad-$sr-$yy.atspkg.tar.zst" ] || { echo "  HATA: satir bicimi: $ad $sr $yy $f"; H=1; continue; }
    # ya daha once imzalanip yayinlanmis dizinde birebir ayni satir, ya da yerel SHA256SUMS ile ayni sha256
    if grep -qxF "$ad $sr $yy $f $h" $P/atspkg.index.yayinlanan 2>/dev/null; then echo "  tamam (onceki imzali dizinde): $f"; continue; fi
    y=$(awk -v f="$f" '$2==f{print $1}' $P/SHA256SUMS)
    [ "$y" = "$h" ] && echo "  tamam (yerel paket): $f" || { echo "  HATA: $f yerel SHA256SUMS ile tutmuyor (${y:-yerelde yok})"; H=1; }
done < $T/atspkg.index
if [ -f $P/atspkg.index.yayinlanan ]; then
    while read -r l; do grep -qxF "$l" $T/atspkg.index || { echo "  HATA: son yayinlanan satir dizinde yok: $l"; H=1; }; done < $P/atspkg.index.yayinlanan
fi
[ $H -eq 0 ] || { echo "  DURDU: archive.org'daki dizin bizim paketlerimizle birebir degil; imzalanmadi."; exit 1; }
echo "  Dizin ($(wc -l < $T/atspkg.index) kayit) yerel paketlerle birebir; imza eski/gecersiz."
read -r -p "  Bu dizin imzalanip YALNIZ atspkg.index.sig yuklensin mi? 'evet' yaz (sonra gpg parolasi): " E
[ "$E" = evet ] || { echo "  iptal."; exit 0; }
gpg --local-user "$FPR" --detach-sign -o $T/atspkg.index.sig $T/atspkg.index || { echo "HATA: imzalanamadi"; exit 1; }
gpgv --keyring $KN/depo-anahtari.gpg $T/atspkg.index.sig $T/atspkg.index >/dev/null 2>&1 || { echo "HATA: imza dogrulanamadi"; exit 1; }
(cd $T && "$IA" upload atasos-depo atspkg.index.sig --retries 5) || { echo "HATA: imza yuklenemedi (tekrar calistir)"; exit 1; }
cp $T/atspkg.index $P/atspkg.index.yayinlanan
echo "  TAMAM: imza yuklendi. archive.org'da gorunmesi birkac dakika - yarim saat surebilir."
