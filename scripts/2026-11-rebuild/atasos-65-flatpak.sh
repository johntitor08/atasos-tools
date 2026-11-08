#!/usr/bin/env bash
# atasOS'a Flatpak (Steam icin): p5'e chroot ile kaynaktan derler ve kurar.
#   Zincir: libseccomp, yaml, npth, libassuan, libksba, gnupg, gpgme, libxmlb, AppStream,
#           bubblewrap, xdg-dbus-proxy, libostree, flatpak 1.16.1
#   Sonra: 'flatpak' sistem kullanicisi, Plasma oturumuna XDG_DATA_DIRS, Flathub deposu (sistem geneli).
# Kaynaklar: /veri/atasos-flatpak-kaynak (indirildi) -> p5:/sources/flatpak-zinciri
# Her paketin dosya listesi /var/lib/atasos-paketler/<ad>.list; mevcut bir dosyanin ustune yazan olursa uyarir.
# Tekrar calistirmak guvenli: kurulu paketler atlanir (YENIDEN=1 ile hepsi yeniden derlenir).
# Kullanim: sudo bash /home/eren/atasos-65-flatpak.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
KY=/veri/atasos-flatpak-kaynak
LOG=/home/eren/atas3-loglar/atasos-65-flatpak.log
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS 65: Flatpak  ($(date '+%F %T')) ##########"
for f in derle.sh flathub.flatpakrepo flatpak-1.16.1.tar.xz libostree-2025.2.tar.xz gnupg-2.4.7.tar.bz2 AppStream-1.0.4.tar.xz; do
    [ -s "$KY/$f" ] || { echo "HATA: $KY/$f yok"; exit 1; }; done

A=/mnt/atasos
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ cd /; for m in $A/run $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount -l $m; done; sync
           umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi (umount /mnt/atasos)"; }
trap temizle EXIT
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sys $A/sys
mount --bind /run $A/run    # DNS (resolv.conf -> /run/systemd/resolve) ve /run/lock
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin /bin/bash -c "$1"; }

echo
echo "########## 1/3  KAYNAKLAR -> p5:/sources/flatpak-zinciri ##########"
Z=$A/sources/flatpak-zinciri; mkdir -p $Z
cp -u $KY/*.tar.* $KY/*.whl $KY/derle.sh $KY/flathub.flatpakrepo $Z/ && ls $Z | wc -l | sed 's/^/  dosya: /'
df -h $A | tail -1 | awk '{print "  p5 bos: "$4}'

echo
echo "########## 2/3  DERLEME (chroot; ~15-25 dk) ##########"
cr "YENIDEN=${YENIDEN:-0} bash /sources/flatpak-zinciri/derle.sh" || { echo; echo "  HATA: derleme durdu. Ayrinti: $Z/is/*.log ve $LOG"; exit 1; }

echo
echo "########## 3/3  AYARLAR ##########"
# atasOS'ta systemd-sysusers yok: flatpak.conf'taki kullaniciyi elle olustur (sistem yardimcisi bu kullaniciyla calisir)
cr "getent group flatpak >/dev/null || groupadd -r flatpak; getent passwd flatpak >/dev/null || useradd -r -g flatpak -d / -s /bin/false -c 'Flatpak system helper' flatpak"
cr "getent passwd flatpak >/dev/null" && echo "  'flatpak' sistem kullanicisi var" || echo "  UYARI: flatpak kullanicisi olusturulamadi"
# /etc/profile profile.d'yi okumuyor: Plasma oturumu Flatpak uygulamalarini menude gorsun diye XDG_DATA_DIRS'i plasma env ile ver
mkdir -p $A/etc/xdg/plasma-workspace/env
printf '%s\n' '# atasOS: Flatpak uygulamalari (Steam vb.) uygulama menusunde gorunsun' '[ -r /etc/profile.d/flatpak.sh ] && . /etc/profile.d/flatpak.sh' \
    > $A/etc/xdg/plasma-workspace/env/atasos-flatpak.sh
echo "  /etc/xdg/plasma-workspace/env/atasos-flatpak.sh yazildi"
[ -e $A/etc/grub.d/15_ostree ] && rm -f $A/etc/grub.d/15_ostree && echo "  /etc/grub.d/15_ostree kaldirildi (atasOS ostree ile acilmaz)"
cr "flatpak remote-add --system --if-not-exists flathub /sources/flatpak-zinciri/flathub.flatpakrepo" && echo "  Flathub deposu eklendi (sistem geneli)"
echo
echo "  --- denetim ---"
H=0
for c in "flatpak --version" "bwrap --version" "xdg-dbus-proxy --version" "ostree --version | head -2 | tail -1" "gpg --version | head -1" "appstreamcli --version" "flatpak remotes --system"; do
    o=$(cr "$c" 2>&1) && echo "  $c: $(echo "$o" | tr '\n' ' ')" || { echo "  HATA: $c -> $o"; H=1; }
done
cr "ldd /usr/bin/flatpak | grep -q 'not found'" && { echo "  HATA: flatpak eksik kutuphane:"; cr "ldd /usr/bin/flatpak | grep 'not found'"; H=1; }
[ -f $A/etc/profile.d/flatpak.sh ] && echo "  /etc/profile.d/flatpak.sh var (uygulamalar menude gorunur)" || echo "  UYARI: /etc/profile.d/flatpak.sh yok"
[ -f $A/usr/share/polkit-1/rules.d/org.freedesktop.Flatpak.rules ] && echo "  polkit kurali var (wheel grubu parolasiz kurabilir)"
echo
[ $H = 0 ] && echo "  TAMAM. atasOS'u ac, Konsole'da:  flatpak install flathub com.valvesoftware.Steam" \
           || echo "  SORUN VAR, yukaridaki HATA satirlarina bak."
echo "  Kayit: $LOG"
