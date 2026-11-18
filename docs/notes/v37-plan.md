# atasOS v37 canlı ISO: değişiklik listesi (taslak, 2026-11-18)

v36 (`scripts/2026-11-rebuild/atasos-81-v36-iso.sh`) üzerine. Kaynak: 18 Kasım oturumunda kurulu
sistemde (p4, `atasos-kurulu`) yapılan düzeltmeler ile ISO'nun üretildiği geliştirme sistemi (p5)
arasındaki fark. p5 o gün `/mnt/atasos` üzerinden tek tek kontrol edildi.

## 0. ENGELLEYİCİ: bunlar olmadan v37 üretilmez

- [x] **`home-kurulu` ISO'ya GİRMEMELİ.** → `scripts/2026-11-rebuild/atasos-87-v37-iso.sh` (sahte ağaçla test edildi: v36 listesi `.ssh/id_ed25519`'i sızdırıyor, v37 listesi dışlıyor, kontroller yakalıyor) 18 Kasım'da p4'ün `/home`'u p5'e taşındı:
      `p5:/home-kurulu` (≈14 GB: `~/.ssh` özel anahtarı, Firefox profili, Claude oturumu, Steam).
      v36 betiği yalnızca `$K/home`'u boşaltıyor ve `HARIC` listesinde `home-kurulu` yok. Betik bu
      haliyle çalışırsa hepsi `filesystem.squashfs`'e girip archive.org'da yayımlanır.
      - `HARIC=(... home-kurulu ...)` ekle; boyut hesabındaki `for h in ...` döngüsüne de ekle.
      - Son kontrol döngüsüne `'home-kurulu/'` ve `'.ssh/'` "temiz" maddeleri ekle.
      - Ek güvenlik: `mksquashfs`'ten önce `[ -e $K/home-kurulu ] && rm -rf $K/home-kurulu`
        (overlay görünümünde, p5'e dokunmaz).
- [x] **GitHub push.** Tarifler ve betikler (6 commit, `b12ab05..f05765e`) yalnızca bu makinede ve
      `~/atasos-tools-yedek.bundle` içinde. ISO'dan önce depoda olsunlar.
- [ ] Betiği yine **Kubuntu'dan** çalıştır. atasOS'ta (p4) p5 artık fstab'dan `/mnt/atasos`'a bağlı,
      betiğin "p5 başka yerde bağlı" kontrolü orada durdurur (bu doğru davranış).

## 1. Çekirdek: 6.16.1-atas7

- [ ] `configs/kernel/atas7.config` fragment'ını atas6'ya birleştir, derle (`make vmlinux modules`),
      p5'e kur. Birleşim 18 Kasım'da gerçek 6.16.1 kaynağıyla doğrulandı (38/38 satır).
- [ ] Önce bu makinede dene: systemd-oomd (MEMCG+PSI), `nft list ruleset`, BBR hâlâ çalışıyor mu
      (`sysctl net.ipv4.tcp_congestion_control`), Landlock (`/sys/kernel/security/lsm`).
- Betik en yeni `vmlinuz-*-atasN`'yi seçiyor ve `*atas[6-9]*` kontrolü atas7'yi kabul ediyor;
  değişiklik gerekmez.
- Not: p5 ve p4'teki atas6 birebir aynı (BBR/fq dahil).

## 2. Paketler (p5'te yok)

| Paket | Durum | ISO |
|---|---|---|
| xdg-desktop-portal 1.18.4 | kaynaktan derlendi, p4'e elle kuruldu | **ekle**: atspkg tarifi yazılmalı (`recipes/xdg-desktop-portal/`'dan) |
| xdg-desktop-portal-kde 6.3.4 | aynı, CUPS'suz yama ile | **ekle**: aynı tarif ya da ayrı paket |
| nspr 4.36, sqlite 3.49.1, nss 3.108 | atspkg paketi hazır (`~/atasos-paket/`) | ekle |
| libcups 2.4.11 | atspkg paketi hazır | ekle |
| atasos-xdg-open 1.0 | atspkg paketi hazır | ekle |
| claude-desktop 5.11492.5 | atspkg paketi hazır | **EKLEME**: dağıtım izni yok, yalnız depoda tarif |
| hiztesti, `90-net.conf`, `bbr.conf` | `scripts/`, `configs/etc/` | ekle |

