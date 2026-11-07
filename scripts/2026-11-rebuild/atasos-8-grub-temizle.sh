#!/usr/bin/env bash
# HATA: 42_atasos yedegi /etc/grub.d icinde CALISTIRILABILIR kaldi, GRUB onu da
# isledi; menude eski atas2 girdileri de duruyor ve sen onlardan birini sectin.
# Bu betik yedegi dizinden cikarir, menuyu yeniden uretir ve girdileri NUMARALI listeler.
# Ayrica atasOS'un saat ayarini duzeltir (journal 3 saat geri gosteriyordu).
# Kullanim: sudo bash /home/eren/atasos-8-grub-temizle.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
mountpoint -q $A || mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }

echo "########## 1/5  /etc/grub.d TEMIZLENIYOR ##########"
YD=/root/grub.d-yedekler
mkdir -p "$YD"
N=0
for f in /etc/grub.d/*; do
    b=$(basename "$f")
    case "$b" in
        README) continue ;;
        [0-9][0-9]_*)
            # normal GRUB betigi adi: NN_ad  (nokta iceriyorsa yedek/bakiyedir)
            case "$b" in
                *.*) ;;          # 42_atasos.yedek-... gibi -> asagi dus
                *)   continue ;; # temiz isim -> dokunma
            esac ;;
        *) continue ;;
    esac
    if [ -x "$f" ]; then
        echo "  DISARI ALINIYOR: $b  (calistirilabilirdi, GRUB'a giriyordu)"
        mv "$f" "$YD/$b"
        N=$((N+1))
    fi
done
[ "$N" -eq 0 ] && echo "  temizlenecek dosya yok"
echo
echo "  --- kalan (GRUB'in isleyecegi dosyalar) ---"
ls -l /etc/grub.d/ | grep -E '^-rwx' | awk '{print "    "$NF}'
echo "  yedekler burada: $YD"

echo
echo "########## 2/5  42_atasos DOGRULANIYOR ##########"
echo "  --- bu dosyadaki menuentry basliklari ---"
grep -n '^menuentry' /etc/grub.d/42_atasos | sed 's/^/    /'
echo "  --- her girdinin cagirdigi cekirdek ---"
grep -oE 'vmlinuz-[0-9.]+-[a-z0-9]+' /etc/grub.d/42_atasos | sort | uniq -c | sed 's/^/    /'

echo
echo "########## 3/5  MENU YENIDEN URETILIYOR ##########"
update-grub 2>&1 | grep -viE '^Generating|^done$' | sed 's/^/  /'
echo
T=$(grep -c '^menuentry.*atasOS' /boot/grub/grub.cfg)
printf '  atasOS girdi sayisi: %s  (beklenen: 4)\n' "$T"
E=$(grep -A6 '^menuentry.*atasOS' /boot/grub/grub.cfg | grep -c 'vmlinuz-6.16.1-atas2')
Y=$(grep -A6 '^menuentry.*atasOS' /boot/grub/grub.cfg | grep -c 'vmlinuz-6.16.1-atas3')
printf '  atas3 cagiran girdi: %s  (beklenen: 3)\n' "$Y"
printf '  atas2 cagiran girdi: %s  (beklenen: 1 - geri donus)\n' "$E"

echo
echo "########## 4/5  MENUDE NE GORECEKSIN (numarali) ##########"
echo "  Ust menude yukaridan asagiya sirayla:"
grep -nE '^(menuentry|submenu)' /boot/grub/grub.cfg \
  | sed -E 's/^[0-9]+:(menuentry|submenu) .([^"'"'"']*)..*/\2/' \
  | nl -ba -w3 -s'  ' | sed 's/^/  /'
echo
echo "  >>> SECMEN GEREKEN: basliginda '6.16.1-atas3' ve 'metin konsolu' gecen girdi."
echo "  >>> Baslikta 'atas3' YOKSA yanlis girdidir."

echo
echo "########## 5/5  atasOS SAATI (RTC yorumu) ##########"
HOST=$(timedatectl show -p LocalRTC --value 2>/dev/null)
echo "  Kubuntu'nun donanim saati yerel mi? LocalRTC=$HOST  (no => RTC UTC'dir)"
echo "  atasOS /etc/adjtime son satiri: $(tail -1 $A/etc/adjtime 2>/dev/null)"
if [ "$HOST" = "no" ] && [ "$(tail -1 $A/etc/adjtime 2>/dev/null)" = "LOCAL" ]; then
    cp "$A/etc/adjtime" "$A/etc/adjtime.yedek-$(date +%Y%m%d-%H%M%S)"
    printf '0.0 0 0.0\n0\nUTC\n' > "$A/etc/adjtime"
    echo "  DUZELTILDI: atasOS artik RTC'yi UTC kabul edecek."
    echo "  yeni icerik: $(tr '\n' ' ' < $A/etc/adjtime)"
else
    echo "  degisiklik gerekmedi."
fi

sync
echo
echo "=============================================="
if [ "$T" -eq 4 ] && [ "$Y" -eq 3 ]; then
    echo " HAZIR. Yeniden baslat ve basliginda 'atas3' gecen"
    echo " ILK girdiyi sec. Eski atas2 girdileri artik menuden kalkti."
else
    echo " SAYILAR BEKLENENE UYMADI <<< yukariya bak, yeniden baslatma."
fi
echo "=============================================="
