#!/usr/bin/env bash
# Plasma panelinde (gorev cubugu) Firefox/Konsole yok.
# Varsayilan panel "preferred://browser" kullanir; atasOS'ta varsayilan tarayici ayarli degil -> simge yok.
# 1) Panel ayarini goster  2) Gorev yoneticisine Firefox + Dolphin + Konsole sabitle
# 3) Firefox'u varsayilan tarayici yap. atasOS KAPALIYKEN calistir (Plasma acikken ayari ezer).
# Kullanim: sudo bash /home/eren/atasos-34-panel-kisayol.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
A=/mnt/atasos
H=$A/home/eren
C=$H/.config
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p $A
if mountpoint -q $A; then mount -o remount,rw $A; else mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }; fi
trap 'umount $A 2>/dev/null' EXIT
F=$C/plasma-org.kde.plasma.desktop-appletsrc

echo "########## 1/3  PANELIN SU ANKI AYARI ##########"
[ -f "$F" ] || { echo "  $F yok - Plasma hic oturum acmamis olmali. Iptal."; exit 1; }
echo "  gorev yoneticisi uygulamaciklari:"
grep -nE '^plugin=org\.kde\.plasma\.(icontasks|taskmanager)' "$F" | sed 's/^/    satir /'
echo "  mevcut sabitler (launchers):"
grep -nE '^launchers=' "$F" | sed 's/^/    satir /' || echo "    (hic yok - varsayilan: preferred://browser vb.)"
echo "  uygulama dosyalari:"
for d in firefox.desktop org.kde.konsole.desktop org.kde.dolphin.desktop; do
    printf '    %-26s %s\n' "$d" "$([ -f $A/usr/share/applications/$d ] && echo VAR || echo YOK)"
done

echo
echo "########## 2/3  PANELE SABITLE ##########"
cp -p "$F" "$F.yedek-$TS"
python3 -I - "$F" <<'PY'
import re, sys
yol = sys.argv[1]
satirlar = open(yol, encoding="utf-8").read().split("\n")
L = "launchers=applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop"
# gorev yoneticisi applet gruplarini bul: [Containments][X][Applets][Y] + plugin=...tasks/taskmanager
gruplar, grup = [], None
for s in satirlar:
    m = re.match(r"^\[(.*)\]$", s)
    if m: grup = m.group(0); continue
    if grup and re.match(r"^plugin=org\.kde\.plasma\.(icontasks|taskmanager)$", s):
        gruplar.append(grup)
if not gruplar:
    print("    gorev yoneticisi bulunamadi - degisiklik yok"); sys.exit(2)
for g in gruplar:
    hedef = g + "[Configuration][General]"
    if hedef in satirlar:
        i = satirlar.index(hedef); j = i + 1
        while j < len(satirlar) and not satirlar[j].startswith("["): j += 1
        blok = satirlar[i+1:j]
        blok = [b for b in blok if not b.startswith("launchers=")]
        satirlar[i+1:j] = [L] + blok
    else:
        satirlar += ["", hedef, L]
    print("    " + hedef + "  <- sabitlendi")
open(yol, "w", encoding="utf-8").write("\n".join(satirlar))
PY
R=$?
[ $R -eq 0 ] || { echo "  degisiklik yapilamadi (kod $R), yedekten geri aliniyor"; cp -p "$F.yedek-$TS" "$F"; exit 1; }
echo "  yeni sabitler:"; grep -nE '^launchers=' "$F" | sed 's/^/    satir /'

echo
echo "########## 3/3  VARSAYILAN TARAYICI ##########"
M=$C/mimeapps.list
[ -f "$M" ] && cp -p "$M" "$M.yedek-$TS"
python3 -I - "$M" <<'PY'
import sys, os
yol = sys.argv[1]
eski = open(yol, encoding="utf-8").read().split("\n") if os.path.exists(yol) else []
turler = ["x-scheme-handler/http","x-scheme-handler/https","text/html","application/xhtml+xml"]
cikti, grup = [], None
for s in eski:
    if s.startswith("["): grup = s
    if grup == "[Default Applications]" and any(s.startswith(t+"=") for t in turler): continue
    cikti.append(s)
if "[Default Applications]" not in cikti:
    cikti += ["", "[Default Applications]"]
