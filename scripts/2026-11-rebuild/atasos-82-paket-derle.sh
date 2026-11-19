#!/usr/bin/env bash
# atasos-82: guncelleme kanali paketlerini (atspkg .atspkg.tar.zst) atasOS'un KENDI ortaminda derler ve dener.
#   - p5 SALT-OKUNUR baglanir; uzerine gecici bir overlay (/veri/atasos-paket/kok) kurulur. p5'e HICBIR SEY yazilmaz.
#   - kaynak arsivleri /veri/atasos-paket/kaynak/DOGRULANMIS.txt'teki sha256 ile denetlenir (imzalari Claude dogruladi)
#   - her tarif chroot icinde 'atspkg derle' ile paketlenir (atspkg 0.3.0)
#   - paket denetimi: yasak yollar (/etc/sudoers, /etc/ssl/openssl.cnf ...), setuid, derleme yolu sizintisi (RPATH)
#   - DUMAN TESTI: paketler ayni GECICI katmana 'atspkg kur' ile kurulur, sonra openssl/curl/sudo calistirilir,
#     curl ile archive.org'a TLS baglantisi denenir. Katman bir sonraki calismada silinir.
#   - cikti: /veri/atasos-paket/paketler/*.atspkg.tar.zst (+ sha256)
# Kullanim (Konsole'da): sudo bash /home/eren/atasos-82-paket-derle.sh [openssl curl sudo]
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi calisiyor. Hicbir sey yapilmadi."; exit 1; }
P=/veri/atasos-paket
A=/mnt/atasos
K=$P/kok; U=$P/ust; W=$P/is
KN=/veri/atasos-iso/kanal
LOG=$P/derleme-$(date +%Y%m%d-%H%M).log
PAKETLER=("$@"); [ ${#PAKETLER[@]} -gt 0 ] || PAKETLER=(openssl curl sudo)
# bagimlilik sirasi: her paket derlenir derlenmez gecici katmana kurulur, sonrakiler ona karsi derlenir (nss -> nspr+sqlite)
SIRA=(openssl curl sudo expat zlib nspr sqlite nss libcups atasos-xdg-open xdg-desktop-portal xdg-desktop-portal-kde fastfetch atasos-masaustu atasos-guncelleme)
S2=(); for s in "${SIRA[@]}"; do for p in "${PAKETLER[@]}"; do [ "$p" = "$s" ] && S2+=("$p"); done; done
for p in "${PAKETLER[@]}"; do [[ " ${SIRA[*]} " == *" $p "* ]] || S2+=("$p"); done
PAKETLER=("${S2[@]}")
for p in "${PAKETLER[@]}"; do
    case $p in nss) for d in nspr sqlite; do [[ " ${PAKETLER[*]} " == *" $d "* ]] || { echo "HATA: nss icin $d de ayni calismada derlenmeli (sira: nspr sqlite nss)"; exit 1; }; done ;; esac
done
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once ayir. Hicbir sey yapilmadi."; exit 1; }
[ "$(sha256sum $KN/atspkg-0.3.0 2>/dev/null | cut -d' ' -f1)" = 9fd185ccca487009508847ce0b3ac15efeabb11dc4c012e62b93db585b634049 ] \
    || { echo "HATA: $KN/atspkg-0.3.0 yok/bozuk"; exit 1; }
[ -s $KN/depo-anahtari.gpg ] || { echo "HATA: $KN/depo-anahtari.gpg yok"; exit 1; }

# kaynak denetimi (agir isten once)
declare -A KAYNAK
for p in "${PAKETLER[@]}"; do
    T=$P/tarifler/$p/tarif
    [ -f "$T" ] || { echo "HATA: tarif yok: $T"; exit 1; }
    s=$(bash -c '. "$1"; printf "%s\n" "${source[@]}"' _ "$T") || { echo "HATA: tarif okunamadi: $T"; exit 1; }
    for f in $s; do
        case "$f" in *://*) echo "HATA: $p tarifi kaynagi internetten indiriyor ($f); dogrulanmis yerel arsiv olmali"; exit 1;; esac
        h=$(awk -v f="$f" '$2==f{print $1}' $P/kaynak/DOGRULANMIS.txt)
        [ -n "$h" ] && [ "$(sha256sum "$P/kaynak/$f" 2>/dev/null | cut -d' ' -f1)" = "$h" ] \
            || { echo "HATA: $f DOGRULANMIS.txt'te yok ya da sha256 tutmuyor. Hicbir sey yapilmadi."; exit 1; }
        KAYNAK[$p]+="$f "
    done
done

mkdir -p $A $K $P/paketler
mount -o ro /dev/nvme0n1p5 $A || { echo "HATA: p5 baglanamadi"; exit 1; }
temizle(){
    cd /
    for m in $K/mnt/tarifler $K/tmp $K/sys $K/proc $K/dev/pts $K/dev $K; do mountpoint -q "$m" && umount "$m"; done
    umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"
    chown -R 1000:1000 $P/paketler $P/tarifler "$LOG" 2>/dev/null; true; }
trap temizle EXIT
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS 82: paket derleme  ($(date '+%F %T'))  paketler: ${PAKETLER[*]} ##########"

echo
echo "########## 1/4  GECICI KATMAN ##########"
rm -rf "$U" "$W"; mkdir -p "$U" "$W"
mount -t overlay overlay -o lowerdir=$A,upperdir=$U,workdir=$W $K || { echo "HATA: overlay"; exit 1; }
install -m 755 $KN/atspkg-0.3.0 $K/usr/bin/atspkg
install -d $K/usr/share/atspkg; install -m 644 $KN/depo-anahtari.gpg $K/usr/share/atspkg/depo-anahtari.gpg
rm -f $K/etc/resolv.conf; cat /etc/resolv.conf > $K/etc/resolv.conf
mkdir -p $K/mnt/tarifler
mount --bind /dev $K/dev; mount --bind /dev/pts $K/dev/pts; mount -t proc proc $K/proc; mount -t sysfs sysfs $K/sys
mount -t tmpfs -o size=6G tmpfs $K/tmp
mount --bind $P/tarifler $K/mnt/tarifler
cr(){ chroot $K /usr/bin/env -i HOME=/root TERM=${TERM:-dumb} LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }
echo "  katman: $K (alt: p5 salt-okunur, ust: $U)  atspkg: $(cr atspkg surum)"

echo
echo "########## 2/4  DERLEME ##########"
declare -A DOSYA
for p in "${PAKETLER[@]}"; do
    D=$P/tarifler/$p
    for f in ${KAYNAK[$p]}; do cp -f "$P/kaynak/$f" "$D/$f"; done
    rm -f "$D"/*.atspkg.tar.zst
    B=$(date +%s)
    echo "== $p derleniyor (kayit: $D/derleme.log)"
    if ! cr atspkg derle /mnt/tarifler/$p > "$D/derleme.log" 2>&1; then
        echo "  HATA: $p derlenemedi. Son satirlar:"; grep -E "error|Error|hata" "$D/derleme.log" | tail -n 10 | sed 's/^/    /'
        tail -n 8 "$D/derleme.log" | sed 's/^/    /'; exit 1
    fi
    DOSYA[$p]=$(ls "$D"/$p-*.atspkg.tar.zst 2>/dev/null | head -1)
    [ -f "${DOSYA[$p]}" ] || { echo "  HATA: $p paketi olusmadi"; exit 1; }
    rm -rf "$D/work"
    echo "  tamam: ${DOSYA[$p]##*/} ($(du -h "${DOSYA[$p]}" | cut -f1), $(( ($(date +%s)-B)/60 )) dk)"
    # sonraki paketler buna karsi derlensin diye HEMEN gecici katmana kur (p5'e dokunmaz)
    [ "$p" = sudo ] && { chown root:root $K/etc/sudoers && chmod 0440 $K/etc/sudoers; }
    cr atspkg kur "/mnt/tarifler/$p/${DOSYA[$p]##*/}" > "$D/kurulum.log" 2>&1 \
        || { echo "  HATA: $p gecici katmana kurulamadi:"; tail -n 8 "$D/kurulum.log" | sed 's/^/    /'; exit 1; }
    echo "  gecici katmana kuruldu: $p"
