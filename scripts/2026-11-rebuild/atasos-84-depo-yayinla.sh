#!/usr/bin/env bash
# atasos-84 (83'un yerine): archive.org'da AYNI sha256 ile zaten duran paketler YENIDEN YUKLENMEZ (yalniz eksik/farkli olanlar).
# atasos-83: derlenmis paketleri (atasos-82 ciktisi) archive.org paket deposuna (atasos-depo) YAYINLAR. ROOT GEREKMEZ.
#   1) depodaki mevcut dizin (atspkg.index) indirilir ve IMZASI depo acik anahtariyla dogrulanir (temel guvenilir olmali)
#   2) secilen paketler /veri/atasos-paket/paketler/SHA256SUMS ile denetlenir; dizinde ayni ad+surum+yayin varsa REDDEDILIR
#   3) yeni dizin gosterilir, 'evet' yazmadan hicbir sey yuklenmez (YUKLEME YAYINDIR)
#   4) once paketler yuklenir ve archive.org'dan geri indirilip sha256'lari denetlenir
#   5) sonra yeni dizin imzalanir (parolani gpg'nin penceresine SEN yazarsin), acik anahtarla dogrulanir, dizin + imza yuklenir
# Kullanim (sudo YOK): bash ~/atasos-84-depo-yayinla.sh <paket-dosyasi-adi>...   (ornek: openssl-3.5.9-1.atspkg.tar.zst)
#                      bash ~/atasos-84-depo-yayinla.sh --hepsi                 (paketler/ altindaki hepsi)
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -ne 0 ] || { echo "Root olarak DEGIL, kendi kullanicinla calistir: bash $0"; exit 1; }
export GNUPGHOME=$HOME/.atasos-depo-imza
P=/veri/atasos-paket/paketler
KN=/veri/atasos-iso/kanal
IA=$HOME/atas3-loglar/ia-venv/bin/ia
DEPO=https://archive.org/download/atasos-depo
FPR=$(cat $KN/parmak-izi.txt 2>/dev/null)
[ -d "$GNUPGHOME" ] && [ -n "$FPR" ] && [ -s $KN/depo-anahtari.gpg ] || { echo "HATA: depo anahtari/parmak izi yok (atasos-78)"; exit 1; }
[ -x "$IA" ] || { echo "HATA: $IA yok"; exit 1; }
[ -f $P/SHA256SUMS ] || { echo "HATA: $P/SHA256SUMS yok (once atasos-82)"; exit 1; }
SECILEN=()
if [ "${1:-}" = --hepsi ]; then for f in $P/*.atspkg.tar.zst; do SECILEN+=("${f##*/}"); done
else SECILEN=("$@"); fi
[ ${#SECILEN[@]} -gt 0 ] || { echo "Kullanim: bash $0 <paket.atspkg.tar.zst>... | --hepsi"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

echo "########## 1/4  MEVCUT DIZIN (imza denetimi) ##########"
curl -fsSL -o $T/atspkg.index "$DEPO/atspkg.index" && curl -fsSL -o $T/atspkg.index.sig "$DEPO/atspkg.index.sig" \
    || { echo "HATA: mevcut dizin/imza indirilemedi"; exit 1; }
gpgv --keyring $KN/depo-anahtari.gpg $T/atspkg.index.sig $T/atspkg.index >/dev/null 2>&1 \
    || { echo "HATA: depodaki MEVCUT dizinin imzasi gecersiz. Depo degistirilmis olabilir; yayin durduruldu."; exit 1; }
echo "  mevcut dizin gecerli ($(wc -l < $T/atspkg.index) kayit)"
cp $T/atspkg.index $T/yeni.index

echo
echo "########## 2/4  PAKETLER ##########"
for f in "${SECILEN[@]}"; do
    [ -f "$P/$f" ] || { echo "HATA: $P/$f yok"; exit 1; }
    h=$(awk -v f="$f" '$2==f{print $1}' $P/SHA256SUMS)
    [ -n "$h" ] && [ "$(sha256sum "$P/$f" | cut -d' ' -f1)" = "$h" ] || { echo "HATA: $f SHA256SUMS ile tutmuyor"; exit 1; }
    pk=$(tar -xOf "$P/$f" .PKGINFO 2>/dev/null) || { echo "HATA: $f icinde .PKGINFO yok"; exit 1; }
    ad=$(awk -F' = ' '$1=="name"{print $2}' <<< "$pk"); sr=$(awk -F' = ' '$1=="version"{print $2}' <<< "$pk"); yy=$(awk -F' = ' '$1=="release"{print $2}' <<< "$pk")
    [ "$f" = "$ad-$sr-$yy.atspkg.tar.zst" ] || { echo "HATA: dosya adi ($f) PKGINFO ile ($ad-$sr-$yy) tutmuyor"; exit 1; }
    # ""-birlestirme: METIN karsilastirmasi (awk sayi gibi gorunen alanlari sayisal karsilastirir: 1.10 == 1.1)
    awk -v a="$ad" -v s="$sr" -v y="$yy" '$1""==a"" && $2""==s"" && $3""==y""{f=1} END{exit !f}' $T/yeni.index \
        && { echo "HATA: dizinde zaten var: $ad $sr-$yy (ayni surum yeniden yayinlanamaz; release'i artir)"; exit 1; }
    echo "$ad $sr $yy $f $h" >> $T/yeni.index
    echo "  eklenecek: $ad $sr-$yy  ($(du -h "$P/$f" | cut -f1), sha256 ${h:0:16}...)"
done

echo
echo "########## 3/4  ONAY ##########"
echo "  Yeni dizin:"; sed 's/^/    /' $T/yeni.index
read -r -p "  Paketler ve imzali dizin archive.org'a (atasos-depo) yuklensin mi? 'evet' yaz: " C
[ "$C" = evet ] || { echo "  iptal; hicbir sey yuklenmedi."; exit 0; }

echo
echo "########## 4/4  YUKLEME ##########"
YUKLE=()
for f in "${SECILEN[@]}"; do
    h=$(awk -v f="$f" '$2==f{print $1}' $P/SHA256SUMS)
    if [ "$(curl -fsSL --max-time 300 "$DEPO/$f" 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$h" ]; then
        echo "  zaten archive.org'da (sha256 ayni), yuklenmeyecek: $f"
    else YUKLE+=("$f"); fi
done
if [ ${#YUKLE[@]} -gt 0 ]; then
    (cd $P && "$IA" upload atasos-depo "${YUKLE[@]}" --retries 5) || { echo "HATA: paket yuklemesi basarisiz (dizin degismedi)"; exit 1; }
fi
for f in "${SECILEN[@]}"; do
    h=$(awk -v f="$f" '$2==f{print $1}' $P/SHA256SUMS); n=0
    echo "  archive.org'da denetleniyor: $f (yeni dosyalarin gorunmesi archive.org sirasina gore birkac dk - yarim saat surebilir)"
    until [ "$(curl -fsSL "$DEPO/$f" 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$h" ]; do
        n=$((n+1)); [ $n -ge 120 ] && { echo "HATA: $f archive.org'da 60 dk icinde gorunmedi; dizin YUKLENMEDI (paketler duruyor, betigi sonra yeniden calistir)"; exit 1; }
        echo "    bekleniyor... ($((n/2)) dk)"; sleep 30; done
    echo "  archive.org'da dogrulandi: $f"
done
gpg --local-user "$FPR" --detach-sign -o $T/yeni.index.sig $T/yeni.index || { echo "HATA: imzalanamadi"; exit 1; }
gpgv --keyring $KN/depo-anahtari.gpg $T/yeni.index.sig $T/yeni.index >/dev/null 2>&1 || { echo "HATA: yeni imza dogrulanamadi"; exit 1; }
mkdir -p $T/y && cp $T/yeni.index $T/y/atspkg.index && cp $T/yeni.index.sig $T/y/atspkg.index.sig
(cd $T/y && "$IA" upload atasos-depo atspkg.index atspkg.index.sig --retries 5) || { echo "HATA: dizin yuklenemedi"; exit 1; }
cp $T/yeni.index $P/atspkg.index.yayinlanan
echo "  TAMAM: dizin + imza yuklendi. archive.org'da gorunmesi birkac dakika surebilir;"
echo "  o arada istemcilerde 'imza gecersiz' gorulebilir (eski dizin korunur, guvenli)."
