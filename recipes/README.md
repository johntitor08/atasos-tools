# atasOS derleme tarifleri (Kasım 2026)

| Paket | Sürüm | Not |
|---|---|---|
| nspr | 4.36 | `--with-mozilla --with-pthreads --enable-64bit` |
| sqlite | 3.49.1 | `--soname=legacy` ŞART (yoksa SONAME yok) |
| nss | 3.108 | sqlite'tan SONRA, `NSS_USE_SYSTEM_SQLITE=1`, nss-standalone-1.patch |
| cups | 2.4.11 | sadece libcups: `make -C cups` |
| git | 2.51.0 | `--with-curl` (yoksa https çalışmaz) |
| NetworkManager | 1.56.0 | nmcli/libnm: aşağıdaki meson seçenekleri |
| claude-desktop | apt reposundan .deb | ar x + data.tar, chrome-sandbox 4755 |
| kernel | 6.16.1-atas6 | TCP_CONG_BBR=m, NET_SCH_FQ=m |
| kernel (atas7 taslağı) | 6.16.1 | `configs/kernel/atas7.config` fragment, aşağıya bak |
| xdg-desktop-portal | 1.18.4 | 1.20.x GStreamer ister, atasOS'ta yok |
| xdg-desktop-portal-kde | 6.3.4 | Qt CUPS'suz → `recipes/xdg-desktop-portal/` yaması |

## NetworkManager (sadece istemci)
    meson setup build --prefix=/usr --libdir=lib64 --buildtype=release \
      -Dnmcli=true -Dnmtui=false -Dintrospection=false -Dvapi=false \
      -Ddocs=false -Dman=false -Dtests=no -Dqt=false -Dovs=false -Dppp=false \
      -Dmodem_manager=false -Dlibaudit=no -Dselinux=false -Dnm_cloud_setup=false
    # yalnızca build/src/nmcli/nmcli ve build/src/libnm-client-impl/libnm.so.0.1.0 kopyalanır

## Claude Desktop
    REPO=https://downloads.claude.ai/claude-desktop/apt/stable
    DEB=$(curl -fsSL "$REPO/dists/stable/main/binary-amd64/Packages" | grep '^Filename: pool/main/c/claude-desktop/claude-desktop_' | sort -V | tail -n1 | cut -d' ' -f2)
    curl -fLO "$REPO/$DEB" && ar x claude-desktop_*.deb && tar xf data.tar.*
    sudo cp -a usr/. /usr/
    sudo chown root:root /usr/lib/claude-desktop/chrome-sandbox && sudo chmod 4755 /usr/lib/claude-desktop/chrome-sandbox
    # X11 oturumunda: claude-desktop --ozone-platform=x11

## Kernel atas7 (taslak, henüz derlenmedi)
`configs/kernel/atas7.config`, atas6 üzerine eklenecek seçenekler: MEMCG, PSI, SCHED_AUTOGROUP,
BPF_SYSCALL/JIT + CGROUP_BPF, nftables (modül), WireGuard, MGLRU, THP (madvise), zram zstd,
SECURITYFS + Landlock + Yama, varsayılan governor schedutil, zstd sıkıştırmalı kernel.
Gerçek 6.16.1 kaynağıyla doğrulandı (38 satırın 38'i son .config'e giriyor).

    cp /boot/config-6.16.1-atas6 .config
    scripts/kconfig/merge_config.sh -m .config /yol/atas7.config
    make olddefconfig

