#!/usr/bin/env bash
# atasos-99: p4'te (kurulu atasOS) Claude masaustu uygulamasinin "cok yakin" (asiri buyuk) gorunmesinin teshisi.
#   p4 SALT-OKUNUR baglanir (ro,noload: gunluk bile yeniden oynatilmaz), hicbir dosya degismez.
#   Yalniz olcekle ilgili ayarlar yazdirilir: ekran olcegi, XWayland olcegi, DPI, ortam degiskenleri,
#   Claude'un nasil kuruldugu/baslatildigi ve kendi olcek/yakinlastirma kayitlari (oturum bilgisi YAZDIRILMAZ).
# Kullanim (Konsole'da): sudo bash ~/atasos-99-p4-olcek-teshis.sh
set -uo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi calisiyor. Hicbir sey yapilmadi."; exit 1; }
DEV=/dev/nvme0n1p4
[ "$(blkid -s LABEL -o value $DEV)" = atasos-kurulu ] || { echo "HATA: $DEV etiketi atasos-kurulu degil"; exit 1; }
grep -q "^$DEV " /proc/mounts && { echo "  p4 baska bir yerde bagli (Dolphin?); once ayir. Hicbir sey yapilmadi."; exit 1; }
M=/mnt/atasos-p4-ro; mkdir -p $M
mount -o ro,noload $DEV $M || { echo "HATA: p4 salt-okunur baglanamadi"; exit 1; }
trap 'cd /; umount $M 2>/dev/null || echo "  UYARI: p4 ayrilamadi"' EXIT
# p4'un /home'u p5:/home-kurulu'dan bind ile gelir (fstab) -> p5 de SALT-OKUNUR baglanir
D5=/dev/nvme0n1p5; M5=/mnt/atasos-p5-ro
echo "  p4 fstab /home satiri: $(grep -E '[[:space:]]/home[[:space:]]' $M/etc/fstab | tr -s ' \t' ' ')"
if [ "$(blkid -s LABEL -o value $D5)" = atasOS ] && ! grep -q "^$D5 " /proc/mounts; then
    mkdir -p $M5 && mount -o ro,noload $D5 $M5 && trap 'cd /; umount $M 2>/dev/null || echo "  UYARI: p4 ayrilamadi"; umount $M5 2>/dev/null || echo "  UYARI: p5 ayrilamadi"' EXIT
else echo "  UYARI: p5 baglanamadi (zaten bagli ya da etiket farkli)"; fi

echo "== Claude nasil kurulu"
ls -la $M/usr/bin/claude* $M/usr/lib/claude-desktop/claude-desktop $M/opt/*/claude* 2>/dev/null | sed 's|'$M'||'
ls -d $M/var/lib/flatpak/app/*laude* $M/home/*/.local/share/flatpak/app/*laude* 2>/dev/null | sed 's|'$M'||'
find $M/home -maxdepth 3 -iname '*claude*.AppImage' 2>/dev/null | sed 's|'$M'||'
grep -rH '^Exec=' $M/usr/share/applications/*laude*.desktop $M/home/*/.local/share/applications/*laude*.desktop \
    $M/var/lib/flatpak/exports/share/applications/*laude*.desktop 2>/dev/null | sed 's|'$M'||'

echo; echo "== kullanicilar (p4 /etc/passwd, uid>=1000):"
awk -F: '$3>=1000 && $3<60000 {print "   "$1" uid="$3" ev="$6}' $M/etc/passwd
echo "   /home: $(ls -la $M/home 2>&1 | tail -n +2 | awk '{print $1,$3,$NF}' | tr '\n' ';')"
for EV in $(awk -F: '$3>=1000 && $3<60000 {print $6}' $M/etc/passwd); do
    H=$M$EV
    [ -L "$H" ] && { echo "   $EV bir baglanti: $(readlink "$H")"; H=$M$(readlink "$H"); }
    [ -d "$H/.config" ] || { [ -d "$M5/home-kurulu/${EV#/home/}/.config" ] && H=$M5/home-kurulu/${EV#/home/} && echo "   ev p5:/home-kurulu'da"; }
    [ -d "$H/.config" ] || { echo "   $EV/.config yok"; continue; }
    echo; echo "== kullanici: $EV"
    echo "-- ekran olcegi (kwinoutputconfig.json):"
    python3 -I - "$H/.config/kwinoutputconfig.json" <<'EOF' 2>/dev/null || echo "   (dosya yok -> varsayilan olcek)"
import json,sys
for blk in json.load(open(sys.argv[1])):
    for o in blk.get("data",[]):
        if isinstance(o,dict) and "scale" in o:
            m=o.get("mode",{}); print("  ", o.get("connectorName"), "olcek", o["scale"], "mod", m.get("width"), "x", m.get("height"))
EOF
    echo "-- kwinrc [Xwayland]:"; sed -n '/^\[Xwayland\]/,/^\[/p' "$H/.config/kwinrc" 2>/dev/null | grep -v '^\[' | sed 's/^/   /'
    echo "-- kdeglobals/kcmfonts:"; grep -hiE 'ScaleFactor|forceFontDPI|^font=' "$H/.config/kdeglobals" "$H/.config/kcmfonts" 2>/dev/null | sed 's/^/   /'
    echo "-- Xresources:"; grep -hi dpi "$H/.Xresources" "$H/.Xdefaults" 2>/dev/null | sed 's/^/   /'
    echo "-- ortam (environment.d, plasma-workspace/env, electron bayraklari):"
    grep -hiE 'SCALE|DPI|GDK_|QT_|ELECTRON|OZONE' "$H"/.config/environment.d/* "$H"/.config/plasma-workspace/env/* 2>/dev/null | sed 's/^/   /'
    for f in "$H"/.config/*flags*.conf; do [ -f "$f" ] && { echo "   ${f##*/}:"; sed 's/^/     /' "$f"; }; done
    for C in "$H/.config/Claude" "$H/.var/app/"*laude*/config/Claude; do
        [ -d "$C" ] || continue
        echo "-- Claude ayarlari: ${C#$M}"
        python3 -I - "$C" <<'EOF' 2>/dev/null
import json,sys,os
for n in ("config.json","window-state.json","Preferences"):
    p=os.path.join(sys.argv[1],n)
    try: d=json.load(open(p))
    except Exception: continue
    def walk(o,yol=""):
        if isinstance(o,dict):
            for k,v in o.items():
                if any(s in k.lower() for s in ("scale","zoom","width","height","bounds")) and not isinstance(v,(dict,list)):
                    print("  ", n, yol+k, "=", v)
                walk(v,yol+k+".")
    walk(d)
EOF
    done
done
echo; echo "== sistem geneli ortam:"
grep -hiE 'SCALE|DPI|GDK_|QT_|ELECTRON|OZONE' $M/etc/environment $M/etc/profile.d/* $M/etc/environment.d/* $M/usr/lib/environment.d/* 2>/dev/null | sed 's/^/   /'
echo "== bitti (p4'te hicbir sey degismedi)"