done

echo
echo "########## 3/4  PAKET DENETIMI ##########"
H=0
for p in "${PAKETLER[@]}"; do
    F=${DOSYA[$p]}; L=$(tar -tvf "$F")
    yasak=$(tar -tf "$F" | sed 's|^\./||' | grep -E '^(etc/sudoers|etc/sudo\.conf|etc/sudo_logsrvd\.conf|etc/ssl/openssl\.cnf|etc/passwd|etc/shadow|etc/group)$|^(etc/sudoers\.d|etc/ssl/certs|tmp|mnt|root|home|var/lib/sudo|run)(/|$)' || true)
    [ -z "$yasak" ] && echo "  $p: yasak yol yok" || { echo "  $p: YASAK YOL <<<"; echo "$yasak" | sed 's/^/      /'; H=1; }
    X=$(mktemp -d /run/atasos-paket.XXXX); tar -xf "$F" -C "$X"
    rp=$(find "$X" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c 'readelf -d "$1" 2>/dev/null | grep -E "R(UN)?PATH" | grep -c -E "/mnt/tarifler|/tmp|work/" >/dev/null && echo "$1"' _ {} \; | sed "s|$X/||")
    [ -z "$rp" ] && echo "  $p: derleme yolu sizintisi yok" || { echo "  $p: RPATH'te derleme yolu <<<"; echo "$rp" | sed 's/^/      /'; H=1; }
    rm -rf "$X"
    case $p in
        sudo) grep -qE '^-rws..x..x .* (\./)?usr/bin/sudo$' <<< "$L" && echo "  sudo: setuid root" || { echo "  sudo: setuid YOK <<<"; H=1; } ;;
        openssl) for y in usr/lib/libcrypto.so.3 usr/lib64/libcrypto.so.3 usr/lib/libssl.so.3 usr/lib64/libssl.so.3 usr/bin/openssl; do
                     grep -qE " (\./)?$y$" <<< "$L" || { echo "  openssl: $y YOK <<<"; H=1; }; done; echo "  openssl: lib + lib64 kopyalari var" ;;
    esac
