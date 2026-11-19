# atasOS (atasos-masaustu 1.2): %200 olcekte GTK uygulamalarinin (Firefox dahil) yazi DPI'i.
# Yer: /etc/xdg/plasma-workspace/env/ ; atasos-hidpi.sh'den SONRA calisir (alfabetik) ve onun ATASOS_OLCEK'ine bakar.
# Neden: KDE (kde-gtk-config) GTK'ya Xft/DPI'i kcmfonts 'forceFontDPI'dan verir; anahtar yoksa 96 verir. atasos-hidpi.sh
# GDK_DPI_SCALE=0.5 koydugu icin GTK yazilari 96*0.5=48 DPI'a, Firefox yarim boya dusuyordu (v37 gercek donanim testi).
# Kullanici kendi degerini (Sistem Ayarlari > Yazi Tipleri) secmediyse bir kez 192 yazilir; sonra KDE'nin kendi ayaridir.
if [ "${ATASOS_OLCEK:-1}" = 2 ]; then
    _k="${XDG_CONFIG_HOME:-$HOME/.config}/kcmfonts"
    if ! grep -qs '^forceFontDPI=' "$_k"; then
        command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file kcmfonts --group General --key forceFontDPI 192
    fi
    unset _k
fi
