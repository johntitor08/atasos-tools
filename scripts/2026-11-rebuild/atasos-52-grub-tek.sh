#!/usr/bin/env bash
# Kubuntu GRUB: atasOS girdilerinden YALNIZ "atas5 masaustu / SDDM" kalir, adi "atasOS" olur.
# Eski 42/43/44 dosyalari /root/grub-yedek-<tarih>/ altina yedeklenir (geri donus: oradan /etc/grub.d'ye + update-grub).
# Kullanim (atas5 gercek donanimda acildiktan sonra): sudo bash /home/eren/atasos-52-grub-tek.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
Y=/root/grub-yedek-$(date +%m%d-%H%M); mkdir -p $Y
for f in 42_atasos 43_atasos_atas4 44_atasos_atas5; do [ -f /etc/grub.d/$f ] && cp -a /etc/grub.d/$f $Y/; done
G5=/etc/grub.d/44_atasos_atas5
[ -f $Y/44_atasos_atas5 ] || { echo "HATA: $G5 yok - GRUB'a dokunulmadi"; exit 1; }
python3 -I - $Y/44_atasos_atas5 $G5 <<'PY' || { echo "HATA: girdi ayiklanamadi - GRUB'a dokunulmadi"; exit 1; }
import sys,re
t=open(sys.argv[1]).read()
m=re.search(r'menuentry "[^"]*atas5[^"]*masaustu[^"]*"[^{]*\{.*?\n\}', t, re.S) or re.search(r'menuentry "atasOS"[^{]*\{.*?atas5.*?\n\}', t, re.S)
if not m: sys.exit(1)
g=m.group(0); g=g.replace(g.split('"')[1], "atasOS", 1)
open(sys.argv[2],"w").write('#!/bin/sh\nexec tail -n +3 $0\n'+g+'\n')
PY
chmod 755 $G5
rm -f /etc/grub.d/42_atasos /etc/grub.d/43_atasos_atas4
update-grub 2>&1 | grep -iE 'error|hata' | sed 's/^/  /'
echo "  yedek: $Y"
echo "  GRUB'daki atasOS girdileri:"; grep -n 'menuentry "atasOS' /boot/grub/grub.cfg | sed 's/^/    /'