done
[ $H -eq 0 ] || { echo "  DURDU: paket denetimi basarisiz."; exit 1; }

echo
echo "########## 4/4  DUMAN TESTI (yalniz gecici katmanda) ##########"
# p5 (gelistirme sistemi) /etc/sudoers 0440 degil; ISO ve kurulu sistemlerde 0440 -> gecici katmanda kurulu sistemi taklit et
chown root:root $K/etc/sudoers && chmod 0440 $K/etc/sudoers
# paketler derleme adiminda zaten gecici katmana kuruldu
for p in "${PAKETLER[@]}"; do
    case $p in
        openssl) v=$(cr openssl version 2>&1); echo "  openssl version: $v"; grep -q "^OpenSSL 3.5.9" <<< "$v" || H=1
                 for so in /usr/lib/libcrypto.so.3 /usr/lib64/libcrypto.so.3; do cr sh -c "strings $so | grep -m1 '^OpenSSL 3'" | sed "s|^|  $so: |"; done ;;
        curl)    v=$(cr curl --version 2>&1 | head -1); echo "  curl: $v"; grep -q "^curl 8.23.0" <<< "$v" || H=1
                 c=$(cr curl -sSL -o /dev/null -w '%{http_code}' https://archive.org/download/atasos-depo/atspkg.index 2>&1)
                 echo "  curl https://archive.org (TLS dogrulamali): $c"; [ "$c" = 200 ] || H=1 ;;
        expat)   v=$(cr xmlwf -v 2>&1 | head -1); echo "  expat: $v"; grep -q "expat_2.10.0" <<< "$v" || H=1
                 p=$(cr python3 -c 'import pyexpat; print(pyexpat.EXPAT_VERSION)' 2>&1); echo "  python pyexpat: $p (bilgi; python kendi expat'ini gomulu kullaniyor olabilir)" ;;
        zlib)    p=$(cr python3 -c 'import zlib; print(zlib.ZLIB_RUNTIME_VERSION)' 2>&1); echo "  zlib (python calisma ani): $p"; [ "$p" = 1.3.2 ] || H=1
                 c=$(cr sh -c 'echo atasos | gzip | gzip -d' 2>&1); echo "  gzip gidis-donus: $c"; [ "$c" = atasos ] || H=1 ;;
        sudo)    v=$(cr sudo -V 2>&1 | head -1); echo "  sudo: $v"; grep -q "1.9.17p2" <<< "$v" || H=1
                 cr sudo -V 2>&1 | grep -q -- '--without-pam' && echo "  sudo: PAM'siz (ozgun gibi)" || { echo "  sudo: --without-pam YOK <<<"; H=1; }
                 cr visudo -c 2>&1 | sed 's/^/  visudo: /' ;;
        nspr)    v=$(cr nspr-config --version 2>&1); echo "  nspr: $v"; case "$v" in 4.36|4.36.0) ;; *) H=1;; esac ;;
        sqlite)  v=$(cr sqlite3 --version 2>&1 | cut -d' ' -f1); echo "  sqlite3: $v"; [ "$v" = 3.49.1 ] || H=1
                 c=$(cr sqlite3 :memory: "create virtual table t using fts5(x); insert into t values('atasos'); select x from t where t match 'atasos';" 2>&1)
                 echo "  sqlite fts5 sorgusu: $c"; [ "$c" = atasos ] || H=1 ;;
        nss)     v=$(cr nss-config --version 2>&1); echo "  nss: $v"; case "$v" in 3.108|3.108.0) ;; *) H=1;; esac
                 c=$(cr sh -c 'd=$(mktemp -d) && certutil -N -d sql:$d --empty-password && certutil -L -d sql:$d >/dev/null && ls $d/cert9.db >/dev/null && echo ok; rm -rf $d' 2>&1)
                 echo "  certutil sql: veritabani (softokn3 + sistem sqlite): $c"; [ "$c" = ok ] || H=1 ;;
        libcups) c=$(cr python3 -c 'import ctypes; l=ctypes.CDLL("libcups.so.2"); l.cupsGetDefault; print("ok")' 2>&1)
                 echo "  libcups.so.2 yuklenip sembol bulundu: $c"; [ "$c" = ok ] || H=1 ;;
        atasos-xdg-open) cr sh -n /usr/bin/xdg-open && [ -x $K/usr/bin/xdg-open ] && echo "  xdg-open: calistirilabilir, sozdizimi tamam" || { echo "  xdg-open sorunlu <<<"; H=1; } ;;
        xdg-desktop-portal) cr /usr/libexec/xdg-desktop-portal --help >/dev/null 2>&1 && echo "  xdg-desktop-portal: calisiyor (--help)" || { echo "  xdg-desktop-portal calismiyor <<<"; H=1; }
                 for f in /usr/share/dbus-1/services/org.freedesktop.portal.Desktop.service /usr/lib/systemd/user/xdg-desktop-portal.service; do [ -e $K$f ] && echo "  portal: $f var" || { echo "  portal: $f YOK <<<"; H=1; }; done ;;
        atasos-masaustu) for f in /usr/share/plasma/look-and-feel/org.atasos.masaustu/contents/layouts/org.kde.plasma.desktop-layout.js \
                     /usr/share/plasma/plasmoids/org.atasos.baslat/contents/ui/main.qml /usr/share/plasma/plasmoids/org.atasos.hosgeldin/contents/ui/main.qml \
                     /usr/share/plasma/desktoptheme/atasos/colors /usr/share/color-schemes/AtasOS.colors /etc/xdg/autostart/atasos-hosgeldin.desktop /etc/xdg/fastfetch/config.jsonc /usr/share/atasos/fastfetch/atasos.txt /etc/xdg/plasma-workspace/env/atasos-yazi-dpi.sh; do
                     [ -s $K$f ] && echo "  masaustu: $f var" || { echo "  masaustu: $f YOK <<<"; H=1; }; done
                 cr sh -n /usr/bin/atasos-hosgeldin && [ -n "$(cr /usr/bin/atasos-hosgeldin --durum)" ] && echo "  atasos-hosgeldin: calisiyor" || { echo "  atasos-hosgeldin sorunlu <<<"; H=1; }
                 [ -x $K/usr/bin/fastfetch ] && { c=$(cr fastfetch --pipe -s os 2>&1 | head -1); echo "  fastfetch atasOS ayariyla: $c"; grep -q "atasOS" <<< "$c" || H=1; } ;;
        fastfetch) v=$(cr fastfetch --version 2>&1 | head -1); echo "  fastfetch: $v"; grep -q "2\.71\.0" <<< "$v" || H=1
                 c=$(cr fastfetch --pipe --logo none -s os:kernel 2>&1 | head -2 | tr "\n" " "); echo "  fastfetch cikti: $c"; grep -q "Kernel" <<< "$c" || H=1 ;;
        xdg-desktop-portal-kde) for f in /usr/share/xdg-desktop-portal/portals/kde.portal /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kde.service; do
                     [ -e $K$f ] && echo "  portal-kde: $f var" || { echo "  portal-kde: $f YOK <<<"; H=1; }; done ;;
    esac
