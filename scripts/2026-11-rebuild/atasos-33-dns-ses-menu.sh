#!/usr/bin/env bash
# 1) DNS: /etc/resolv.conf "nameserver 10.0.2.3" (VirtualBox/QEMU NAT DNS'i) -> gercek agda yok.
#    NetworkManager resolv.conf'u kendisi yazsin (rc-manager=file). systemd-resolved'a dokunulmaz.
# 2) Ses: PipeWire 1.2.7'de ALSA eklentisi yok. ISO'daki ayni surum libspa-alsa.so + alsa-card-profile.
# 3) Menu: Plasma "applications.menu" ariyor, sistemde sadece plasma-applications.menu var -> bag.
# Degisen her dosya yedeklenir.
# Kullanim: sudo bash /home/eren/atasos-33-dns-ses-menu.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
SQ=/home/eren/atas3-loglar/iso-inceleme/filesystem.squashfs
TS=$(date +%Y%m%d-%H%M%S)
Y=$A/var/lib/atasos-paketler/yedek-33-$TS
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
temizle(){ for m in $A/sys $A/proc $A/dev; do mountpoint -q $m && umount $m; done; umount $A 2>/dev/null; }
trap temizle EXIT
mount --bind /dev $A/dev; mount -t proc proc $A/proc; mount -t sysfs sysfs $A/sys
mkdir -p "$Y"
D=0

echo "########## 1/3  DNS ##########"
cp -a $A/etc/resolv.conf "$Y/resolv.conf"
echo "  eski resolv.conf: $(grep -v '^#' $A/etc/resolv.conf | tr '\n' ' ')  (yedek: ${Y#$A})"
mkdir -p $A/etc/NetworkManager/conf.d
cat > $A/etc/NetworkManager/conf.d/90-atasos-dns.conf <<'EOF'
# atasOS: systemd-resolved calismiyor; NetworkManager DHCP'den gelen DNS'i
# dogrudan /etc/resolv.conf'a yazsin. (Eski dosyada VM'den kalma 10.0.2.3 vardi.)
[main]
dns=default
rc-manager=file
EOF
chmod 644 $A/etc/NetworkManager/conf.d/90-atasos-dns.conf
printf '# NetworkManager tarafindan yazilir (90-atasos-dns.conf)\n' > $A/etc/resolv.conf
chmod 644 $A/etc/resolv.conf
grep -q '10.0.2.3' $A/etc/resolv.conf && { echo "  10.0.2.3 hala duruyor <<<"; D=1; } || echo "  10.0.2.3 kaldirildi; baglaninca NetworkManager gercek DNS'i yazacak"
echo "  nsswitch hosts: $(grep -E '^hosts' $A/etc/nsswitch.conf)"
echo "  ('resolve' calismayinca [!UNAVAIL=return] sayesinde 'dns'e duser - sorun degil)"

echo
echo "########## 2/3  SES: PipeWire ALSA eklentisi ##########"
P=usr/lib64/spa-0.2/alsa/libspa-alsa.so
echo "  p5 pipewire: $(strings $A/usr/bin/pipewire | grep -m1 -xE '1\.[0-9]+\.[0-9]+')   ISO: 1.2.7"
printf '%s\nusr/share/alsa-card-profile\n' "$P" > /tmp/pw33.$$
[ -d $A/usr/share/alsa-card-profile ] && cp -a $A/usr/share/alsa-card-profile "$Y/"
unsquashfs -q -f -d "$A" -ef /tmp/pw33.$$ "$SQ" >/dev/null 2>&1; rm -f /tmp/pw33.$$
{ echo "/$P"; find $A/usr/share/alsa-card-profile -type f | sed "s|^$A||"; } > $A/var/lib/atasos-paketler/pipewire-alsa-iso.list
if [ -f "$A/$P" ]; then
    e=$(chroot $A /usr/bin/ldd "/$P" 2>&1 | grep 'not found')
    [ -z "$e" ] && echo "  /$P  TAMAM (ldd eksiksiz)" || { echo "  ldd EKSIK:"; echo "$e" | sed 's/^/    /'; D=1; }
else echo "  eklenti AKTARILAMADI <<<"; D=1; fi
n=$(find $A/usr/share/alsa-card-profile -type f 2>/dev/null | wc -l)
[ "$n" -gt 0 ] && echo "  alsa-card-profile: $n dosya" || { echo "  alsa-card-profile YOK <<<"; D=1; }
echo "  eren audio grubunda: $(grep -E '^audio:' $A/etc/group | cut -d: -f4)"

echo
echo "########## 3/3  UYGULAMA MENUSU ##########"
M=$A/etc/xdg/menus
if [ -e $M/applications.menu ]; then echo "  applications.menu zaten var"
else ln -s plasma-applications.menu $M/applications.menu; echo "  applications.menu -> plasma-applications.menu"; fi
[ -e $M/applications.menu ] && echo "  bag cozuluyor  TAMAM" || { echo "  bag KIRIK <<<"; D=1; }
# eski menu onbellegi bos menuyu hatirlamasin
rm -f $A/home/eren/.cache/ksycoca6_* 2>/dev/null && echo "  eski menu onbellegi temizlendi (oturum acilinca yeniden olusur)"

echo
sync
if [ "$D" -eq 0 ]; then
cat <<'SON'
  TAMAM. Yeniden baslat, GRUB'da 5. satir (masaustu / SDDM). Telefonda erisim noktasi acik olsun.
  Kontrol (Konsole):
    cat /etc/resolv.conf          # 10.0.2.3 degil, telefonun verdigi DNS gorunmeli
    ping -c2 archive.org
    wpctl status                  # "Sinks" altinda Built-in Audio gorunmeli
  Menude Firefox, Konsole, Dolphin gorunmeli.
SON
else
    echo "  SORUN VAR <<< yukariya bak. Yedek: ${Y#$A}"
fi