Portal olmadan flatpak uygulamalarında (Steam dahil) dosya seçici, bağlantı açma ve koyu tema
çalışmıyor. v37'nin en görünür kazancı bu.

## 3. Varsayılan ayarlar (`/etc/xdg`, `/etc/skel`)

- [ ] **Kullanıcı klasörleri**: `/etc/skel/.config/user-dirs.dirs` + klasörlerin kendisi. Yoksa
      portal-kde ekran görüntüsünü kaydedemiyor ("Ekran resmi alınamadı"). Türkçe adlar önerisi:
      `Masaüstü`, `İndirilenler`, `Belgeler`, `Resimler`, `Müzik`, `Videolar`.
      (Kurulu sistemde elle: Desktop / İndirilenler / görsel.)
- [ ] **HiDPI'ı tek yerde topla** (`branding/plasma/atasos-hidpi.sh`, `OLCEK=2` dalı):
      - `printf 'Xft.dpi: 192\n' | xrdb -merge` (kcmfonts'a bırakma; startplasma sırasına bağlı kalmasın)
      - `export GDK_DPI_SCALE=0.5` koşulsuz (şu an yalnız Xft.dpi zaten > 96 ise konuyor; değilse
        Firefox ve Electron uygulamaları 4x oluyor)
      - `export STEAM_FORCE_DESKTOPUI_SCALING=2` (Steam flatpak'ı ortamı devralıyor)
      - Electron uygulamaları kendini yeniden başlatınca komut satırı bayraklarını kaybediyor;
        `GDK_DPI_SCALE` oturum ortamında (startplasma → systemd) olduğu için ayrıca bayrak gerekmez.
- [ ] (İsteğe bağlı) Flameshot ISO'ya girerse `/etc/xdg/kwinrulesrc` kuralı (`recipes/README.md`).
      Dikkat: kullanıcı kendi kuralını eklerse `[General] rules` anahtarı sistem kuralını ezer.

## 4. ISO'ya GİRMEYECEKLER (bu makineye özgü)

- `/home`'un p5'e taşınması, fstab bind satırları, `eski-home-sil.sh`
- Kullanıcı flatpak'ları (Steam, Flameshot, Gwenview), PrtSc kısayolu, Gwenview varsayılanı
- `~/.local/share/applications` başlatıcı değişiklikleri (Firefox, Claude ölçek bayrakları)

## 5. Doğrulama (betiğin son kontrol döngüsüne)

- [ ] `var`: `usr/libexec/xdg-desktop-portal`, `usr/libexec/xdg-desktop-portal-kde`,
      `usr/share/xdg-desktop-portal/portals/kde.portal`, `etc/skel/.config/user-dirs.dirs`,
      `usr/lib64/libnss3.so`, `usr/bin/hiztesti`
- [ ] `temiz`: `home-kurulu/`, `.ssh/`, `usr/lib/claude-desktop`
- [ ] VM testi (69/73): flatpak uygulamasında "Farklı kaydet" KDE penceresiyle açılıyor mu, link
      tarayıcıda açılıyor mu, PrtSc kaydediyor mu, 3000x2000 sanal ekranda ölçek 2x mi.

## 6. Açık konular

- portal-kde servisi `Failed to find a Kirigami platform plugin for style "Fusion"` diyor.
  Olası sebep: systemd kullanıcı ortamında `QT_QPA_PLATFORMTHEME` yok (portal systemd'den
  başlıyor, plasmashell'in ortamını almıyor). QML onay pencereleri bundan etkilenebilir.
- xdg-desktop-portal 1.20.x için GStreamer (gst-plugins-base) gerekiyor; şimdilik 1.18.4.
- udisks2 yok: KDE uygulamaları (Gwenview) "Not connected to D-Bus server" uyarısı basıyor;
  çıkarılabilir disk entegrasyonu için ileride.
