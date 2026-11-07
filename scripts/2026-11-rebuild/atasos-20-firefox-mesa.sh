#!/usr/bin/env bash
# A) Mozilla'nin resmi Firefox paketini atasOS /opt/firefox'a kur (SHA512 dogrulamali).
# B) Mesa'yi iris ile derlemek icin gerekenler var mi - SADECE RAPOR.
# Kullanim: sudo bash /home/eren/atasos-20-firefox-mesa.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
T=/home/eren/atas3-loglar/indirme
mkdir -p $A "$T"
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi

echo "########## A1  FIREFOX SURUMU ##########"
U=$(curl -sSIL -o /dev/null -w '%{url_effective}' 'https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=tr')
V=$(echo "$U" | grep -oE 'releases/[0-9][0-9.]*[0-9]' | cut -d/ -f2)
F=$(basename "$U")
echo "  adres : $U"
echo "  surum : ${V:-BULUNAMADI}"
echo "  dosya : $F"
case "$U" in https://download-installer.cdn.mozilla.net/*|https://archive.mozilla.org/*|https://ftp.mozilla.org/*) ;;
    *) echo "  HATA: beklenmeyen indirme adresi, iptal."; exit 1 ;; esac
[ -n "$V" ] || { echo "  HATA: surum okunamadi"; exit 1; }

echo
echo "########## A2  INDIRME + SHA512 DOGRULAMA ##########"
curl -sSfL -o "$T/$F" "$U" || { echo "  HATA: indirilemedi"; exit 1; }
curl -sSfL -o "$T/SHA512SUMS" "https://archive.mozilla.org/pub/firefox/releases/$V/SHA512SUMS" || { echo "  HATA: SHA512SUMS alinamadi"; exit 1; }
BEK=$(grep -E " linux-x86_64/tr/$F\$" "$T/SHA512SUMS" | awk '{print $1}')
GER=$(sha512sum "$T/$F" | awk '{print $1}')
printf '  boyut    : %s\n' "$(du -h "$T/$F" | cut -f1)"
printf '  beklenen : %s...\n' "${BEK:0:32}"
printf '  gercek   : %s...\n' "${GER:0:32}"
[ -n "$BEK" ] && [ "$BEK" = "$GER" ] || { echo "  HATA: SHA512 UYUSMUYOR - kurulmadi."; exit 1; }
echo "  SHA512 ESLESTI"

echo
echo "########## A3  /opt/firefox'a KURULUM ##########"
[ -d $A/opt/firefox ] && mv $A/opt/firefox $A/opt/firefox.eski-$(date +%Y%m%d-%H%M%S)
mkdir -p $A/opt
tar -xf "$T/$F" -C $A/opt || { echo "  HATA: acilamadi"; exit 1; }
chown -R 0:0 $A/opt/firefox
ln -sfn /opt/firefox/firefox $A/usr/bin/firefox
mkdir -p $A/usr/share/applications
cat > $A/usr/share/applications/firefox.desktop <<'EOF'
[Desktop Entry]
Name=Firefox
GenericName=Web Tarayıcı
Exec=/opt/firefox/firefox %u
Icon=/opt/firefox/browser/chrome/icons/default/default128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=firefox
EOF
echo "  kuruldu: /opt/firefox  ($(du -sh $A/opt/firefox | cut -f1))"
echo "  komut  : /usr/bin/firefox -> /opt/firefox/firefox"
echo "  menu   : /usr/share/applications/firefox.desktop"

echo
echo "########## A4  atasOS KUTUPHANELERIYLE UYUMLULUK (ldd) ##########"
EKS=$(for b in firefox-bin libxul.so libmozgtk.so; do
        f=$(find $A/opt/firefox -maxdepth 1 -name "$b" | head -1)
        [ -n "$f" ] && chroot $A /usr/bin/ldd "${f#$A}" 2>/dev/null
      done | grep 'not found' | sort -u)
if [ -z "$EKS" ]; then echo "  eksik kutuphane YOK"; else echo "  EKSIK:"; echo "$EKS" | sed 's/^/    /'; fi
echo "  glibc (atasOS): $(chroot $A /usr/bin/ldd --version 2>/dev/null | head -1)"

echo
echo "########## B  MESA'YI iris ILE DERLEME ON KOSULLARI (sadece rapor) ##########"
v(){ printf '  %-30s %s\n' "$1" "$2"; }
v "mesa (kurulu)"        "$(ls $A/usr/lib64/libgallium-* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
v "mesa kaynagi /sources" "$(ls -d $A/sources/mesa* 2>/dev/null | tr '\n' ' ' || true)"
for c in meson ninja python3 gcc g++ pkg-config bison flex glslangValidator llvm-config clang; do
    p=$(chroot $A /bin/sh -c "command -v $c" 2>/dev/null)
    v "$c" "${p:-YOK}"
done
v "python mako"   "$(chroot $A /usr/bin/python3 -c 'import mako; print(mako.__version__)' 2>/dev/null || echo YOK)"
v "python yaml"   "$(chroot $A /usr/bin/python3 -c 'import yaml; print(yaml.__version__)' 2>/dev/null || echo YOK)"
v "python packaging" "$(chroot $A /usr/bin/python3 -c 'import packaging; print(packaging.__version__)' 2>/dev/null || echo YOK)"
for p in libdrm libdrm_intel expat zlib libzstd wayland-client wayland-protocols x11 xext xfixes xshmfence xxf86vm xrandr libudev libclc SPIRV-Tools LLVMSPIRVLib; do
    r=$(chroot $A /bin/sh -c "PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig pkg-config --modversion $p" 2>/dev/null)
    v "pkg: $p" "${r:-YOK}"
done
echo "  --- mevcut mesa'nin derleme secenekleri (varsa) ---"
grep -rhoE "gallium-drivers=[^ ']*|vulkan-drivers=[^ ']*" $A/sources/mesa*/build/meson-logs/meson-log.txt 2>/dev/null | sort -u | head -4 | sed 's/^/    /'

sync
umount $A 2>/dev/null
echo
echo "  indirilen dosyalar: $T"
