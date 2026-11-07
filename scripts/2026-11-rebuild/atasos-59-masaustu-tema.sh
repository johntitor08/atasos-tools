#!/usr/bin/env bash
# atasOS masaustu ozellestirmesi (p5'e; sonraki ISO buradan alir):
#   1) Duvar kagidi "atasOS" (/usr/share/wallpapers/atasOS, 8 cozunurluk): masaustu, kilit ekrani, giris ekrani
#   2) Breeze Koyu + atasOS mavisi (#3daee9): KDE renkleri, Plasma temasi, simgeler; GTK/Firefox koyu (prefer-dark)
#   3) Panel: menu dugmesinde atasOS logosu; sabit uygulamalar Dolphin, Firefox, Konsole, Kate, Sistem Ayarlari
#   4) GRUB temasi /usr/share/grub/themes/atasos (DejaVu yazi tipleri grub-mkfont ile uretilir)
#   5) Giris temasi guncellemesi: duvar kagidi arka plan, yeni sistemde varsayilan X11 oturumu, klavye genisligi
#   6) Dokunmatik yuzey: dokunarak tiklama (X11 libinput varsayilani kapali)
# Varsayilanlar /etc/xdg ve /etc/skel'e yazilir (yeni kullanicilar). Senin eren hesabina da uygulanir;
# degisen her dosya once /var/lib/atasos-paketler/yedek-59-<tarih>/ altina kopyalanir.
# Kullanim: sudo bash /home/eren/atasos-59-masaustu-tema.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root gerekli: sudo bash $0"; exit 1; }
exec 9>/run/atasos-betik.lock
flock -n 9 || { echo "  Baska bir atasOS betigi su an calisiyor. O bitince tekrar calistir."; exit 1; }
G=/home/eren/atas3-loglar/gelistirme
for f in $G/duvar/atasOS/metadata.json $G/duvar/atasOS/contents/images/1920x1080.jpg $G/grub-atasos/theme.txt $G/grub-atasos/background.png \
         $G/sddm-atasOS/Main.qml $G/sddm-atasOS/background.jpg; do [ -s "$f" ] || { echo "HATA: $f yok"; exit 1; }; done
A=/mnt/atasos; TS=$(date +%m%d-%H%M); Y=$A/var/lib/atasos-paketler/yedek-59-$TS
grep -q '^/dev/nvme0n1p5 ' /proc/mounts && { echo "  p5 baska bir yerde bagli; once onu ayir."; exit 1; }
mkdir -p $A; mount /dev/nvme0n1p5 $A || { echo "HATA: p5"; exit 1; }
temizle(){ for m in $A/proc $A/dev; do mountpoint -q $m && umount $m; done; sync; cd /; umount $A 2>/dev/null || echo "  UYARI: p5 ayrilamadi"; }
trap temizle EXIT
mkdir -p $Y
yedek(){ for p in "$@"; do [ -e "$A$p" ] || continue; mkdir -p "$Y$(dirname "$p")"; cp -a "$A$p" "$Y$p"; done; }
cr(){ chroot $A /usr/bin/env -i HOME=/root TERM=dumb LC_ALL=C LANG=C PATH=/usr/bin:/usr/sbin:/bin:/sbin /bin/bash -c "$1"; }
mount --bind /dev $A/dev; mount -t proc proc $A/proc
EU=$(stat -c %u:%g $A/home/eren 2>/dev/null)
DUVAR=file:///usr/share/wallpapers/atasOS/
EH=$A/home/eren/.config