done
ek=$(cr sh -c 'for b in /usr/bin/openssl /usr/bin/curl /usr/bin/sudo /usr/lib/sudo/sudoers.so /usr/lib/libcurl.so.4 /usr/bin/xmlwf /usr/lib/libexpat.so.1 /usr/lib/libz.so.1 /usr/lib/libnspr4.so /usr/lib/libnss3.so /usr/lib/libsoftokn3.so /usr/bin/certutil /usr/bin/sqlite3 /usr/lib/libsqlite3.so.0 /usr/lib/libcups.so.2 /usr/libexec/xdg-desktop-portal /usr/libexec/xdg-document-portal /usr/libexec/xdg-permission-store /usr/libexec/xdg-desktop-portal-kde /usr/bin/fastfetch; do [ -e $b ] && ldd $b; done 2>/dev/null | grep "not found" | sort -u')
[ -z "$ek" ] && echo "  eksik kutuphane yok" || { echo "  EKSIK KUTUPHANE <<<"; echo "$ek" | sed 's/^/    /'; H=1; }
cr atspkg listele 2>&1 | sed 's/^/  kurulu: /'
[ $H -eq 0 ] || { echo "  DURDU: duman testi basarisiz; paketler yayinlanmamali."; exit 1; }

for p in "${PAKETLER[@]}"; do mv -f "${DOSYA[$p]}" $P/paketler/; done
(cd $P/paketler && sha256sum *.atspkg.tar.zst > SHA256SUMS)
echo
echo "########## OZET ##########"
sed 's/^/  /' $P/paketler/SHA256SUMS
echo "  Paketler: $P/paketler  | kayit: $LOG"
echo "  Sonraki adim: Claude sanal makinede v36 kurulu sisteme kurup dener; sonra yayin (imzali dizin)."
