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
SIRA=(openssl curl sudo expat zlib xz dbus libxml2 libxslt libpng libarchive libtasn1 gnutls glib nspr sqlite nss libcups python git libjpeg-turbo freetype linux atasos-xdg-open xdg-desktop-portal xdg-desktop-portal-kde fastfetch atasos-masaustu atasos-guncelleme)
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
# isaret: kurulum kancalari bunu gorunce GRUB/os-prober gibi sistem disi islerden kacinir (linux kancasi)
mkdir -p $K/run && : > $K/run/atasos-82-katman
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
    # makedepends (tarifte; atspkg okumaz): katmanda yoksa paketler/'deki en yeni dogrulanmis surumu once kur
    for md in $(bash -c '. "$1"; echo "${makedepends[@]}"' _ "$D/tarif"); do
        [ -d $K/var/lib/atspkg/db/$md ] && continue
        E=$(ls $P/paketler/$md-[0-9]*.atspkg.tar.zst 2>/dev/null | sort -V | tail -1)
        h=$(awk -v f="${E##*/}" '$2==f{print $1}' $P/paketler/SHA256SUMS)
        [ -n "$E" ] && [ -n "$h" ] && [ "$(sha256sum "$E" | cut -d' ' -f1)" = "$h" ] \
            || { echo "  HATA: $p icin derleme bagimliligi $md paketler/'de yok ya da dogrulanamadi"; exit 1; }
        cp -f "$E" $K/tmp/ && cr atspkg kur "/tmp/${E##*/}" > "$D/makedep-$md.log" 2>&1 \
            || { echo "  HATA: derleme bagimliligi ${E##*/} kurulamadi:"; tail -n 5 "$D/makedep-$md.log" | sed 's/^/    /'; exit 1; }
        rm -f "$K/tmp/${E##*/}"; echo "  derleme bagimliligi kuruldu: ${E##*/}"
    done
    # p5'te olmayan ama ISO'da/kanalda ESKI surumu olan paketler (nss 3.108, sqlite 3.49.1 ...): once eski dogrulanmis
    # paketi gecici katmana kur -> ABI denetimi gercek eski kutuphaneyle yapilir + v38 kullanicisinin yukseltme yolu denenir
    if [ ! -d $K/var/lib/atspkg/db/$p ]; then
        yv=$(bash -c '. "$1"; echo "$version-$release"' _ "$D/tarif")
        E=$(ls $P/paketler/$p-[0-9]*.atspkg.tar.zst 2>/dev/null | sort -V | tail -1)
        ev=${E##*/}; ev=${ev#$p-}; ev=${ev%.atspkg.tar.zst}
        if [ -n "$E" ] && [ "$ev" != "$yv" ] && [ "$(printf '%s\n%s\n' "$ev" "$yv" | sort -V | tail -1)" = "$yv" ]; then
            h=$(awk -v f="${E##*/}" '$2==f{print $1}' $P/paketler/SHA256SUMS)
            if [ -n "$h" ] && [ "$(sha256sum "$E" | cut -d' ' -f1)" = "$h" ]; then
                cp -f "$E" $K/tmp/ && cr atspkg kur "/tmp/${E##*/}" > "$D/eski-kurulum.log" 2>&1 \
                    || { echo "  HATA: eski ${E##*/} gecici katmana kurulamadi:"; tail -n 5 "$D/eski-kurulum.log" | sed 's/^/    /'; exit 1; }
                rm -f "$K/tmp/${E##*/}"
                echo "  once eski surum kuruldu (ABI + yukseltme denemesi): ${E##*/}"
            else echo "  UYARI: ${E##*/} SHA256SUMS ile tutmuyor; eski surum kurulmadi, ABI denetimi p5'e gore"; fi
        fi
    fi
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
    yasak=$(tar -tf "$F" | sed 's|^\./||' | grep -E '^(etc/sudoers|etc/sudo\.conf|etc/sudo_logsrvd\.conf|etc/ssl/openssl\.cnf|etc/passwd|etc/shadow|etc/group)$|^(etc/sudoers\.d|etc/ssl/certs|etc/dbus-1|tmp|mnt|root|home|var/lib/sudo|var/lib/dbus|run)(/|$)' || true)
    [ -z "$yasak" ] && echo "  $p: yasak yol yok" || { echo "  $p: YASAK YOL <<<"; echo "$yasak" | sed 's/^/      /'; H=1; }
    X=$(mktemp -d /run/atasos-paket.XXXX); tar -xf "$F" -C "$X"
    rp=$(find "$X" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c 'readelf -d "$1" 2>/dev/null | grep -E "R(UN)?PATH" | grep -c -E "/mnt/tarifler|/tmp|work/" >/dev/null && echo "$1"' _ {} \; | sed "s|$X/||")
    [ -z "$rp" ] && echo "  $p: derleme yolu sizintisi yok" || { echo "  $p: RPATH'te derleme yolu <<<"; echo "$rp" | sed 's/^/      /'; H=1; }
    rm -rf "$X"
    case $p in
        sudo) grep -qE '^-rws..x..x .* (\./)?usr/bin/sudo$' <<< "$L" && echo "  sudo: setuid root" || { echo "  sudo: setuid YOK <<<"; H=1; } ;;
        openssl) for y in usr/lib/libcrypto.so.3 usr/lib64/libcrypto.so.3 usr/lib/libssl.so.3 usr/lib64/libssl.so.3 usr/bin/openssl; do
                     grep -qE " (\./)?$y$" <<< "$L" || { echo "  openssl: $y YOK <<<"; H=1; }; done; echo "  openssl: lib + lib64 kopyalari var" ;;
        # launch-helper pakette setuid'siz 0700; root:messagebus 4110'u kurulum kancasi verir (tar sahipleri 0:0 paketler)
        dbus) grep -qE '^-rwx------ .* (\./)?usr/libexec/dbus-daemon-launch-helper$' <<< "$L" && echo "  dbus: launch-helper pakette 0700 (setuid'i kanca verir)" || { echo "  dbus: launch-helper izni beklenmedik <<<"; grep launch-helper <<< "$L" | sed 's/^/      /'; H=1; }
              tar -xOf "$F" .INSTALL 2>/dev/null | grep -q 'chmod 4110' && echo "  dbus: kurulum kancasi var" || { echo "  dbus: .INSTALL kancasi YOK <<<"; H=1; } ;;
        linux) KR=$(tar -tf "$F" | sed -n 's|^\(\./\)\{0,1\}boot/vmlinuz-||p' | head -1)
               for y in boot/vmlinuz-$KR boot/config-$KR boot/System.map-$KR usr/lib/modules/$KR/modules.dep usr/lib/modules/$KR/modules.builtin; do
                   grep -qE " (\./)?$y$" <<< "$L" || { echo "  linux: $y YOK <<<"; H=1; }; done
               grep -qE " (\./)?usr/lib/modules/$KR/(build|source)( |$)" <<< "$L" && { echo "  linux: build/source baglantisi pakette <<<"; H=1; }
               tar -xOf "$F" .INSTALL 2>/dev/null | grep -q 'grub-mkconfig' && echo "  linux: $KR, kanca (depmod + grub-mkconfig) var" || { echo "  linux: kanca YOK <<<"; H=1; } ;;
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
        xz)      v=$(cr xz --version 2>&1 | head -2 | tr '\n' ' '); echo "  xz: $v"; [ "$(grep -o '5\.8\.4' <<< "$v" | wc -l)" = 2 ] || { echo "  xz/liblzma 5.8.4 degil <<<"; H=1; }
                 c=$(cr sh -c 'echo atasos | xz -9e | xz -d && echo atasos | lzma | unlzma' 2>&1 | tr '\n' ' '); echo "  xz/lzma gidis-donus: $c"; [ "$c" = "atasos atasos " ] || H=1
                 c=$(cr python3 -c 'import lzma; print(lzma.decompress(lzma.compress(b"atasos")).decode())' 2>&1); echo "  python lzma: $c"; [ "$c" = atasos ] || H=1
                 c=$(cr kmod --version 2>&1 | grep -o '+XZ'); echo "  kmod (liblzma'ya bagli, modul yukleme): ${c:-XZ YOK}"; [ "$c" = +XZ ] || H=1 ;;
        dbus)    v=$(cr dbus-daemon --version 2>&1 | head -1); echo "  dbus: $v"; grep -q "1\.16\.4" <<< "$v" || H=1
                 # chroot ICINDE: grup adi atasOS'un /etc/group'undan (messagebus=18; Kubuntu'da 996, disaridan UNKNOWN gorunur)
                 c=$(cr stat -c '%a %U %G' /usr/libexec/dbus-daemon-launch-helper); echo "  launch-helper: $c (kanca sonrasi)"; [ "$c" = "4110 root messagebus" ] || H=1
                 c=$(cr dbus-run-session -- dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetId 2>&1 | grep -c string)
                 echo "  oturum veri yolu (dbus-run-session + dbus-send): $c"; [ "$c" = 1 ] || H=1
                 for k in '<user>messagebus</user>' '<listen>unix:path=/run/dbus/system_bus_socket</listen>' '<servicehelper>/usr/libexec/dbus-daemon-launch-helper</servicehelper>' '<pidfile>/run/dbus/pid</pidfile>'; do
                     grep -qF "$k" $K/usr/share/dbus-1/system.conf && grep -qF "$k" $A/usr/share/dbus-1/system.conf || { echo "  system.conf: $k farkli <<<"; H=1; }; done
                 echo "  system.conf: kullanici/soket/yardimci/pid eskisiyle ayni"
                 for f in /etc/dbus-1/system.d/wpa_supplicant.conf /etc/dbus-1/system.conf /var/lib/dbus/machine-id; do [ -e $K$f ] || [ -L $K$f ] || { echo "  $f kayboldu <<<"; H=1; }; done ;;
        python)  v=$(cr python3 --version 2>&1); echo "  python: $v"; [ "$v" = "Python 3.13.18" ] || H=1
                 c=$(cr python3 -c 'import ssl, lzma, bz2, zlib, ctypes, readline, curses, dbm.gnu, uuid, hashlib, pyexpat, sqlite3, decimal, json, venv
hashlib.sha3_256(); hashlib.blake2b(); ctypes.CDLL("libc.so.6")
c = sqlite3.connect(":memory:"); c.execute("create virtual table t using fts5(x)")
print("ok", ssl.OPENSSL_VERSION.split()[1], "sqlite", sqlite3.sqlite_version)' 2>&1); echo "  python standart moduller (ssl/lzma/ctypes/readline/curses/dbm/sqlite3 ...): $c"; grep -qE "^ok 3\.5\.[0-9]+ sqlite 3\.54\.1" <<< "$c" || H=1
                 c=$(cr python3 -c 'import yaml, markupsafe._speedups, mesonbuild, jinja2, mako; yaml.CLoader; print("ok")' 2>&1); echo "  site-packages C eklentileri (yaml, markupsafe) + meson/jinja2/mako (libxslt.py p5'te zaten bozuk: libxml2mod yok): $c"; [ "$c" = ok ] || H=1
                 c=$(cr sh -c 'pip3 --version | cut -d" " -f1-2; meson --version' 2>&1 | tr '\n' ' '); echo "  sistem pip + meson (pakete girmedi, calisiyor): $c"; grep -q "^pip 26" <<< "$c" || H=1 ;;
        git)     v=$(cr git --version 2>&1); echo "  git: $v"; [ "$v" = "git version 2.56.1" ] || H=1
                 c=$(cr sh -c 'd=$(mktemp -d) && cd $d && git init -q && git -c user.name=a -c user.email=a@b commit -q --allow-empty -m atasos && git log --format=%s; rm -rf $d' 2>&1); echo "  git init/commit/log: $c"; [ "$c" = atasos ] || H=1
                 c=$(cr sh -c 'git ls-remote https://git.kernel.org/pub/scm/git/git.git refs/heads/master 2>&1 | grep -c refs/heads/master'); echo "  git https (git.kernel.org ls-remote, curl'lu; p5'te calismiyordu): $c"; [ "$c" = 1 ] || H=1 ;;
        libjpeg-turbo) v=$(cr djpeg -version 2>&1 | head -1); echo "  libjpeg-turbo: $v"; grep -q "3\.2\.1" <<< "$v" || H=1
                 c=$(cr sh -c 'd=$(mktemp -d) && printf "P6\n2 2\n255\n\377\0\0\0\377\0\0\0\377\377\377\377" > $d/a.ppm && cjpeg -quality 95 $d/a.ppm > $d/a.jpg && djpeg $d/a.jpg | head -c 2; rm -rf $d' 2>&1); echo "  cjpeg/djpeg gidis-donus: $c"; [ "$c" = P6 ] || H=1
                 c=$(cr python3 -c 'import ctypes; l=ctypes.CDLL("libturbojpeg.so.0"); l.tj3Init; print("ok")' 2>&1); echo "  libturbojpeg (tj3 API): $c"; [ "$c" = ok ] || H=1 ;;
        freetype) v=$(cr freetype-config --ftversion 2>&1); echo "  freetype: $v"; [ "$v" = 2.15.0 ] || H=1
                 c=$(cr python3 -c 'import ctypes
f = ctypes.CDLL("libfreetype.so.6"); lib = ctypes.c_void_p(); f.FT_Init_FreeType(ctypes.byref(lib))
a, b, c = ctypes.c_int(), ctypes.c_int(), ctypes.c_int(); f.FT_Library_Version(lib, ctypes.byref(a), ctypes.byref(b), ctypes.byref(c)); print("%d.%d.%d" % (a.value, b.value, c.value))' 2>&1); echo "  libfreetype calisma ani surumu: $c"; [ "$c" = 2.15.0 ] || H=1
                 c=$(cr sh -c 'f=$(find /usr/share/fonts -name "*.ttf" -o -name "*.otf" | head -1); fc-scan --format "%{family}\n" "$f" | head -1' 2>&1); echo "  fontconfig fc-scan (freetype ile yazi tipi ayristirma): $c"; [ -n "$c" ] || H=1 ;;
        linux)   KR=6.18.64-atas7
                 c=$(cr sh -c "dd if=/boot/vmlinuz-$KR bs=1 skip=514 count=4 2>/dev/null; echo; strings /boot/vmlinuz-$KR | grep -m1 -o '^$KR'" 2>&1 | tr '\n' ' '); echo "  vmlinuz: $c"; [ "$c" = "HdrS $KR " ] || H=1
                 c=$(cr modinfo -k $KR -F vermagic i915 2>&1); echo "  i915 vermagic: $c"; grep -q "^$KR " <<< "$c" || H=1
                 c=$(cr modprobe -S $KR --show-depends amdgpu 2>&1 | grep -c '^insmod'); echo "  amdgpu bagimlilik zinciri (modules.dep): $c modul"; [ "${c:-0}" -ge 2 ] || H=1
                 c=$(cr sh -c "grep -cE '^CONFIG_(BLK_DEV_NVME|EXT4_FS|DRM_SIMPLEDRM|FRAMEBUFFER_CONSOLE|DEVTMPFS_MOUNT|EFI_STUB)=y' /boot/config-$KR"); echo "  acilis suruculeri gomulu (6/6): $c"; [ "$c" = 6 ] || H=1
                 [ -e $K/boot/vmlinuz-6.16.1-atas6 ] && echo "  eski cekirdek atas6 yerinde (yedek)" || { echo "  atas6 kayboldu <<<"; H=1; }
                 # nouveau kurali: modprobe 'install' ile yonlendiriyor mu + karar mantigi (sahte sysfs; modprobe CAGRILMAZ)
                 c=$(cr modprobe -c 2>/dev/null | grep -c '^install nouveau /usr/lib/atasos/nouveau-yukle'); echo "  modprobe yapilandirmasi: install nouveau kurali $c"; [ "$c" = 1 ] || H=1
                 c=$(cr sh -c 'T=$(mktemp -d); m(){ mkdir -p $T/$1/bus/pci/devices/x; echo $2 > $T/$1/bus/pci/devices/x/vendor; echo $3 > $T/$1/bus/pci/devices/x/class; }; m h 0x10de 0x030200; m v 0x10de 0x030000; for s in h v; do ATASOS_SYSFS=$T/$s ATASOS_DENEME=1 /usr/lib/atasos/nouveau-yukle; done | tr "\n" " "; rm -rf $T'); echo "  nouveau karari (hibrit 3D denetleyici / VGA NVIDIA): $c"; [ "$c" = "atla yukle " ] || H=1
                 grep -q 'GRUB atlandi' /veri/atasos-paket/tarifler/linux/kurulum.log && echo "  kanca: derleme katmaninda GRUB'a dokunmadi" || { echo "  kanca GRUB'a dokunmus olabilir <<<"; H=1; } ;;
        nspr)    v=$(cr nspr-config --version 2>&1); echo "  nspr: $v"; case "$v" in 4.41|4.41.0) ;; *) H=1;; esac ;;
        sqlite)  v=$(cr sqlite3 --version 2>&1 | cut -d' ' -f1); echo "  sqlite3: $v"; [ "$v" = 3.54.1 ] || H=1
                 c=$(cr sqlite3 :memory: "create virtual table t using fts5(x); insert into t values('atasos'); select x from t where t match 'atasos';" 2>&1)
                 echo "  sqlite fts5 sorgusu: $c"; [ "$c" = atasos ] || H=1 ;;
        nss)     v=$(cr nss-config --version 2>&1); echo "  nss: $v"; case "$v" in 3.134|3.134.0) ;; *) H=1;; esac
                 c=$(cr sh -c 'd=$(mktemp -d) && certutil -N -d sql:$d --empty-password && certutil -L -d sql:$d >/dev/null && ls $d/cert9.db >/dev/null && echo ok; rm -rf $d' 2>&1)
                 echo "  certutil sql: veritabani (softokn3 + sistem sqlite): $c"; [ "$c" = ok ] || H=1 ;;
        libcups) c=$(cr python3 -c 'import ctypes; l=ctypes.CDLL("libcups.so.2"); l.cupsGetDefault; print("ok")' 2>&1)
                 echo "  libcups.so.2 yuklenip sembol bulundu: $c"; [ "$c" = ok ] || H=1
                 c=$(cr sh -c 'strings /usr/lib/libcups.so.2 | grep -m1 -o "CUPS/2\.4\.[0-9]*"'); echo "  libcups surumu: $c"; [ "$c" = CUPS/2.4.20 ] || H=1 ;;
        atasos-xdg-open) cr sh -n /usr/bin/xdg-open && [ -x $K/usr/bin/xdg-open ] && echo "  xdg-open: calistirilabilir, sozdizimi tamam" || { echo "  xdg-open sorunlu <<<"; H=1; } ;;
        xdg-desktop-portal) cr /usr/libexec/xdg-desktop-portal --help >/dev/null 2>&1 && echo "  xdg-desktop-portal: calisiyor (--help)" || { echo "  xdg-desktop-portal calismiyor <<<"; H=1; }
                 for f in /usr/share/dbus-1/services/org.freedesktop.portal.Desktop.service /usr/lib/systemd/user/xdg-desktop-portal.service; do [ -e $K$f ] && echo "  portal: $f var" || { echo "  portal: $f YOK <<<"; H=1; }; done ;;
        atasos-masaustu) for f in /usr/share/plasma/look-and-feel/org.atasos.masaustu/contents/layouts/org.kde.plasma.desktop-layout.js \
                     /usr/share/plasma/plasmoids/org.atasos.baslat/contents/ui/main.qml /usr/share/plasma/plasmoids/org.atasos.hosgeldin/contents/ui/main.qml \
                     /usr/share/plasma/desktoptheme/atasos/colors /usr/share/color-schemes/AtasOS.colors /etc/xdg/autostart/atasos-hosgeldin.desktop /etc/xdg/fastfetch/config.jsonc /usr/share/atasos/fastfetch/atasos.txt /etc/xdg/plasma-workspace/env/atasos-yazi-dpi.sh; do
                     [ -s $K$f ] && echo "  masaustu: $f var" || { echo "  masaustu: $f YOK <<<"; H=1; }; done
                 cr sh -n /usr/bin/atasos-hosgeldin && [ -n "$(cr /usr/bin/atasos-hosgeldin --durum)" ] && echo "  atasos-hosgeldin: calisiyor" || { echo "  atasos-hosgeldin sorunlu <<<"; H=1; }
                 [ -x $K/usr/bin/fastfetch ] && { c=$(cr fastfetch --pipe -s os 2>&1 | head -1); echo "  fastfetch atasOS ayariyla: $c"; grep -q "atasOS" <<< "$c" || H=1; } ;;
        libxml2) v=$(cr xmllint --version 2>&1 | head -1); echo "  libxml2: $v"; grep -q "21309" <<< "$v" || H=1
                 c=$(cr sh -c 'printf "<a><b>atasos</b></a>" | xmllint --xpath "string(/a/b)" -' 2>&1); echo "  xmllint xpath: $c"; [ "$c" = atasos ] || H=1 ;;
        libpng)  v=$(cr libpng-config --version 2>&1); echo "  libpng: $v"; [ "$v" = 1.6.59 ] || H=1
                 c=$(cr sh -c 'f=$(find /usr/share/icons -name "*.png" -size +1k | head -1); pngfix --quiet "$f" && echo ok' 2>&1); echo "  pngfix (gercek PNG): $c"; [ "$c" = ok ] || H=1 ;;
        libarchive) v=$(cr bsdtar --version 2>&1 | head -1); echo "  bsdtar: $v"; grep -q "libarchive 3.8.11" <<< "$v" || H=1
                 for oz in zlib liblzma bz2lib libzstd liblz4; do grep -q "$oz" <<< "$v" || { echo "  bsdtar: $oz destegi YOK <<<"; H=1; }; done
                 c=$(cr sh -c 'd=$(mktemp -d) && cd $d && echo atasos > a && bsdtar --zstd -cf a.tar.zst a && rm a && bsdtar -xf a.tar.zst && cat a; rm -rf $d' 2>&1); echo "  bsdtar zstd gidis-donus: $c"; [ "$c" = atasos ] || H=1 ;;
        libxslt) v=$(cr xsltproc --version 2>&1 | head -1); echo "  libxslt: $v"; grep -q "libxslt 10143" <<< "$v" || H=1
                 c=$(cr sh -c 'd=$(mktemp -d) && printf "<a><b>atasos</b></a>" > $d/x.xml && printf "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\"><xsl:output method=\"text\"/><xsl:template match=\"/\"><xsl:value-of select=\"/a/b\"/></xsl:template></xsl:stylesheet>" > $d/s.xsl && xsltproc $d/s.xsl $d/x.xml; rm -rf $d' 2>&1); echo "  xsltproc donusum: $c"; [ "$c" = atasos ] || H=1 ;;
        libtasn1) v=$(cr asn1Parser --version 2>&1 | head -1); echo "  libtasn1: $v"; grep -q "4\.21\.0" <<< "$v" || H=1 ;;
        gnutls)  v=$(cr gnutls-cli --version 2>&1 | head -1); echo "  gnutls: $v"; grep -q "3\.8\.14" <<< "$v" || H=1
                 cmp -s $K/usr/lib/libgnutls.so.30 $K/usr/lib64/libgnutls.so.30 && echo "  gnutls: lib ve lib64 kopyalari ayni" || { echo "  gnutls: lib64 kopyasi farkli <<<"; H=1; }
                 c=$(cr sh -c 'gnutls-cli --port 443 archive.org < /dev/null 2>&1 | grep -c "Handshake was completed"'); echo "  gnutls TLS (archive.org, sertifika dogrulamali): $c"; [ "$c" = 1 ] || H=1 ;;
        glib)    v=$(cr gsettings --version 2>&1); echo "  glib (gsettings): $v"; [ "$v" = 2.82.5 ] || H=1
                 c=$(cr sh -c 'gio info / 2>&1 | grep -c "standard::type"'); echo "  gio info /: $c alan"; [ "${c:-0}" -ge 1 ] || H=1
                 cr glib-compile-schemas --strict --dry-run /usr/share/glib-2.0/schemas >/dev/null 2>&1 && echo "  glib-compile-schemas: semalar gecerli" || { echo "  glib-compile-schemas HATA <<<"; H=1; } ;;
        atasos-guncelleme) cr bash -n /usr/bin/atasos-guncelle && cr bash -n /usr/bin/atasos-guncelleme-denetle && [ -s $K/etc/xdg/autostart/atasos-guncelleme-denetle.desktop ] \
                     && echo "  guncelleyici + gunluk denetleyici: sozdizimi tamam, autostart var" || { echo "  guncelleyici/denetleyici sorunlu <<<"; H=1; }
                 for t in xz dbus nspr sqlite nss libcups python git libjpeg-turbo freetype linux; do grep -qx "$t" $K/usr/share/atasos-guncelleme/temel.list || { echo "  temel.list: $t YOK <<<"; H=1; }; done
                 [ "$(grep -nx nspr $K/usr/share/atasos-guncelleme/temel.list | cut -d: -f1)" -lt "$(grep -nx nss $K/usr/share/atasos-guncelleme/temel.list | cut -d: -f1)" ] \
                     && echo "  temel.list: 6. parti var (nspr/sqlite nss'ten once)" || { echo "  temel.list: sira yanlis <<<"; H=1; } ;;
        fastfetch) v=$(cr fastfetch --version 2>&1 | head -1); echo "  fastfetch: $v"; grep -q "2\.71\.0" <<< "$v" || H=1
                 c=$(cr fastfetch --pipe --logo none -s os:kernel 2>&1 | head -2 | tr "\n" " "); echo "  fastfetch cikti: $c"; grep -q "Kernel" <<< "$c" || H=1 ;;
        xdg-desktop-portal-kde) for f in /usr/share/xdg-desktop-portal/portals/kde.portal /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kde.service; do
                     [ -e $K$f ] && echo "  portal-kde: $f var" || { echo "  portal-kde: $f YOK <<<"; H=1; }; done ;;
    esac
