# atasOS: yuksek cozunurluklu ekranlarda otomatik %200 olcek (Plasma X11 oturumu).
# Yer: /etc/xdg/plasma-workspace/env/atasos-hidpi.sh  (startplasma her oturumda "source" eder).
# Ekranin EDID'inden fiziksel DPI hesaplanir; >= 170 dpi ise Qt, GTK/Firefox ve imlec iki kat olur.
# Devre disi kalir: kullanici Sistem Ayarlari > Ekran'dan olcek sectiyse (kdeglobals ScaleFactor) ya da
# kendi ~/.config/plasma-workspace/env/atasos-olcek.sh dosyasi varsa.
# Elle secim: ~/.config/atasos-olcek veya /etc/atasos/olcek dosyasina  OLCEK=1 | OLCEK=2 | OLCEK=otomatik
atasos_hidpi() {
    _c="${XDG_CONFIG_HOME:-$HOME/.config}"
    [ -f "$_c/plasma-workspace/env/atasos-olcek.sh" ] && return 0
    [ -f "$_c/kdeglobals" ] && grep -q '^ScaleFactor=' "$_c/kdeglobals" && return 0
    _o=""
    for _f in "$_c/atasos-olcek" /etc/atasos/olcek; do
        [ -r "$_f" ] && { _o=$(sed -n 's/^OLCEK=//p' "$_f" | head -n1); [ -n "$_o" ] && break; }
    done
    _ad=""
    if [ -z "$_o" ] || [ "$_o" = otomatik ]; then
        _o=1; _en=0
        for _k in /sys/class/drm/card*-*; do
            [ "$(cat "$_k/status" 2>/dev/null)" = connected ] || continue
            # EDID: ilk ayrintili zamanlama tanimi (bayt 54). Yatay piksel: 56 + ust 4 bit 58; yatay mm: 66 + ust 4 bit 68
            set -- $(od -An -tu1 -j54 -N18 "$_k/edid")
            [ $# -eq 18 ] || continue
            _px=$(( $3 + ($5 / 16) * 256 )); _mm=$(( ${13} + (${15} / 16) * 256 ))
            [ "$_mm" -gt 0 ] || _mm=$(( $(od -An -tu1 -j21 -N1 "$_k/edid") * 10 ))
            [ "$_mm" -gt 0 ] && [ "$_px" -gt 0 ] || continue
            _dpi=$(( _px * 254 / (_mm * 10) ))
            # dahili ekran (eDP/LVDS/DSI) oncelikli; yoksa en yogun ekran
            case "${_k##*/}" in *-eDP-*|*-LVDS-*|*-DSI-*) _dahili=1;; *) _dahili=0;; esac
            if [ $_dahili -eq 1 ] || [ $_dpi -gt $_en ]; then
                _en=$_dpi; _ad=${_k##*/}; _ad=${_ad#card*-}
                [ $_dahili -eq 1 ] && break
            fi
        done
        [ "$_en" -ge 170 ] && _o=2
        ATASOS_EKRAN_DPI=$_en; export ATASOS_EKRAN_DPI
    fi
    [ "$_o" = 2 ] || return 0
    case "$_ad" in eDP-*|LVDS-*|DSI-*) export QT_SCREEN_SCALE_FACTORS="$_ad=2;";; *) export QT_SCREEN_SCALE_FACTORS="2";; esac
    export GDK_SCALE=2
    # Xft.dpi zaten buyutulmusse (orn. 192) GTK yazilari iki kez buyumesin
    _x=$(xrdb -query 2>/dev/null | sed -n 's/^Xft\.dpi:[[:space:]]*//p' | head -n1)
    if [ -n "$_x" ] && [ "${_x%%.*}" -gt 96 ] 2>/dev/null; then
        export GDK_DPI_SCALE=$(awk "BEGIN{printf \"%.3g\", 96/${_x%%.*}}")
    fi
    if ! grep -qs '^cursorSize=' "$_c/kcminputrc"; then
        export XCURSOR_SIZE=48
        export XCURSOR_THEME="${XCURSOR_THEME:-breeze_cursors}"
        printf 'Xcursor.size: 48\n' | xrdb -merge 2>/dev/null
    fi
    ATASOS_OLCEK=2; export ATASOS_OLCEK
}
atasos_hidpi
unset -f atasos_hidpi
unset _c _o _f _ad _en _k _px _mm _dpi _dahili _x
