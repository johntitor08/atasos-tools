#!/usr/bin/env bash
# atasos-96: Kubuntu GRUB'undaki p4 (kurulu atasOS) girdisini p4'un /boot'undaki cekirdeklerden YENIDEN URETIR.
#   p4'un kendi GRUB menusu yok; Kubuntu'nun /etc/grub.d/45_atasos_kurulu dosyasi sabit bir vmlinuz'u aciyordu.
#   Bu betik: en yeni atasN cekirdegi ilk (varsayilan atasOS girdisi), eskiler "(yedek cekirdek ...)" girdisi olur.
#   p4'e yeni cekirdek paketi kurulunca (Sistemi Guncelle) bunu bir kez calistirmak yeter.
#   Dokunulan tek sey: /etc/grub.d/45_atasos_kurulu (+ update-grub). Eskisi /root/45_atasos_kurulu.yedek-* olarak
#   grub.d DISINA yedeklenir (grub.d icindeki yedekler de menuye girer). p4'e yalniz okumak icin bakilir.
# Kullanim (Konsole'da): sudo bash ~/atasos-96-p4-cekirdek-grub.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
G=/etc/grub.d/45_atasos_kurulu
[ -f $G ] || { echo "HATA: $G yok"; exit 1; }
UUID=$(sed -n 's/.*--fs-uuid --set=root \([0-9a-f-]*\).*/\1/p' $G | head -1)
PUUID=$(sed -n 's/.*root=PARTUUID=\([0-9a-f-]*\).*/\1/p' $G | head -1)
[ -n "$UUID" ] && [ -n "$PUUID" ] || { echo "HATA: $G icinden UUID/PARTUUID okunamadi"; exit 1; }
DEV=$(blkid -U "$UUID") || { echo "HATA: UUID $UUID olan bolum yok"; exit 1; }
[ "$(blkid -s PARTUUID -o value "$DEV")" = "$PUUID" ] || { echo "HATA: $DEV PARTUUID'i $PUUID degil"; exit 1; }
M=$(mktemp -d /run/atasos-p4.XXXX)
trap 'umount "$M" 2>/dev/null; rmdir "$M" 2>/dev/null' EXIT
if findmnt -n "$DEV" >/dev/null; then B=$(findmnt -nfo TARGET "$DEV"); else mount -o ro "$DEV" "$M" || { echo "HATA: $DEV baglanamadi"; exit 1; }; B=$M; fi
mapfile -t CEK < <(ls "$B"/boot/vmlinuz-*-atas[0-9]* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -rV)
[ ${#CEK[@]} -gt 0 ] || { echo "HATA: $DEV/boot'ta atasN cekirdegi yok"; exit 1; }
for k in "${CEK[@]}"; do
    [ -d "$B/usr/lib/modules/$k" ] && echo "  cekirdek: $k (moduller var)" || echo "  cekirdek: $k (UYARI: /usr/lib/modules/$k yok)"
done
SURUM=$(sed -n 's/^VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$B/etc/os-release" 2>/dev/null | head -1)
cp -a $G /root/45_atasos_kurulu.yedek-$(date +%Y%m%d-%H%M)
{
    echo '#!/bin/sh'
    echo 'exec tail -n +3 $0'
    i=0
    for k in "${CEK[@]}"; do
        [ $i -eq 0 ] && ad="atasOS (kurulu, p4)" || ad="atasOS (kurulu, p4) - yedek cekirdek $k"
        cat <<EOF
menuentry "$ad" --class atasos {
    insmod part_gpt
    insmod ext2
    insmod all_video
    insmod gfxterm
    set gfxpayload=keep
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/vmlinuz-$k root=PARTUUID=$PUUID rw rootwait quiet loglevel=3
}
EOF
        i=$((i+1))
    done
} > $G.yeni
# 'sh -n' KULLANILMAZ: dosya 'exec tail -n +3 $0' ile kendi govdesini basar; govde GRUB sozdizimi, sh degil.
# Dogrusu: calistir ve ciktida her cekirdek icin bir girdi + dengeli { } var mi bak.
CIKTI=$(sh $G.yeni)
[ "$(grep -c '^menuentry "atasOS (kurulu, p4)' <<< "$CIKTI")" -eq ${#CEK[@]} ] \
    && [ "$(grep -c '{' <<< "$CIKTI")" -eq "$(grep -c '^}' <<< "$CIKTI")" ] \
    || { echo "HATA: uretilen dosya beklenen girdileri vermiyor"; rm -f $G.yeni; exit 1; }
echo "  uretilen girdiler:"; grep '^menuentry' <<< "$CIKTI" | sed 's/ --class.*//; s/^/    /'
mv -f $G.yeni $G && chmod 755 $G
update-grub 2>&1 | grep -iE 'error|done' | sed 's/^/  /'
grep -n 'menuentry "atasOS (kurulu' /boot/grub/grub.cfg | sed 's/^/  /'
grep -q "vmlinuz-${CEK[0]} " /boot/grub/grub.cfg && echo "  TAMAM: GRUB'da 'atasOS (kurulu, p4)' -> ${CEK[0]}; sorun olursa '- yedek cekirdek' girdisini sec." \
    || { echo "  HATA: yeni girdi grub.cfg'de yok; yedek: /root/45_atasos_kurulu.yedek-*"; exit 1; }
echo "  (p4 surumu: ${SURUM:-?})"