done
ek=$(cr sh -c 'for b in /usr/bin/openssl /usr/bin/curl /usr/bin/sudo /usr/lib/sudo/sudoers.so /usr/lib/libcurl.so.4 /usr/bin/xmlwf /usr/lib/libexpat.so.1 /usr/lib/libz.so.1 /usr/lib/libnspr4.so /usr/lib/libnss3.so /usr/lib/libsoftokn3.so /usr/bin/certutil /usr/bin/sqlite3 /usr/lib/libsqlite3.so.0 /usr/lib/libcups.so.2 /usr/libexec/xdg-desktop-portal /usr/libexec/xdg-document-portal /usr/libexec/xdg-permission-store /usr/libexec/xdg-desktop-portal-kde /usr/bin/fastfetch /usr/bin/xmllint /usr/lib/libxml2.so.2 /usr/lib/libpng16.so.16 /usr/bin/pngfix /usr/lib/libarchive.so.13 /usr/bin/bsdtar /usr/bin/xsltproc /usr/lib/libxslt.so.1 /usr/lib/libgnutls.so.30 /usr/bin/gnutls-cli /usr/lib64/libglib-2.0.so.0 /usr/lib64/libgio-2.0.so.0 /usr/bin/gsettings /usr/bin/plasmashell /usr/bin/xz /usr/lib/liblzma.so.5 /usr/bin/kmod /usr/lib/systemd/systemd /usr/bin/dbus-daemon /usr/lib/libdbus-1.so.3 /usr/libexec/dbus-daemon-launch-helper /usr/bin/NetworkManager /usr/bin/python3.13 /usr/lib/libpython3.13.so.1.0 /usr/bin/git /usr/libexec/git-core/git-remote-https /usr/lib/libjpeg.so.62 /usr/lib/libturbojpeg.so.0 /usr/lib/libfreetype.so.6 /usr/bin/fc-list /usr/lib/libharfbuzz.so.0 /usr/lib/python3.13/site-packages/libxsltmod.so /usr/lib/python3.13/site-packages/yaml/_yaml.cpython-313-x86_64-linux-gnu.so; do [ -e $b ] && ldd $b; done 2>/dev/null | grep "not found" | sort -u')
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