# kconfig dosyasina deger yaz: kyaz <dosya> "<[Grup][Alt]>" anahtar deger   (dosya yoksa olusturur)
kyaz(){ python3 -I - "$@" <<'PY'
import sys, os, re
yol, grup, anahtar, deger = sys.argv[1:5]
satirlar = open(yol, encoding="utf-8").read().splitlines() if os.path.exists(yol) else []
baslik = grup
i = next((n for n, l in enumerate(satirlar) if l.strip() == baslik), None)
if i is None:
    if satirlar and satirlar[-1].strip(): satirlar.append("")
    satirlar += [baslik, f"{anahtar}={deger}"]
else:
    j = i + 1
    while j < len(satirlar) and not satirlar[j].startswith("["): j += 1
    for k in range(i + 1, j):
        if re.match(rf"^{re.escape(anahtar)}\s*=", satirlar[k]):
            satirlar[k] = f"{anahtar}={deger}"; break
    else:
        k = j
        while k > i + 1 and not satirlar[k - 1].strip(): k -= 1
        satirlar.insert(k, f"{anahtar}={deger}")
os.makedirs(os.path.dirname(yol), exist_ok=True)
open(yol, "w", encoding="utf-8").write("\n".join(satirlar) + "\n")
PY
}
# BreezeDark.colors'taki renk gruplarini bir kdeglobals'a kopyala (var olan renk gruplari degistirilir)
renkler(){ python3 -I - "$A/usr/share/color-schemes/BreezeDark.colors" "$1" <<'PY'
import sys, os
kaynak, hedef = sys.argv[1:3]
def oku(y):
    gr, sira, cur = {}, [], None
    if os.path.exists(y):
        for l in open(y, encoding="utf-8").read().splitlines():
            if l.startswith("[") and l.rstrip().endswith("]"):
                cur = l.strip(); sira.append(cur); gr.setdefault(cur, [])
            elif cur is None:
                gr.setdefault("", []).append(l); sira.insert(0, "") if "" not in sira else None
            else:
                gr[cur].append(l)
    return gr, sira
k, ks = oku(kaynak); h, hs = oku(hedef)
for g in ks:
    if g.startswith("[Colors:") or g.startswith("[ColorEffects:") or g == "[WM]":
        if g not in h: hs.append(g)
        h[g] = [l for l in k[g] if l.strip()]
out = []
for g in hs:
    if g: out.append(g)
    out += [l for l in h[g] if l.strip()]
    out.append("")
open(hedef, "w", encoding="utf-8").write("\n".join(out).rstrip() + "\n")
PY
}
# appletsrc: masaustu containment'inin duvar kagidi + kickoff simgesi + panel sabitleri
panel(){ python3 -I - "$1" "$DUVAR" <<'PY'
import sys, re
yol, duvar = sys.argv[1:3]
s = open(yol, encoding="utf-8").read().splitlines()
def gruplar():
    return {i: l.strip() for i, l in enumerate(s) if l.startswith("[")}
def bolum(baslik):
    g = gruplar(); i = next((n for n, h in g.items() if h == baslik), None)
    if i is None: return None, None
    j = next((n for n in sorted(g) if n > i), len(s)); return i, j
def anahtar(baslik, k, v):
    i, j = bolum(baslik)
    if i is None:
        if s and s[-1].strip(): s.append("")
        s.extend([baslik, f"{k}={v}"]); return
    for n in range(i + 1, j):
        if s[n].startswith(k + "="): s[n] = f"{k}={v}"; return
    s.insert(i + 1, f"{k}={v}")
def deger(baslik, k):
    i, j = bolum(baslik)
    if i is None: return None
    for n in range(i + 1, j):
        if s[n].startswith(k + "="): return s[n].split("=", 1)[1]
cids = sorted({m.group(1) for l in s for m in [re.match(r"^\[Containments\]\[(\d+)\]$", l.strip())] if m}, key=int)
masa = [c for c in cids if deger(f"[Containments][{c}]", "plugin") in ("org.kde.plasma.folder", "org.kde.desktopcontainment")]
for c in masa:
    anahtar(f"[Containments][{c}]", "wallpaperplugin", "org.kde.image")
    anahtar(f"[Containments][{c}][Wallpaper][org.kde.image][General]", "Image", duvar)
    anahtar(f"[Containments][{c}][Wallpaper][org.kde.image][General]", "SlidePaths", "/usr/share/wallpapers/")
kick = []; gorev = []
for l in s:
    m = re.match(r"^\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]$", l.strip())
    if m:
        p = deger(l.strip(), "plugin")
        if p in ("org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.kickerdash"): kick.append(m.groups())
        if p in ("org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"): gorev.append(m.groups())
for c, a in kick:
    anahtar(f"[Containments][{c}][Applets][{a}][Configuration][General]", "icon", "atasos")
for c, a in gorev:
    anahtar(f"[Containments][{c}][Applets][{a}][Configuration][General]", "launchers",
            "applications:org.kde.dolphin.desktop,applications:firefox.desktop,applications:org.kde.konsole.desktop,applications:org.kde.kate.desktop,applications:systemsettings.desktop")
open(yol, "w", encoding="utf-8").write("\n".join(s).rstrip() + "\n")
print(f"    masaustu: {len(masa)}, menu dugmesi: {len(kick)}, gorev cubugu: {len(gorev)}")
PY
}

