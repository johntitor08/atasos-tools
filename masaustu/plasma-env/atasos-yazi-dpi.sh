# atasOS (atasos-masaustu 1.3): %200 olcekte GTK uygulamalarinin (Firefox dahil) yazi DPI'i.
# Yer: /etc/xdg/plasma-workspace/env/ ; atasos-hidpi.sh'den SONRA calisir (alfabetik) ve onun ATASOS_OLCEK'ine bakar.
# Neden: KDE (kde-gtk-config) GTK'ya Xft/DPI'i kcmfonts 'forceFontDPI'dan verir; anahtar yoksa 96 verir. atasos-hidpi.sh
# GDK_DPI_SCALE=0.5 koydugu icin GTK yazilari 96*0.5=48 DPI'a, Firefox yarim boya dusuyordu (v37 gercek donanim testi).
# Kullanici kendi degerini secmediyse 192 yazilir ve bunu BIZIM yazdigimiz bir isaret dosyasiyla hatirlanir; ekran
# sonradan %100'e donerse (baska ekran, OLCEK=1) yalniz bizim yazdigimiz 192 geri alinir. Kullanicinin degerine dokunulmaz.
_c="${XDG_CONFIG_HOME:-$HOME/.config}"; _k="$_c/kcmfonts"; _i="$_c/atasos-yazi-dpi-otomatik"
if [ "${ATASOS_OLCEK:-1}" = 2 ]; then
    if ! grep -qs '^forceFontDPI=' "$_k"; then
        command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file kcmfonts --group General --key forceFontDPI 192 && : > "$_i"
    fi
elif [ -e "$_i" ]; then
    if grep -qs '^forceFontDPI=192$' "$_k" && command -v kwriteconfig6 >/dev/null; then
        kwriteconfig6 --file kcmfonts --group General --key forceFontDPI --delete
        printf 'Xft.dpi: 96\n' | xrdb -merge 2>/dev/null
    fi
    rm -f "$_i"
fi
unset _c _k _i