i = cikti.index("[Default Applications]")
cikti[i+1:i+1] = [t + "=firefox.desktop" for t in turler]
open(yol, "w", encoding="utf-8").write("\n".join(cikti).strip("\n") + "\n")
PY
K=$C/kdeglobals
if grep -q '^BrowserApplication=' "$K" 2>/dev/null; then sed -i 's/^BrowserApplication=.*/BrowserApplication=firefox.desktop/' "$K"
elif grep -q '^\[General\]' "$K" 2>/dev/null; then sed -i '/^\[General\]/a BrowserApplication=firefox.desktop' "$K"
else printf '\n[General]\nBrowserApplication=firefox.desktop\n' >> "$K"; fi
chown 1001:1001 "$F" "$M" "$K"
echo "  mimeapps.list:"; grep -E 'firefox' "$M" | sed 's/^/    /'
echo "  kdeglobals  : $(grep '^BrowserApplication=' "$K")"

echo
echo "########## 4/4  OLCEK %200 + FARE IMLECI ##########"
echo "  --- Eylul'de yazilan olcek ayarlari su an ne durumda ---"
for f in kdeglobals kcmfonts kcminputrc kwinrc; do
    [ -f "$C/$f" ] || { printf '    %-11s yok\n' "$f"; continue; }
    v=$(grep -E '^(ScaleFactor|ScreenScaleFactors|forceFontDPI|cursorSize|cursorTheme)=' "$C/$f" | tr '\n' ' ')
    printf '    %-11s %s\n' "$f" "${v:-(olcek satiri yok)}"
done
for f in kcmfonts kcminputrc; do [ -f "$C/$f" ] && cp -p "$C/$f" "$C/$f.yedek-$TS"; done
# Ayar dosyalari (KDE'nin kendi yontemi) - yeniden yaz
python3 -I - "$C" <<'PY'
import sys, os
C = sys.argv[1]
def ayarla(dosya, grup, anahtar, deger):
    yol = os.path.join(C, dosya)
    s = open(yol, encoding="utf-8").read().split("\n") if os.path.exists(yol) else []
    g = "[" + grup + "]"
    if g not in s: s += ["", g]
    i = s.index(g) + 1; j = i
    while j < len(s) and not s[j].startswith("["): j += 1
    blok = [b for b in s[i:j] if not b.startswith(anahtar + "=")]
    s[i:j] = [anahtar + "=" + deger] + blok
    open(yol, "w", encoding="utf-8").write("\n".join(s).strip("\n") + "\n")
ayarla("kdeglobals", "KScreen", "ScaleFactor", "2")
ayarla("kdeglobals", "KScreen", "ScreenScaleFactors", "eDP-1=2;")
ayarla("kcmfonts",   "General", "forceFontDPI", "192")
ayarla("kcminputrc", "Mouse",   "cursorSize", "48")
PY
# Ortam degiskenleri: startplasma her oturumda ~/.config/plasma-workspace/env/*.sh dosyalarini okur
E=$C/plasma-workspace/env
mkdir -p "$E"
cat > "$E/atasos-olcek.sh" <<'EOF'
# atasOS: 3000x2000 panel icin %200 olcek (X11). KDE ayar dosyalari okunmasa bile uygulanir.
export QT_SCREEN_SCALE_FACTORS="eDP-1=2;"
export XCURSOR_SIZE=48
if command -v xrdb >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    printf 'Xft.dpi: 192\nXcursor.size: 48\n' | xrdb -merge
fi
EOF
chmod 644 "$E/atasos-olcek.sh"
chown -R 1001:1001 "$C/plasma-workspace" "$C/kdeglobals" "$C/kcmfonts" "$C/kcminputrc"
echo "  --- yazilan ---"
for f in kdeglobals kcmfonts kcminputrc; do
    printf '    %-11s %s\n' "$f" "$(grep -E '^(ScaleFactor|ScreenScaleFactors|forceFontDPI|cursorSize)=' "$C/$f" | tr '\n' ' ')"
done
echo "    env betigi : ${E#$A}/atasos-olcek.sh"
echo "    xrdb       : $([ -x $A/usr/bin/xrdb ] && echo var || echo 'YOK (Xft.dpi yalnizca kcmfonts ile uygulanir)')"
echo "    imlec temasi: $(ls $A/usr/share/icons/*/cursors -d 2>/dev/null | sed "s|$A/usr/share/icons/||; s|/cursors||" | tr '\n' ' ')"
sync
echo
echo "  TAMAM. atasOS'u ac (GRUB 5. satir). Panelde Firefox, Dolphin, Konsole simgeleri,"
echo "  yazilar ve fare imleci iki kat buyuk olmali."
echo "  Geri alma: ${F#$A}.yedek-$TS ve ayni zaman damgali kcmfonts/kcminputrc yedekleri"
