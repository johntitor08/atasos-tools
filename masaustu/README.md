# atasOS masaüstü

KDE Plasma 6.3 üzerinde atasOS'un kendi görünümü ve uygulamaları. `atasos-masaustu` atspkg paketi olarak
kurulur (tarif: `scripts/2026-11-rebuild/paketler/tarifler/atasos-masaustu`); v37 ve sonrası ISO'larda yeni
kullanıcıların varsayılanıdır (`atasos-88`).

| Parça | Yer | Ne yapar |
|---|---|---|
| `color-schemes/AtasOS.colors` | `/usr/share/color-schemes/` | Gece mavisi zemin, Breeze mavisi vurgu |
| `desktoptheme/atasos` | `/usr/share/plasma/desktoptheme/` | Breeze biçimleri + atasOS renkleri (panel, açılır pencereler) |
| `look-and-feel/org.atasos.masaustu` | `/usr/share/plasma/look-and-feel/` | Varsayılanlar, ortada yüzen alt panel (`layouts/…-layout.js`), açılış ekranı (`splash/Splash.qml`), önizleme |
| `plasmoids/org.atasos.baslat` | `/usr/share/plasma/plasmoids/` | atasOS Başlat: arama (KRunner), tüm uygulamalar ızgarası, güç düğmeleri; Meta tuşu açar |
| `plasmoids/org.atasos.hosgeldin` + `bin/atasos-hosgeldin` | plasmoid + `/usr/bin` | "atasOS'a Hoş Geldin" (`plasmawindowed`): güncelle, Flathub, görünümü uygula, ayarlar, fastfetch; ilk girişte açılır, "Açılışta gösterme" ile kapanır |

Mevcut bir sistemde görünümü uygulamak: Hoş Geldin → "atasOS görünümünü uygula" (`plasma-apply-lookandfeel -a org.atasos.masaustu --resetLayout`; paneli sıfırlar).
Sanal makinede (v37 kurulu) denendi: görünüm, panel, Başlat (liste + arama), açılış ekranı, Hoş Geldin.
