#!/usr/bin/env bash
# atasOS'a Claude Code: Anthropic'in resmi kurulum programi (https://claude.ai/install.sh) p5'te eren kullanicisi
# olarak chroot icinde calisir -> ~/.local/bin/claude (+ ~/.local/share/claude). PATH'te ~/.local/bin yoksa ~/.bashrc'ye eklenir.
# Giris (hesap) atasOS'ta ilk 'claude' calistirildiginda tarayicidan yapilir; bu betik hicbir kimlik bilgisi tasimaz.
# Kullanim: sudo bash /home/eren/atasos-67-claude-code.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
LOG=/home/eren/atas3-loglar/atasos-67-claude-code.log
exec > >(tee -a "$LOG") 2>&1
echo "########## atasOS 67: Claude Code  ($(date '+%F %T')) ##########"
A=/mnt/atasos
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ cd /; for m in $A/run $A/sys $A/proc $A/dev/pts $A/dev; do mountpoint -q $m && umount -l $m; done; sync
           umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi (umount /mnt/atasos)"; }
trap temizle EXIT
mount --bind /dev $A/dev; mount --bind /dev/pts $A/dev/pts; mount -t proc proc $A/proc; mount -t sysfs sys $A/sys
mount --bind /run $A/run    # DNS
grep -q '^eren:' $A/etc/passwd || { echo "HATA: p5'te eren yok"; exit 1; }
er(){ chroot $A /usr/bin/env -i HOME=/home/eren USER=eren LOGNAME=eren SHELL=/bin/bash TERM=dumb LANG=tr_TR.UTF-8 \
        PATH=/home/eren/.local/bin:/usr/bin:/usr/sbin:/bin:/sbin /bin/su -s /bin/bash eren -c "$1"; }

echo
echo "########## 1/2  KURULUM (resmi kurulum programi) ##########"
er 'cd ~ && curl -fsSL https://claude.ai/install.sh | bash' || { echo "  HATA: kurulum programi basarisiz"; exit 1; }

echo
echo "########## 2/2  DENETIM ##########"
H=0
# baglanti mutlak (/home/eren/...): chroot icinde denetle; su PATH'i sifirladigi icin tam yolla calistir
chroot $A test -x /home/eren/.local/bin/claude && echo "  ~/.local/bin/claude var -> $(readlink $A/home/eren/.local/bin/claude)" || { echo "  HATA: ~/.local/bin/claude yok"; H=1; }
V=$(er '/home/eren/.local/bin/claude --version' 2>&1) && echo "  claude --version: $V" || { echo "  HATA: claude calismadi: $V"; H=1; }
B=$A/home/eren/.bashrc
if ! grep -qs '\.local/bin' $B; then
    printf '\n# Claude Code (atasos-67)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> $B
    chown "$(stat -c %u:%g $A/home/eren)" $B
    echo "  ~/.bashrc: PATH'e ~/.local/bin eklendi"
else echo "  ~/.bashrc: ~/.local/bin zaten PATH'te"; fi
grep -qs 'bashrc' $A/home/eren/.bash_profile $A/home/eren/.profile || echo "  NOT: ~/.bash_profile ~/.bashrc'yi okumuyor olabilir; Konsole etkilesimli kabukta ~/.bashrc okunur."
echo
[ $H = 0 ] && echo "  TAMAM. atasOS'ta Konsole ac:  claude   (ilk calistirmada tarayicidan giris)" || echo "  SORUN VAR, yukaridaki HATA satirlarina bak."
echo "  Kayit: $LOG"