echo "########## 1/6  DUVAR KAGIDI ##########"
rm -rf $A/usr/share/wallpapers/atasOS; cp -r $G/duvar/atasOS $A/usr/share/wallpapers/atasOS
chmod -R u=rwX,go=rX $A/usr/share/wallpapers/atasOS; chown -R 0:0 $A/usr/share/wallpapers/atasOS
echo "  /usr/share/wallpapers/atasOS: $(ls $A/usr/share/wallpapers/atasOS/contents/images | tr '\n' ' ')"
# varsayilan duvar kagidi (Kubuntu'nun yontemi): yeni etkinlikte/ilk girisste olusturulan masaustu da atasOS'u alir
for t in breeze-dark default breeze-light; do
    f=$A/usr/share/plasma/desktoptheme/$t/plasmarc; [ -f $f ] || continue
    yedek /usr/share/plasma/desktoptheme/$t/plasmarc
    kyaz $f "[Wallpaper]" defaultWallpaperTheme atasOS
    kyaz $f "[Wallpaper]" defaultFileSuffix .jpg
    echo "  $t/plasmarc: $(grep -E '^defaultWallpaperTheme=' $f)"
done
# asil kaynak (v31 sanal makine testinde bulundu): yeni masaustu, gorunum paketinin defaults dosyasindaki
# [Wallpaper] Image degerini alir (Breeze paketlerinde "Next")
for t in org.kde.breezedark.desktop org.kde.breeze.desktop org.kde.breezetwilight.desktop; do
    f=$A/usr/share/plasma/look-and-feel/$t/contents/defaults; [ -f $f ] || continue
    yedek /usr/share/plasma/look-and-feel/$t/contents/defaults
    kyaz $f "[Wallpaper]" Image atasOS
    echo "  $t: $(grep -A1 '^\[Wallpaper\]' $f | tail -1)"
done

echo
echo "########## 2/6  BREEZE KOYU + atasOS MAVISI ##########"
yedek /etc/xdg/kdeglobals /etc/xdg/plasmarc /etc/xdg/kscreenlockerrc /etc/gtk-3.0/settings.ini /etc/gtk-4.0/settings.ini
X=$A/etc/xdg; mkdir -p $X
renkler $X/kdeglobals
kyaz $X/kdeglobals "[General]" ColorScheme BreezeDark
kyaz $X/kdeglobals "[General]" AccentColor "61,174,233"
kyaz $X/kdeglobals "[KDE]" LookAndFeelPackage org.kde.breezedark.desktop
kyaz $X/kdeglobals "[Icons]" Theme breeze-dark
kyaz $X/plasmarc "[Theme]" name breeze-dark
kyaz $X/kscreenlockerrc "[Greeter][Wallpaper][org.kde.image][General]" Image "$DUVAR"
for v in 3.0 4.0; do
    kyaz $A/etc/gtk-$v/settings.ini "[Settings]" gtk-application-prefer-dark-theme 1
    kyaz $A/etc/gtk-$v/settings.ini "[Settings]" gtk-icon-theme-name breeze-dark
    kyaz $A/etc/gtk-$v/settings.ini "[Settings]" gtk-cursor-theme-name breeze_cursors
done
echo "  /etc/xdg/kdeglobals: $(grep -c '^\[Colors:' $X/kdeglobals) renk grubu, $(grep -E '^(ColorScheme|LookAndFeelPackage|Theme)=' $X/kdeglobals | tr '\n' ' ')"
echo "  /etc/xdg/plasmarc: $(grep '^name=' $X/plasmarc)   GTK: prefer-dark"

echo
echo "########## 3/6  PANEL + KULLANICILAR (skel + eren) ##########"
yedek /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
echo "  /etc/skel:"; panel $A/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc
if [ -d $EH ]; then
    yedek /home/eren/.config/kdeglobals /home/eren/.config/plasmarc /home/eren/.config/kscreenlockerrc /home/eren/.config/plasma-org.kde.plasma.desktop-appletsrc /home/eren/.config/gtk-3.0/settings.ini /home/eren/.config/gtk-4.0/settings.ini
    renkler $EH/kdeglobals
    kyaz $EH/kdeglobals "[General]" ColorScheme BreezeDark
    kyaz $EH/kdeglobals "[General]" AccentColor "61,174,233"
    kyaz $EH/kdeglobals "[KDE]" LookAndFeelPackage org.kde.breezedark.desktop
    kyaz $EH/kdeglobals "[Icons]" Theme breeze-dark
    kyaz $EH/plasmarc "[Theme]" name breeze-dark
    kyaz $EH/kscreenlockerrc "[Greeter][Wallpaper][org.kde.image][General]" Image "$DUVAR"
    for v in 3.0 4.0; do kyaz $EH/gtk-$v/settings.ini "[Settings]" gtk-application-prefer-dark-theme 1; done
    echo "  eren:"; [ -f $EH/plasma-org.kde.plasma.desktop-appletsrc ] && panel $EH/plasma-org.kde.plasma.desktop-appletsrc
    chown -R $EU $EH/kdeglobals $EH/plasmarc $EH/kscreenlockerrc $EH/plasma-org.kde.plasma.desktop-appletsrc $EH/gtk-3.0 $EH/gtk-4.0 2>/dev/null
    grep -q '^ScaleFactor=' $EH/kdeglobals && echo "  eren olcek ayari korundu: $(grep -E '^(ScaleFactor|ScreenScaleFactors)=' $EH/kdeglobals | tr '\n' ' ')"
    rm -f $A/home/eren/.cache/ksycoca6_* $A/home/eren/.cache/plasma_theme_*.kcache $A/home/eren/.cache/icon-cache.kcache 2>/dev/null
