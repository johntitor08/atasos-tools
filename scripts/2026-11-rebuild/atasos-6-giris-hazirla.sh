#!/usr/bin/env bash
# atas3 ile ekran acilacak - ama GIRIS ISTEMI de olmali.
# getty@tty1'i etkinlestirir, eksik grup/kullanicilari ekler. DERLEME YAPMAZ.
# Kullanim: sudo bash /home/eren/atasos-6-giris-hazirla.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }

A=/mnt/atasos
E=$A/etc
mountpoint -q $A || mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
[ -f "$E/passwd" ] || { echo "HATA: $E/passwd yok"; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)

echo "########## 1/6  KANIT: onceki acilislarda getty calisti mi ##########"
J=$A/var/log/journal
if [ -d "$J" ]; then
    echo "  --- getty / login ile ilgili tum kayitlar ---"
    n=$(journalctl -D "$J" --no-pager -b -1 2>/dev/null | grep -icE 'getty|login prompt|agetty')
    echo "    onceki acilista getty gecen satir sayisi: ${n:-0}"
    journalctl -D "$J" --no-pager -b -1 2>/dev/null | grep -iE 'getty|agetty' | head -5 | sed 's/^/    /'
    [ "${n:-0}" -eq 0 ] && echo "    (hic yok -> getty hic baslatilmamis, teshis dogrulandi)"
    echo
    echo "  --- systemd-logind neden basarisiz oldu ---"
    journalctl -D "$J" --no-pager -b -1 -u systemd-logind 2>/dev/null | tail -8 | sed 's/^/    /'
    echo
    echo "  --- polkit ---"
    journalctl -D "$J" --no-pager -b -1 -u polkit 2>/dev/null | tail -5 | sed 's/^/    /'
else
    echo "  journal yok, atlaniyor"
fi

echo
echo "########## 2/6  SIFRE VAR MI (giris yolu guvencesi) ##########"
for u in root eren oyun; do
    h=$(grep -E "^$u:" "$E/shadow" 2>/dev/null | cut -d: -f2)
    case "$h" in
        ''|'!'*|'*') printf '  %-8s SIFRE YOK / kilitli\n' "$u" ;;
        *)           printf '  %-8s sifre var (%s)\n' "$u" "$(echo "$h" | cut -c1-3)" ;;
    esac
done
echo "  NOT: tty1'de 'eren' icin otomatik giris ayarli, sifre gerekmeyecek."

echo
echo "########## 3/6  GETTY ETKINLESTIRILIYOR ##########"
W=$E/systemd/system/getty.target.wants
mkdir -p "$W"
for t in tty1 tty2; do
    ln -sfn /usr/lib/systemd/system/getty@.service "$W/getty@$t.service"
    printf '  %-28s -> %s\n' "getty@$t.service" "$(readlink "$W/getty@$t.service")"
done
echo "  --- tty1 otomatik giris ayari ---"
cat "$E/systemd/system/getty@tty1.service.d/autologin.conf" 2>/dev/null | sed 's/^/    /'
echo "  (tty2'de normal giris istemi olacak - yedek yol)"

echo
echo "########## 4/6  EKSIK GRUPLAR VE polkitd KULLANICISI ##########"
cp "$E/group"  "$E/group.yedek-$TS"
cp "$E/passwd" "$E/passwd.yedek-$TS"
echo "  yedekler: /etc/group.yedek-$TS  /etc/passwd.yedek-$TS"
echo

grup_ekle(){ # $1=ad $2=gid
    if grep -qE "^$1:" "$E/group"; then
        printf '  %-18s zaten var (%s)\n' "$1" "$(grep -E "^$1:" "$E/group" | cut -d: -f3)"
    elif awk -F: -v g="$2" '$3==g{f=1} END{exit !f}' "$E/group"; then
        printf '  %-18s GID %s dolu <<< ELLENMEDI\n' "$1" "$2"
    else
        printf '%s:x:%s:\n' "$1" "$2" >> "$E/group"
        printf '  %-18s eklendi (GID %s)\n' "$1" "$2"
    fi
}
# GID'ler: 23 LFS systemd-journal standardi, 27 BLFS polkitd standardi,
# 25/26 bu sistemde bos (udev sadece ISME bakar, numara serbest)
grup_ekle systemd-journal 23
grup_ekle render          25
grup_ekle sgx             26
grup_ekle polkitd         27

