#!/usr/bin/env bash
# atasos-98: p4'te (kurulu atasOS) 6.18 ile YENIDEN BASLATMADA TAKILMA teshisi icin hazirlik.
#   1) p4'te kalici gunluk: /var/log/journal olusturulur -> sonraki acilis + KAPANIS kayitlari diske yazilir
#      (simdiye kadar gunluk yalniz RAM'deydi; takilan kapanistan sonra hic iz kalmiyordu). Kubuntu'dan okunur.
#   2) Kubuntu GRUB'una ek bir girdi: "atasOS (kurulu, p4) - 6.18 AYRINTILI" -> quiet YOK, systemd adimlari ve
#      cekirdek iletileri ekranda; kapanista hangi adimda takildigi gorunur (fotografi cekilebilir).
#      45_atasos_kurulu'nun SONUNA eklenir; mevcut iki girdiye dokunulmaz. Tekrar calistirmak cift girdi yapmaz.
#   Geri almak: sudo bash ~/atasos-96-p4-cekirdek-grub.sh  (girdileri yeniden uretir, ayrintili girdi kalkar)
# Kullanim (Konsole'da): sudo bash ~/atasos-98-p4-kapanis-teshis.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi calisiyor. Hicbir sey yapilmadi."; exit 1; }
DEV=/dev/nvme0n1p4; G=/etc/grub.d/45_atasos_kurulu; KR=6.18.64-atas7
[ "$(blkid -s LABEL -o value $DEV)" = atasos-kurulu ] || { echo "HATA: $DEV etiketi atasos-kurulu degil"; exit 1; }
grep -q "^$DEV " /proc/mounts && { echo "  p4 baska bir yerde bagli (Dolphin?); once ayir. Hicbir sey yapilmadi."; exit 1; }
[ -f $G ] && grep -q "vmlinuz-$KR " $G || { echo "HATA: $G icinde $KR girdisi yok (once atasos-96)"; exit 1; }
M=/mnt/atasos-p4; mkdir -p $M
mount $DEV $M || { echo "HATA: p4 baglanamadi"; exit 1; }
trap 'cd /; sync; umount $M 2>/dev/null || echo "  UYARI: p4 ayrilamadi"' EXIT
[ -f $M/boot/vmlinuz-$KR ] || { echo "HATA: p4'te /boot/vmlinuz-$KR yok"; exit 1; }

echo "== 1/2 p4 kalici gunluk"
if [ -d $M/var/log/journal ]; then echo "  zaten var"
else
    mkdir -p $M/var/log/journal && chown root:systemd-journal $M/var/log/journal 2>/dev/null
    chmod 2755 $M/var/log/journal; echo "  olusturuldu: /var/log/journal (systemd-journald acilista kendiliginden kullanir)"
fi
grep -qE '^\s*Storage\s*=\s*(volatile|none)' $M/etc/systemd/journald.conf $M/etc/systemd/journald.conf.d/*.conf 2>/dev/null \
    && echo "  UYARI: journald.conf Storage=volatile/none -> yine RAM'de kalir" || echo "  journald.conf: Storage varsayilan (auto) -> diske yazar"

echo "== 2/2 Kubuntu GRUB: ayrintili 6.18 girdisi"
if grep -q 'AYRINTILI' $G; then echo "  zaten var"
else
    cp -a $G /root/45_atasos_kurulu.yedek-$(date +%Y%m%d-%H%M)
    blok=$(awk -v k="vmlinuz-$KR " '/^menuentry/{b=$0"\n"; ic=1; next} ic{b=b $0 "\n"; if($0 ~ /^}/){ if(index(b,k)) {printf "%s", b; exit} ic=0 }}' $G)
    [ -n "$blok" ] || { echo "HATA: $KR blogu okunamadi"; exit 1; }
    yeni=$(printf '%s' "$blok" | sed "1s/^menuentry \"[^\"]*\"/menuentry \"atasOS (kurulu, p4) - 6.18 AYRINTILI (kapanis teshisi)\"/; s/ quiet loglevel=3/ loglevel=7 systemd.show_status=1 printk.devkmsg=on/")
    printf '%s\n' "$yeni" >> $G
    C=$(sh $G); [ "$(grep -c '^menuentry' <<< "$C")" -ge 3 ] && [ "$(grep -c '{' <<< "$C")" -eq "$(grep -c '^}' <<< "$C")" ] \
        || { echo "HATA: girdi dosyasi bozuldu; yedekten geri konuyor"; cp -a "$(ls -t /root/45_atasos_kurulu.yedek-* | head -1)" $G; exit 1; }
    grep -A9 AYRINTILI $G | grep -E 'menuentry|linux' | sed 's/^/    /'
    update-grub 2>&1 | grep -iE 'error|done' | sed 's/^/  /'
fi
grep -n 'menuentry "atasOS (kurulu' /boot/grub/grub.cfg | sed 's/^/  /'
echo "  TAMAM. Yeniden baslat -> 'atasOS (kurulu, p4) - 6.18 AYRINTILI' sec -> masaustu acilinca yeniden baslat."
echo "  Takilirsa ekranin fotografini cek; 2-3 dk bekle; sonra Kubuntu'ya donunce Claude kalici gunlugu okur."
