#!/usr/bin/env bash
# atasos-80: archive.org'daki paket deposunun (atasos-depo) dizinini (atspkg.index) depo anahtariyla IMZALAR
# ve atspkg.index.sig olarak yukler. ROOT GEREKMEZ. Parolani gpg'nin kendi penceresine SEN yazarsin.
#   - dizin archive.org'dan indirilir; her satirdaki paketin sha256'si archive.org'daki dosyayla karsilastirilir
#     (imzalamadan once: imzalanan liste gercekten depodakiyle ayni olmali)
#   - imza yalniz acik anahtarla (atspkg'nin yapacagi gibi) dogrulanir, sonra yuklenir
#   - YUKLEME YAYINDIR: once ozet gosterilir, 'evet' yazmadan yuklenmez
# Kullanim (Konsole'da, sudo YOK): bash ~/atasos-80-depo-imzala.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -ne 0 ] || { echo "Root olarak DEGIL, kendi kullanicinla calistir: bash $0"; exit 1; }
export GNUPGHOME=$HOME/.atasos-depo-imza
KN=/veri/atasos-iso/kanal
IA=$HOME/atas3-loglar/ia-venv/bin/ia
DEPO=https://archive.org/download/atasos-depo
[ -d "$GNUPGHOME" ] || { echo "HATA: $GNUPGHOME yok (once atasos-78)"; exit 1; }
FPR=$(cat $KN/parmak-izi.txt 2>/dev/null); [ -n "$FPR" ] || { echo "HATA: $KN/parmak-izi.txt yok"; exit 1; }
[ -x "$IA" ] || { echo "HATA: $IA yok"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

echo "########## 1/3  DIZIN VE PAKETLER DENETLENIYOR ##########"
curl -fsSL -o "$T/atspkg.index" "$DEPO/atspkg.index" || { echo "HATA: dizin indirilemedi"; exit 1; }
n=0
while read -r ad surum yayin dosya sha; do
    [ -n "${ad:-}" ] || continue
    gercek=$(curl -fsSL "$DEPO/$dosya" | sha256sum | cut -d' ' -f1)
    [ "$gercek" = "$sha" ] && echo "  tamam: $ad $surum-$yayin ($dosya)" || { echo "  TUTMUYOR: $dosya (dizin ${sha:0:12}, depo ${gercek:0:12}) <<< imzalanmadi"; exit 1; }
    n=$((n+1))
done < "$T/atspkg.index"
[ $n -gt 0 ] || { echo "HATA: dizin bos"; exit 1; }

echo
echo "########## 2/3  IMZALANIYOR (parola sorulacak) ##########"
gpg --local-user "$FPR" --detach-sign -o "$T/atspkg.index.sig" "$T/atspkg.index" || { echo "HATA: imzalanamadi"; exit 1; }
gpgv --keyring $KN/depo-anahtari.gpg "$T/atspkg.index.sig" "$T/atspkg.index" >/dev/null 2>&1 \
    && echo "  imza: acik anahtarla dogrulandi" || { echo "HATA: imza dogrulanamadi"; exit 1; }

echo
echo "########## 3/3  YUKLEME (archive.org atasos-depo) ##########"
echo "  yuklenecek: atspkg.index.sig ($(stat -c%s "$T/atspkg.index.sig") bayt), $n paketlik dizin icin"
read -r -p "  Yuklensin mi? 'evet' yaz: " C
[ "$C" = evet ] || { echo "  iptal; hicbir sey yuklenmedi."; exit 0; }
(cd "$T" && "$IA" upload atasos-depo atspkg.index.sig --retries 5) || { echo "HATA: yukleme basarisiz"; exit 1; }
sleep 5
curl -fsSL -o "$T/geri.sig" "$DEPO/atspkg.index.sig" && gpgv --keyring $KN/depo-anahtari.gpg "$T/geri.sig" "$T/atspkg.index" >/dev/null 2>&1 \
    && echo "  TAMAM: $DEPO/atspkg.index.sig yayinda ve gecerli" \
    || echo "  Yuklendi; archive.org'da gorunmesi birkac dakika surebilir (sonra: atspkg guncelle ile dene)."