`configs/kernel/config-6.16.1-atas7` = birleştirilmiş tam sonuç (GCC 15.2 ile üretildi;
`GCC_PLUGINS=y` derleyiciye bağlı, Ubuntu GCC'de kapalı kalabilir).

## xdg-desktop-portal 1.18.4 (flatpak dosya seçici, bağlantı açma, tema, ekran görüntüsü)
    curl -fLO https://github.com/flatpak/xdg-desktop-portal/releases/download/1.18.4/xdg-desktop-portal-1.18.4.tar.xz
    meson setup build --prefix=/usr --libexecdir=libexec --buildtype=release \
      -Dgeoclue=disabled -Dlibportal=disabled -Ddocbook-docs=disabled -Dman-pages=disabled \
      -Dinstalled-tests=false -Dpytest=disabled
    ninja -C build && DESTDIR=$PWD/kok meson install -C build

## xdg-desktop-portal-kde 6.3.4 (Plasma sürümüyle aynı olmalı)
    curl -fLO https://download.kde.org/stable/plasma/6.3.4/xdg-desktop-portal-kde-6.3.4.tar.xz
    # sha256: 59c62f679d2dac721dd537d83ad3075c129d07e1056e0a592117f711979f0821
    patch -p0 -d xdg-desktop-portal-kde-6.3.4/src < recipes/xdg-desktop-portal/xdg-desktop-portal-kde-6.3.4-cupssuz.patch
    cmake -S xdg-desktop-portal-kde-6.3.4 -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBEXECDIR=libexec -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
    ninja -C build && DESTDIR=$PWD/kok cmake --install build

İki paket de aynı `kok/` ağacına kurulur; `recipes/xdg-desktop-portal/portal-kur.sh` bu ağacı
mevcut dizinlerin izinlerine dokunmadan `/` altına açar (`--kaldir` ile `dosya-listesi.txt`'teki
159 dosyayı geri siler). Sistemde önceden olan hiçbir dosyanın üzerine yazmaz. apm paketine
dönüştürülecek ilk adaylar bunlar.

## Flatpak uygulamaları (kullanıcı kurulumu, root gerekmez)
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --user flathub com.valvesoftware.Steam org.flameshot.Flameshot org.kde.gwenview
    # Spectacle Flathub'da YOK; ekran görüntüsü için Flameshot.

## Masaüstü ayarları (kullanıcı)
- HiDPI: `branding/plasma/atasos-hidpi.sh` Qt/GTK'yı 2x yapıyor ama Chromium/Electron
  (Claude, Steam) ve Firefox ölçeği `Xft.dpi`'dan okuyor. 96'da kalırsa pencereler yarım boy:
  `kwriteconfig6 --file kcmfonts --group General --key forceFontDPI 192`
  (hidpi betiği Xft.dpi > 96 görünce GDK_DPI_SCALE ile GTK yazılarını dengeliyor).
  Sadece girişte etkili: hidpi betiği GDK_DPI_SCALE=0.5'i ancak oturum açılırken Xft.dpi 192
  ise koyar. Aksi halde Firefox GDK_SCALE=2 × Xft.dpi 192 ile 4x olur. Oturumdan bağımsız
  kesin ayarlar (kullanıcı başlatıcıları):
  - Firefox: `~/.local/share/applications/firefox.desktop` → `Exec=env GDK_DPI_SCALE=0.5 /opt/firefox/firefox %u`
    (varsayılan tarayıcı girdisi `userapp-Firefox-*.desktop` için de aynısı)
  - Claude Desktop: menü ve `~/.config/autostart/claude-desktop.desktop` Exec'ine `--force-device-scale-factor=2`
  - Steam: `flatpak override --user --env=STEAM_FORCE_DESKTOPUI_SCALING=2 com.valvesoftware.Steam`
- PrtSc → Flameshot: kglobalaccel'i durdur, yaz, başlat (çalışırken yazılan değişikliği ezer):
      systemctl --user stop plasma-kglobalaccel
      kwriteconfig6 --file kglobalshortcutsrc --group services \
        --group org.flameshot.Flameshot.desktop --key Capture Print
      systemctl --user start plasma-kglobalaccel
- Gwenview varsayılan görüntüleyici: `kwriteconfig6 --file mimeapps.list --group "Default Applications" --key image/png org.kde.gwenview.desktop` (her image/* türü için).
- `~/.config/user-dirs.dirs` ŞART (aşağıdaki tuzak):
      XDG_DESKTOP_DIR="$HOME/Desktop"
      XDG_DOWNLOAD_DIR="$HOME/İndirilenler"
      XDG_PICTURES_DIR="$HOME/görsel"

## Disk: /home'u p5'e taşıma
p4 (kök, 30 GB) diskte p3 ile p2 arasında sıkışık, büyütülemez. `scripts/home-tasi.sh`:
p5'i `/mnt/atasos`'a bağlar (LFS ağacına dokunmaz), `/home`'u `/mnt/atasos/home-kurulu`'ya
rsync'ler, fstab'a bind olarak ekler. Reboot sonrası `scripts/eski-home-sil.sh` kökteki eski
kopyayı (`mount --bind /` altından) siler. Kopyalarken Steam vb. kapalı olsun.

## Bilinen tuzaklar
- `sudo nmcli con up` → KWallet'e erişemez, bağlantı düşer. sudo'suz kullan.
- NSS nesne dizinleri `*.OBJ` — temiz derleme için `find nss -name '*.OBJ' -prune -exec rm -rf {} +`
- Kernel: `make modules` tek başına modpost hatası verir, `make vmlinux modules` gerekir.
- xdg-desktop-portal 1.20.x `gstreamer-pbutils-1.0` olmadan derlenmez → 1.18.4 kullan.
- Qt PrintSupport CUPS'suz (`QT_FEATURE_cups -1`) → portal-kde `print.cpp` derlenmez; yama CUPS
  kısımlarını `#if QT_CONFIG(cups)` arkasına alır (PDF'e yazdırma çalışır, N-up seçenekleri yok).
- `~/.config/user-dirs.dirs` yoksa Qt "Resimler" için `~/Pictures` kullanır; klasör yoksa
  portal-kde ekran görüntüsünü kaydedemez ve Flameshot "Ekran resmi alınamadı" der. ISO'da
  kullanıcı klasörleri (user-dirs) oluşturulmalı.
- Portal kurulduktan sonra Flameshot X11 yerine portalı kullanır; etkileşimsiz çekim izni:
  `flatpak permission-set screenshot screenshot org.flameshot.Flameshot yes`
- portal-kde servisi Kirigami "Fusion" stil eklentisini bulamıyor (QML onay pencereleri
  sorunlu olabilir) — açık konu.
- LFS fstab'ında `devpts` satırı `devtmpfs`'ten önceydi; `findmnt --verify` hata verir.
  systemd umursamaz ama sırayı düzelt: devtmpfs önce.
