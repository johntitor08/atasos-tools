#!/usr/bin/env bash
# atasos-95: SURUM IZLEYICI. Guncelleme kanalindaki (ve izlenen temel) paketlerin yayincidaki en yeni surumlerini
# bulur, archive.org'daki imzali dizinle karsilastirir. Hicbir sey indirmez/derlemez/yayinlamaz; yalniz okur.
#   - "seri" sutunu: bilerek sabit tuttugumuz seri (or. libxml2 2.13 = ABI); once o seride en yeni aranir,
#     daha yeni bir seri varsa ayrica not edilir (gecis ayri karar ister).
#   - izlenen temel paketler (kanalda henuz yok) v36/p5'teki surumle karsilastirilir.
# Kullanim (root DEGIL): bash ~/atasos-95-surum-izle.sh
set -uo pipefail
exec python3 -I - "$@" <<'PY'
import json, re, sys, urllib.request

DEPO = "https://archive.org/download/atasos-depo/atspkg.index"
UA = {"User-Agent": "atasos-surum-izle/1.0"}

def al(url, n=30):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=n) as r:
            return r.read().decode("utf-8", "replace")
    except Exception as e:
        return ""

def anahtar(v):
    return [int(x) if x.isdigit() else x for x in re.split(r"[.\-_p]", v) if x != ""]

def kararli(v):
    # KDE/GNOME gelenegi: x.y.90+ beta/RC (or. Plasma 6.3.91 = 6.4 beta)
    p = v.split(".")
    return not (len(p) >= 3 and p[2].isdigit() and int(p[2]) >= 90)

def en_yeni(surumler, seri=None):
    s = sorted({x for x in surumler if kararli(x)}, key=anahtar)
    if seri:
        s = [x for x in s if x == seri or x.startswith(seri + ".") or x.startswith(seri + "p")]
    return s[-1] if s else None

def liste(url, desen):
    return re.findall(desen, al(url))

def github(repo, desen):
    j = al(f"https://api.github.com/repos/{repo}/releases?per_page=100")
    try:
        etiketler = [r["tag_name"] for r in json.loads(j) if not r.get("prerelease") and not r.get("draft")]
    except Exception:
        etiketler = []
    out = []
    for t in etiketler:
        m = re.fullmatch(desen, t)
        if m:
            out.append(m.group(1).replace("_", "."))
    return out

def gnome(ad, sabit=None):
    seriler = liste(f"https://download.gnome.org/sources/{ad}/", r'href="(\d+\.\d+)/"')
    sv = []
    secilen = sorted(set(seriler), key=anahtar)[-3:] + ([sabit] if sabit else [])
    for s in sorted(set(secilen), key=anahtar):
        sv += liste(f"https://download.gnome.org/sources/{ad}/{s}/", ad + r"-(\d+\.\d+\.\d+)\.tar\.xz")
    return sv

KAYNAK = {
    # ad: (kaynak islevi, sabit seri ya da None, not)
    "openssl":   (lambda: github("openssl/openssl", r"openssl-(\d+\.\d+\.\d+)"), "3.5", "LTS serisi"),
    "curl":      (lambda: liste("https://curl.se/download/", r"curl-(\d+\.\d+\.\d+)\.tar\.xz"), None, ""),
    "sudo":      (lambda: liste("https://www.sudo.ws/dist/", r"sudo-(1\.9\.\d+(?:p\d+)?)\.tar\.gz"), "1.9", "PAM'siz"),
    "expat":     (lambda: github("libexpat/libexpat", r"R_(\d+_\d+_\d+)"), None, ""),
    "zlib":      (lambda: liste("https://zlib.net/", r"zlib-(\d+\.\d+(?:\.\d+)?)\.tar\.xz"), None, ""),
    "fastfetch": (lambda: github("fastfetch-cli/fastfetch", r"(\d+\.\d+\.\d+)"), None, ""),
    "libxml2":   (lambda: gnome("libxml2", "2.13"), "2.13", "2.14+ API kaldirdi (ABI)"),
    "libxslt":   (lambda: gnome("libxslt"), "1.1", "1.1.45+ libxml2 2.15 ister"),
    "libpng":    (lambda: liste("https://sourceforge.net/projects/libpng/files/libpng16/", r"libpng16/(1\.6\.\d+)/"), "1.6", ""),
    "libarchive":(lambda: github("libarchive/libarchive", r"v(\d+\.\d+\.\d+)"), None, ""),
    "libtasn1":  (lambda: liste("https://ftp.gnu.org/gnu/libtasn1/", r"libtasn1-(\d+\.\d+\.\d+)\.tar\.gz"), None, ""),
    "gnutls":    (lambda: liste("https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/", r"gnutls-(3\.8\.\d+)\.tar\.xz"), "3.8", ""),
    "glib":      (lambda: gnome("glib", "2.82"), "2.82", "seri gecisi Plasma ile birlikte"),
    "nspr":      (lambda: liste("https://ftp.mozilla.org/pub/nspr/releases/", r"v(4\.\d+(?:\.\d+)?)/"), None, ""),
    "nss":       (lambda: [m.replace("_", ".") for m in liste("https://ftp.mozilla.org/pub/security/nss/releases/", r"NSS_(3_\d+(?:_\d+)?)_RTM/")], None, ""),
    "sqlite":    (lambda: [f"{a}.{int(b)}.{int(c)}" for a, b, c in liste("https://sqlite.org/download.html", r"sqlite-autoconf-(\d)(\d\d)(\d\d)00\.tar")], None, ""),
    "libcups":   (lambda: github("OpenPrinting/cups", r"v(2\.4\.\d+)"), "2.4", "yalniz kutuphane"),
    "xdg-desktop-portal": (lambda: github("flatpak/xdg-desktop-portal", r"(1\.\d+\.\d+)"), "1.18", "1.20+ GStreamer ister"),
    "xz":        (lambda: github("tukaani-project/xz", r"v(\d+\.\d+\.\d+)"), None, ""),
    "dbus":      (lambda: liste("https://dbus.freedesktop.org/releases/dbus/", r"dbus-(1\.16\.\d+)\.tar\.xz"), "1.16", "kararli seri"),
    "freetype": (lambda: liste("https://download.savannah.gnu.org/releases/freetype/", r"freetype-(\d+\.\d+\.\d+)\.tar\.xz"), None, ""),
    "libjpeg-turbo": (lambda: github("libjpeg-turbo/libjpeg-turbo", r"(\d+\.\d+\.\d+)"), None, ""),
    "python": (lambda: liste("https://www.python.org/ftp/python/", r'href="(3\.13\.\d+)/"'), "3.13", ""),
    "git": (lambda: liste("https://mirrors.edge.kernel.org/pub/software/scm/git/", r"git-(\d+\.\d+\.\d+)\.tar\.xz"), None, ""),
    "xdg-desktop-portal-kde": (lambda: liste("https://download.kde.org/stable/plasma/", r'href="(6\.\d+\.\d+)/"') + liste("https://download.kde.org/Attic/plasma/", r'href="(6\.\d+\.\d+)/"'), "6.3", "Plasma surumuyle ayni olmali"),
}
# kanalda henuz olmayan ama izlenen temel paketler: v36/p5'teki surum
TEMEL = {
    "harfbuzz":  ("10.1.0", lambda: github("harfbuzz/harfbuzz", r"(\d+\.\d+\.\d+)"), None),
    "polkit":    ("125", lambda: github("polkit-org/polkit", r"(\d+)"), None),
    "pipewire":  ("1.2.7", lambda: [t.lstrip("v") for t in re.findall(r'"name":\s*"(\d+\.\d+\.\d+)"', al("https://gitlab.freedesktop.org/api/v4/projects/pipewire%2Fpipewire/repository/tags?per_page=100"))], "1.2"),
}