fi

echo
echo "########## 4/6  GRUB TEMASI ##########"
GT=$A/usr/share/grub/themes/atasos; rm -rf $GT; mkdir -p $GT; cp $G/grub-atasos/* $GT/
cr 'F=/usr/share/fonts/dejavu; T=/usr/share/grub/themes/atasos
    for z in 16 24; do grub-mkfont -s $z -o $T/dejavu-$z.pf2 $F/DejaVuSans.ttf; done
    for z in 24 32; do grub-mkfont -s $z -o $T/dejavu-bold-$z.pf2 $F/DejaVuSans-Bold.ttf; done'
echo "  /usr/share/grub/themes/atasos: $(ls $GT | grep -c .) dosya, yazi tipleri: $(ls $GT/*.pf2 2>/dev/null | wc -l)/4"
[ "$(ls $GT/*.pf2 2>/dev/null | wc -l)" -eq 4 ] || echo "  UYARI: grub-mkfont yazi tiplerini uretemedi <<<"

echo
echo "########## 5/6  GIRIS TEMASI ##########"
yedek /usr/share/sddm/themes/atasOS
install -m644 $G/sddm-atasOS/Main.qml $G/sddm-atasOS/background.jpg $G/sddm-atasOS/theme.conf $A/usr/share/sddm/themes/atasOS/
echo "  tema: $(ls $A/usr/share/sddm/themes/atasOS | tr '\n' ' ')"
echo
echo "########## 6/6  DOKUNMATIK YUZEY: dokunarak tiklama ##########"
# X11'de libinput varsayilani "Tapping off": hafif dokunus tiklama sayilmiyor, yuzeye bastirmak gerekiyordu
# (Kubuntu'nun Wayland oturumunda Plasma bunu acik getiriyor). Tum yeni kullanicilar + canli ISO icin Xorg ayari:
mkdir -p $A/etc/X11/xorg.conf.d
cat > $A/etc/X11/xorg.conf.d/30-atasos-dokunmatik.conf <<'EOF'
# atasOS: dokunmatik yuzeyde dokunarak tiklama, dokunup surukleme, yazarken yanlis tiklamayi engelleme
Section "InputClass"
    Identifier "atasOS dokunmatik yuzey"
    MatchIsTouchpad "on"
    MatchDriver "libinput"
    Option "Tapping" "on"
    Option "TappingDrag" "on"
    Option "DisableWhileTyping" "on"
EndSection
EOF
echo "  /etc/X11/xorg.conf.d/30-atasos-dokunmatik.conf yazildi"
ls $A/usr/share/X11/xorg.conf.d/*libinput* $A/etc/X11/xorg.conf.d/*libinput* 2>/dev/null | sed "s|^$A|  libinput surucu ayari: |"
[ -n "$(find $A/usr/lib*/xorg/modules/input -name 'libinput_drv.so' 2>/dev/null)" ] && echo "  xf86-input-libinput: var" || echo "  UYARI: libinput_drv.so bulunamadi (Xorg ayari etkisiz olabilir) <<<"
# eren: Plasma'nin X11 dokunmatik yuzey ayari (aygit adiyla); varsa mevcut degerler korunur, yalniz bu uc anahtar yazilir
if [ -d $EH ]; then
    yedek /home/eren/.config/touchpadxlibinputrc
    for ad in "SYNA2393:00 06CB:CD48 Touchpad"; do
        kyaz $EH/touchpadxlibinputrc "[$ad]" tapToClick true
        kyaz $EH/touchpadxlibinputrc "[$ad]" tapAndDrag true
        kyaz $EH/touchpadxlibinputrc "[$ad]" disableWhileTyping true
    done
    chown $EU $EH/touchpadxlibinputrc
    echo "  eren touchpadxlibinputrc: $(grep -c '=true' $EH/touchpadxlibinputrc) ayar"
fi

echo
echo "  Yedek: ${Y#$A}"
echo "  Bitti. atasOS'u acinca: koyu tema, atasOS duvar kagidi, menude atasOS logosu."
