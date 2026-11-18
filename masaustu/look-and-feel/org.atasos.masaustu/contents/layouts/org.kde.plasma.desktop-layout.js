// atasOS masaustu duzeni: ortada yuzen alt panel (baslatici, gorev cubugu, tepsi, saat) + atasOS duvar kagidi.
// Yalniz yeni kullanicida ya da "atasOS gorunumunu uygula" (Hos geldin) ile duzen sifirlanirken calisir.
var panel = new Panel;
panel.location = "bottom";
panel.height = Math.round(gridUnit * 2.4);
panel.hiding = "none";
panel.floating = true;
panel.alignment = "center";
panel.lengthMode = "fit";   // Plasma 6.1+: panel icerigi kadar genis, ortada

var baslat = panel.addWidget("org.atasos.baslat");

var gorevler = panel.addWidget("org.kde.plasma.icontasks");
gorevler.currentConfigGroup = ["General"];
gorevler.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop"
]);

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
var saat = panel.addWidget("org.kde.plasma.digitalclock");
panel.addWidget("org.kde.plasma.showdesktop");

var masaustleri = desktopsForActivity(currentActivity());
for (var j = 0; j < masaustleri.length; j++) {
    masaustleri[j].wallpaperPlugin = "org.kde.image";
    masaustleri[j].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    masaustleri[j].writeConfig("Image", "file:///usr/share/wallpapers/atasOS/");
}