print("atasOS surum izleyici\n")
dizin = {}
for satir in al(DEPO).splitlines():
    p = satir.split()
    if len(p) >= 3:
        dizin.setdefault(p[0], []).append(p[1])
if not dizin:
    print("UYARI: archive.org dizini okunamadi; kanal surumleri bos.\n")

def yaz(ad, bizde, kaynak, seri, notu):
    try:
        hepsi = kaynak()
    except Exception:
        hepsi = []
    if not hepsi:
        print(f"  {ad:24} {bizde:12} {'?':12} {'':10} kaynak okunamadi"); return None
    seride = en_yeni(hepsi, seri) if seri else en_yeni(hepsi)
    genel = en_yeni(hepsi)
    durum = "guncel" if seride and anahtar(seride) <= anahtar(bizde) else "GUNCELLEME VAR"
    ek = f"(yeni seri: {genel})" if seri and genel and genel != seride and anahtar(genel) > anahtar(seride or "0") else ""
    print(f"  {ad:24} {bizde:12} {seride or '?':12} {durum:15} {ek} {notu}".rstrip())
    return durum == "GUNCELLEME VAR"

sayi = 0
print(f"  {'KANAL PAKETI':24} {'bizde':12} {'en yeni':12} durum")
# kanalda yayinlanmamis ama v37/v38 ISO'sunda kurulu gelen paketler (atasos-82 ile derlenip ISO'ya kondu)
ISODA = {"nspr": "4.36", "nss": "3.108", "sqlite": "3.49.1", "libcups": "2.4.11",
         "xdg-desktop-portal": "1.18.4", "xdg-desktop-portal-kde": "6.3.4"}
for ad, (kaynak, seri, notu) in KAYNAK.items():
    bizde = en_yeni(dizin.get(ad, [])) or ISODA.get(ad, "-")
    if ad in ISODA and not dizin.get(ad): notu = (notu + " (ISO'da; kanalda yok)").strip()
    if yaz(ad, bizde, kaynak, seri, notu): sayi += 1
print(f"\n  {'IZLENEN TEMEL (kanalda yok)':24} {'v36/p5':12} {'en yeni':12} durum")
for ad, (bizde, kaynak, seri) in TEMEL.items():
    if yaz(ad, bizde, kaynak, seri, ""): sayi += 1

r = al("https://www.kernel.org/releases.json")
try:
    j = json.loads(r); lts = [x["version"] for x in j["releases"] if x["moniker"] == "longterm"]
    bizde = en_yeni(dizin.get("linux", [])) or "6.16.1"
    seri = ".".join(bizde.split(".")[:2])
    ser = [x for x in j["releases"] if x["version"].startswith(seri + ".")]
    durum = ("DESTEK DISI (EOL)" if ser[0].get("iseol") else "destekleniyor") if ser else "DESTEK DISI (EOL)"
    son = ser[0]["version"] if ser else "?"
    gun = "guncel" if ser and anahtar(son) <= anahtar(bizde) else "GUNCELLEME VAR"
    if gun != "guncel": sayi += 1
    print(f"\n  cekirdek (paket linux): bizde {bizde}; {seri} serisi {durum}, en yeni {son} -> {gun}; guncel LTS: {', '.join(lts[:3])}")
except Exception:
    print("\n  cekirdek: kernel.org okunamadi")
print(f"\n  {sayi} pakette guncelleme var.")
PY