echo
if grep -qE '^polkitd:' "$E/passwd"; then
    echo "  polkitd kullanicisi zaten var"
elif awk -F: '$3==27{f=1} END{exit !f}' "$E/passwd"; then
    echo "  UID 27 dolu <<< polkitd kullanicisi EKLENMEDI"
else
    echo 'polkitd:x:27:27:PolicyKit Daemon Owner:/etc/polkit-1:/usr/bin/false' >> "$E/passwd"
    echo "  polkitd kullanicisi eklendi (UID 27, ev /etc/polkit-1, kabuk false)"
fi
chown -h 27:27 "$A/etc/polkit-1" 2>/dev/null && echo "  /etc/polkit-1 sahipligi polkitd'ye verildi"

echo
echo "########## 5/6  DOGRULAMA ##########"
D=0
v(){ if [ -e "$1" ]; then printf '  %-56s VAR\n' "${1#$A}"
     else printf '  %-56s YOK <<<\n' "${1#$A}"; D=1; fi; }
v "$W/getty@tty1.service"
v "$W/getty@tty2.service"
v "$A/usr/lib/systemd/system/getty@.service"
v "$A/usr/lib/systemd/system/multi-user.target.wants/getty.target"
echo
echo "  --- sembolik baglar cozuluyor mu (kirik olmamali) ---"
for t in tty1 tty2; do
    if [ -e "$W/getty@$t.service" ]; then printf '  %-24s cozuldu\n' "getty@$t"
    else printf '  %-24s KIRIK BAG <<<\n' "getty@$t"; D=1; fi
done
echo
echo "  --- gruplar ---"
for g in systemd-journal render sgx polkitd; do
    printf '  %-18s %s\n' "$g" "$(grep -E "^$g:" "$E/group" || echo 'YOK <<<')"
    grep -qE "^$g:" "$E/group" || D=1
done
echo
echo "  --- polkitd kullanicisi ---"
grep -E '^polkitd:' "$E/passwd" | sed 's/^/  /' || { echo "  YOK <<<"; D=1; }
echo
echo "  --- /etc/group ve /etc/passwd bozulmadi mi ---"
printf '  %-24s %s satir (yedek: %s)\n' "group"  "$(wc -l < "$E/group")"  "$(wc -l < "$E/group.yedek-$TS")"
printf '  %-24s %s satir (yedek: %s)\n' "passwd" "$(wc -l < "$E/passwd")" "$(wc -l < "$E/passwd.yedek-$TS")"
awk -F: 'NF!=4{print "  BOZUK GROUP SATIRI: "$0}' "$E/group"
awk -F: 'NF!=7{print "  BOZUK PASSWD SATIRI: "$0}' "$E/passwd"

echo
echo "########## 6/6  SONUC ##########"
if [ "$D" -eq 0 ]; then
    echo "  HAZIR. Simdi yeniden baslat ve GRUB'da su girdiyi sec:"
    echo "    >>> atasOS  6.16.1-atas3  metin konsolu (YENI - ekran duzeltmesi)"
    echo
    echo "  BEKLENEN SIRA:"
    echo "    1. Huawei logosu kaybolur, siyah ekrana cekirdek mesajlari akar"
    echo "    2. systemd birimleri [  OK  ] diye gecer"
    echo "    3. 'eren' olarak otomatik giris yapilir, komut satiri gelir"
    echo
    echo "  Ekran gelir ama giris gelmezse: Ctrl+Alt+F2 ile tty2'yi dene."
    echo "  Hicbir sey gelmezse: yeniden baslat, '6.16.1-atas2 (ESKI)' gir."
else
    echo "  SORUN VAR <<< yukaridaki satirlara bak. Yeniden baslatma."
    echo "  Geri donus: cp $E/group.yedek-$TS $E/group"
    echo "              cp $E/passwd.yedek-$TS $E/passwd"
fi
sync
echo
echo "=============================================="
echo " Cekirdeklere dokunulmadi. atas2 ve atas3 yerinde."
echo "=============================================="
