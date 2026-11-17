#!/usr/bin/env bash
# atasos-78: atasOS paket deposu (archive.org atasos-depo) icin IMZA ANAHTARI olusturur. ROOT GEREKMEZ.
#   - gizli anahtar: ~/.atasos-depo-imza/ (yalniz bu bilgisayarda; repoya, archive.org'a, ISO'ya GIRMEZ)
#   - acik anahtar : /veri/atasos-iso/kanal/depo-anahtari.gpg (+ .asc, parmak-izi.txt) -> v36 ISO'ya girer;
#                    atspkg 0.3.0 depo dizinini (atspkg.index) yalniz bu anahtarla imzaliysa kabul eder
#   - parolayi gpg'nin kendi penceresine SEN yazarsin (bos birakma); iptal sertifikasi otomatik uretilir
# Anahtar kaybolursa: kurulu sistemlere guncelleme gonderilemez (yeni ISO + yeniden kurulum gerekir).
#   -> ~/.atasos-depo-imza klasorunu bir USB bellege / sifreli yedege kopyala.
# Kullanim (Konsole'da, sudo YOK): bash ~/atasos-78-depo-anahtari.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -ne 0 ] || { echo "Bunu root olarak DEGIL, kendi kullanicinla calistir: bash $0"; exit 1; }
G=$HOME/.atasos-depo-imza
K=/veri/atasos-iso/kanal
AD="atasOS paket deposu"
[ -e "$G" ] && { echo "  $G zaten var; anahtar zaten olusturulmus. Hicbir sey yapilmadi."; exit 1; }
[ -d "$K" ] || { echo "HATA: $K yok"; exit 1; }
mkdir -m 700 "$G"
export GNUPGHOME=$G

echo "########## atasOS depo imza anahtari ##########"
echo "  Simdi gpg bir parola isteyecek (iki kez). Bu parola her guncelleme yayininda sorulur."
echo "  Unutursan anahtar kullanilamaz. Bos birakma."
echo
gpg --quick-generate-key "$AD" ed25519 sign never || { echo "HATA: anahtar olusturulamadi"; rm -rf "$G"; exit 1; }

FPR=$(gpg --batch --with-colons --list-secret-keys "$AD" | awk -F: '$1=="fpr"{print $10; exit}')
[ -n "$FPR" ] || { echo "HATA: parmak izi okunamadi"; exit 1; }
gpg --batch --export "$FPR" > "$K/depo-anahtari.gpg"
gpg --batch --armor --export "$FPR" > "$K/depo-anahtari.asc"
echo "$FPR" > "$K/parmak-izi.txt"

# deneme: imzala + yalniz acik anahtarla dogrula (atspkg'nin yapacagi gibi)
D=$(mktemp -d); echo "atasOS deneme $(date +%s)" > "$D/x"
gpg --batch --yes --detach-sign -o "$D/x.sig" "$D/x" && gpgv --keyring "$K/depo-anahtari.gpg" "$D/x.sig" "$D/x" >/dev/null 2>&1 \
    && echo "  deneme imzasi: GECERLI" || echo "  deneme imzasi: BASARISIZ <<< Bu ciktiyi Claude'a yapistir"
rm -rf "$D"

echo
echo "########## OZET ##########"
echo "  parmak izi : $FPR"
echo "  acik anahtar: $K/depo-anahtari.gpg (v36 ISO'ya girecek)"
echo "  gizli anahtar + iptal sertifikasi: $G  (openpgp-revocs.d/ icinde)"
echo
echo "  YAPMAN GEREKEN: $G klasorunu bir USB bellege ya da sifreli bir yedege kopyala."
echo "  Bu klasoru kimseyle paylasma; GitHub'a ya da archive.org'a yukleme."
