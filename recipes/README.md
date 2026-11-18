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

## Bilinen tuzaklar
- `sudo nmcli con up` → KWallet'e erişemez, bağlantı düşer. sudo'suz kullan.
- NSS nesne dizinleri `*.OBJ` — temiz derleme için `find nss -name '*.OBJ' -prune -exec rm -rf {} +`
- Kernel: `make modules` tek başına modpost hatası verir, `make vmlinux modules` gerekir.
