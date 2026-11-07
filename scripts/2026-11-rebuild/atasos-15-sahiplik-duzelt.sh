#!/usr/bin/env bash
# atasOS sistem dosyalari root yerine eren'e (1001) ait - VM kalintisi.
# UID/GID 1001 olan sistem dosyalarini root:root yapar. Baska sahiplere DOKUNMAZ.
# chown'un sildigi setuid/setgid bitleri ve dosya yetenekleri (capabilities) geri yuklenir.
# Her degisiklik manifest'e yazilir -> tamamen geri alinabilir.
# Kullanim: sudo bash /home/eren/atasos-15-sahiplik-duzelt.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
TS=$(date +%Y%m%d-%H%M%S)
Y=/root/atasos-sahiplik-$TS
mkdir -p "$Y"

# Hariç: kullanici verisi ve kasitli olarak eren'e ait olanlar
bul(){ # ek find kosullari
    find "$A" -xdev \
        \( -path "$A/home" -o -path "$A/sources" -o -path "$A/kurtarma" \
           -o -path "$A/var/mail" -o -path "$A/var/spool/mail" -o -path "$A/tmp/*" \
           -o -path "$A/lost+found" \) -prune -o "$@"
}

echo "########## 1/6  KESIF (henuz hicbir sey degismedi) ##########"
bul \( -uid 1001 -o -gid 1001 \) -printf '%u:%g:%m\t%p\n' > "$Y/manifest.txt" 2>/dev/null
N=$(wc -l < "$Y/manifest.txt")
printf '  %-40s %s\n' "degisecek girdi (uid veya gid 1001)" "$N"
printf '  %-40s %s\n' "  bunlarin dizin olanlari" "$(bul \( -uid 1001 -o -gid 1001 \) -type d -print 2>/dev/null | wc -l)"
bul \( -uid 1001 -o -gid 1001 \) ! -type l ! -type d -perm /6000 -printf '%m\t%p\n' > "$Y/setuid.txt" 2>/dev/null
printf '  %-40s %s\n' "setuid/setgid (geri yuklenecek)" "$(wc -l < "$Y/setuid.txt")"
sed "s|$A||" "$Y/setuid.txt" | head -10 | sed 's/^/      /'
getcap -r "$A" 2>/dev/null | grep -vE "^$A/(home|sources|kurtarma)/" > "$Y/caps.txt"
printf '  %-40s %s\n' "capability tasiyan dosya" "$(wc -l < "$Y/caps.txt")"
sed "s|$A||" "$Y/caps.txt" | head -10 | sed 's/^/      /'
echo
echo "  --- ornek (ilk 15) ---"
sed "s|$A||" "$Y/manifest.txt" | head -15 | sed 's/^/    /'
echo
echo "  --- DOKUNULMAYACAK baska sahipler (kontrol) ---"
bul ! -uid 0 ! -uid 1001 -printf '%u(%U)  %p\n' 2>/dev/null | sed "s|$A||" | awk '{print $1}' | sort | uniq -c | sed 's/^/    /'
echo
echo "  manifest: $Y/manifest.txt"

echo
read -r -p "  Devam edilsin mi? 'evet' yaz: " C
[ "$C" = "evet" ] || { echo "  Iptal. Hicbir sey degismedi."; umount $A 2>/dev/null; exit 0; }

echo
echo "########## 2/6  SAHIPLIK root:root ##########"
bul -uid 1001 -exec chown -h 0 {} + 2>>"$Y/hata.txt"
bul -gid 1001 -exec chgrp -h 0 {} + 2>>"$Y/hata.txt"
echo "  tamam. hata satiri: $(wc -l < "$Y/hata.txt" 2>/dev/null || echo 0)"

echo
echo "########## 3/6  setuid/setgid GERI YUKLENIYOR ##########"
R=0
while IFS=$'\t' read -r m p; do
    chmod "$m" "$p" && R=$((R+1))
done < "$Y/setuid.txt"
echo "  $R dosyanin izni geri yuklendi"

echo
echo "########## 4/6  CAPABILITY GERI YUKLENIYOR ##########"
R=0
while read -r line; do
    p=${line% *}; c=${line##* }
    setcap "$c" "$p" 2>>"$Y/hata.txt" && R=$((R+1))
done < "$Y/caps.txt"
echo "  $R dosyanin yetenegi geri yuklendi"

echo
echo "########## 5/6  /tmp ve kritik dizinler ##########"
chown 0:0 $A/tmp 2>/dev/null; chmod 1777 $A/tmp
for d in / /usr /usr/bin /usr/lib /var /var/lib /etc /tmp; do
    printf '  %-10s %s\n' "$d" "$(stat -c '%U:%G %a' "$A$d")"
done

echo
echo "########## 6/6  DOGRULAMA ##########"
D=0
K=$(bul \( -uid 1001 -o -gid 1001 \) -print 2>/dev/null | wc -l)
printf '  %-40s %s  (beklenen 0)\n' "hala 1001'e ait sistem girdisi" "$K"
[ "$K" -eq 0 ] || D=1
echo "  --- sudo / su setuid mi ---"
for f in /usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/lib/polkit-1/polkit-agent-helper-1; do
    [ -e "$A$f" ] || continue
    m=$(stat -c '%A %U' "$A$f")
    case "$m" in -rws*root) printf '    %-40s %s  TAMAM\n' "$f" "$m" ;;
                 *)         printf '    %-40s %s  <<<\n' "$f" "$m"; D=1 ;; esac
done
echo "  --- setuid listesi birebir mi ---"
F=0
while IFS=$'\t' read -r m p; do
    [ "$(stat -c '%a' "$p")" = "$m" ] || { echo "    FARKLI: ${p#$A} beklenen $m, simdi $(stat -c '%a' "$p")"; F=1; }
done < "$Y/setuid.txt"
[ "$F" -eq 0 ] && echo "    hepsi ayni" || D=1
echo "  --- /home/eren hala eren'e mi ait ---"
stat -c '    %U(%u):%G(%g) %n' $A/home/eren | sed "s|$A||"

sync
umount $A 2>/dev/null
echo
if [ "$D" -eq 0 ]; then
    echo "  TAMAM. atasOS'u acinca 'journalctl -b | grep unsafe' bos cikmali."
else
    echo "  KONTROLLERDEN BIRI TUTMADI <<< yukariya bak."
fi
echo "  Yedek ve geri alma bilgisi: $Y"
echo "  (manifest.txt: her girdinin eski sahip:grup:izin bilgisi)"
