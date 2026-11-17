# atasOS rehberi

İndirmeden kuruluma, ilk açılıştan bilinen sorunlara kadar atasOS hakkında
bilinmesi gerekenler.

**İndir:** <https://archive.org/details/atasos-live>
(doğrudan bağlantı: [atasos-live-v36.iso](https://archive.org/download/atasos-live/atasos-live-v36.iso),
2,9 GB)

```
sha256  c1513c3e102c87ce1a2fb1d5eda8ec9fd13d5f6d5f0ea0e02589dff1eafab101  atasos-live-v36.iso
```

## İçindekiler

1. [atasOS nedir](#1-atasos-nedir)
2. [Gereksinimler](#2-gereksinimler)
3. [İndirme ve doğrulama](#3-i̇ndirme-ve-doğrulama)
4. [USB belleğe yazma](#4-usb-belleğe-yazma)
5. [Canlı oturumu açma](#5-canlı-oturumu-açma)
6. [Kurulum](#6-kurulum)
7. [İlk açılış](#7-i̇lk-açılış)
8. [Günlük kullanım ve ayarlar](#8-günlük-kullanım-ve-ayarlar)
9. [Paketler ve güncelleme](#9-paketler-ve-güncelleme)
10. [Bilinen sorunlar](#10-bilinen-sorunlar)
11. [Kaynak kod](#11-kaynak-kod)
12. [atasOS nasıl üretiliyor](#12-atasos-nasıl-üretiliyor)
13. [Sürüm geçmişi](#13-sürüm-geçmişi)

## 1. atasOS nedir

atasOS, sıfırdan derlenmiş bir Linux dağıtımıdır:

- **Temel:** Linux From Scratch (LFS) 12.3 ve BLFS; paket yöneticisi olan bir
  dağıtımın üstüne kurulmamıştır, her paket kaynağından derlenmiştir.
- **Masaüstü:** KDE Plasma 6 (X11 oturumu), Breeze Koyu tema ve atasOS mavisi.
- **Çekirdek:** Linux 6.16.1-atas6 (kendi ayarlarıyla derlenmiş).
- **Dil:** Türkçe arayüz, Türkçe Q klavye, saat dilimi İstanbul.
- **Kurulum:** Calamares kurulum programıyla canlı ISO'dan.
- **Uygulamalar:** Flatpak ve Flathub (Steam dahil).

Hem BIOS hem UEFI bilgisayarlarda açılır.

## 2. Gereksinimler

| | En az | Önerilen |
|---|---|---|
| İşlemci | 64 bit x86 (Intel / AMD) | |
| Bellek (RAM) | 1 GB (kurulum programının sınırı) | 4 GB ve üstü |
| Disk | 12 GB boş alan (kurulu sistem ~8 GB) | 30 GB ve üstü |
| USB bellek | 4 GB | |

**Desteklenen donanım (çekirdek atas6):**

- Ekran kartı: Intel (i915), AMD (amdgpu, radeon), NVIDIA (nouveau; NVIDIA'nın
  kendi sürücüsü yok). Sanal makineler: QEMU/KVM (virtio, bochs, qxl),
  VirtualBox, VMware.
- Kablosuz ağ: Intel (iwlwifi), MediaTek (mt7921/mt7925), Realtek (rtw88/rtw89,
  rtl8xxxu). Bluetooth.
- Disk: NVMe, SATA, USB (UAS dahil).
- Ses: HDMI ses ve standart HD Audio kartları. Kamera (UVC).

Gerçek donanımda yalnızca geliştiricinin dizüstü bilgisayarında denenmiştir;
kurulum testleri sanal makinede yapılmıştır.

## 3. İndirme ve doğrulama

ISO'yu ve `.sha256` dosyasını aynı klasöre indirin:

```bash
wget https://archive.org/download/atasos-live/atasos-live-v36.iso
wget https://archive.org/download/atasos-live/atasos-live-v36.iso.sha256
sha256sum -c atasos-live-v36.iso.sha256
```

`atasos-live-v36.iso: OK` (Türkçe sistemlerde `TAMAM`) görmelisiniz. Başka bir
şey çıkarsa dosya bozuk inmiştir; yeniden indirin.

Windows'ta PowerShell ile:

```powershell
Get-FileHash .\atasos-live-v36.iso -Algorithm SHA256
```

Çıkan değer yukarıdaki sha256 ile aynı olmalı.

## 4. USB belleğe yazma

> **Dikkat:** USB bellekteki her şey silinir. Doğru aygıtı seçtiğinizden emin
> olun; yanlış aygıta yazmak o diskteki verileri yok eder.

**Linux:** önce USB belleğin adını bulun (`lsblk`; `TRAN` sütununda `usb` yazan
disk). Sonra:

```bash
sudo dd if=atasos-live-v36.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

`/dev/sdX` yerine USB belleğin adını yazın (bölüm değil disk: `sdb1` değil
`sdb`).

atasOS kaynak deposunda bunu daha güvenli yapan bir betik var:
[`scripts/2026-11-rebuild/atasos-61-usb-yaz.sh`](../scripts/2026-11-rebuild/atasos-61-usb-yaz.sh).
Yalnızca USB diskleri kabul eder, aygıt adını elle yazdırır, yazmadan önce
ISO'nun sha256'sını, yazdıktan sonra USB'den geri okuyarak yazılanı doğrular.

**Windows:** [Rufus](https://rufus.ie) ya da balenaEtcher kullanın. Rufus
sorarsa **DD kipi**ni seçin (ISO kipi değil).

## 5. Canlı oturumu açma

1. **Secure Boot'u kapatın.** atasOS ISO'su imzasızdır; Secure Boot açıkken
   bilgisayar onu başlatmaz. BIOS/UEFI ayarlarına (açılışta genellikle F2, F10,
   Del ya da Esc) girip Secure Boot'u **Disabled** yapın.
2. Bilgisayarı USB bellekten açın (açılış menüsü genellikle F12, F11, F8 ya da
   Esc ile gelir).
3. atasOS GRUB menüsünde ilk girdiyi seçin.
4. Masaüstü kendiliğinden açılır: canlı oturum **eren** kullanıcısıyla, parolasız
   başlar.

Canlı oturumda yaptığınız değişiklikler bellekte tutulur; bilgisayarı
kapattığınızda kaybolur. Kurulum yapmadan atasOS'u bu şekilde deneyebilirsiniz.

Yüksek çözünürlüklü ekranlarda (170 dpi ve üstü, ör. 3000×2000 dizüstü ekranlar)
arayüz kendiliğinden %200 ölçeklenir.

## 6. Kurulum

> **Önce yedek alın.** Kurulum diske yazar. Diskte önemli veri varsa başka bir
> yere kopyalayın.

Masaüstündeki **atasOS Kur** simgesine çift tıklayın. Kurulum programı sırayla
şunları sorar:

### 6.1 Hoş geldiniz

Dil seçimi (Türkçe hazır gelir) ve gereksinim denetimi: en az 12 GB boş disk ve
1 GB bellek yoksa kurulum ilerlemez.

### 6.2 Konum

Saat dilimi (Avrupa/İstanbul hazır gelir) ve dil/biçim ayarları.

### 6.3 Klavye

Klavye düzeni. Türkçe Q hazır gelir; F klavye kullanıyorsanız buradan seçin.
Alttaki kutuya yazarak deneyebilirsiniz.

### 6.4 Bölümler (disk)

atasOS'ta bu adımda **hiçbir seçenek önceden seçili gelmez**. Ne yapılacağını
siz seçmeden **İleri** düğmesi açılmaz. Bu bilinçli bir güvenlik önlemidir:
yanlışlıkla bir diskin tamamen silinmesini önler.

> **⚠️ Kurulumdan önce önemli dosyalarınızı başka bir diske ya da buluta
> yedekleyin.** "Diski sil", "Bölüm değiştir" ve "Yanına kur" diske yazar; yanlış
> disk ya da bölüm seçimi, elektrik kesilmesi veya bozuk bir dosya sistemi veri
> kaybına yol açabilir. Kurulum programı geri alma imkânı vermez.

Önce üstten **doğru diski** seçin: adına ve boyutuna bakın (örneğin
`/dev/nvme0n1`, 953,9 GiB). Bilgisayarda birden fazla disk ya da takılı bir USB
bellek varsa özellikle dikkat edin. Diskte başka işletim sistemleri (Windows,
başka bir Linux) varsa adlarıyla gösterilir. Sonra seçeneklerden birini seçin:

- **Diski sil:** seçili diskteki **her şey silinir** (diğer işletim sistemleri
  ve kişisel dosyalar dahil) ve atasOS diskin tamamına kurulur. Yalnızca boş bir
  diskte ya da verilerini gözden çıkardığınız bir diskte seçin.
  - v35'te son onay penceresi genel bir uyarıdır ("Bu değişiklikleri geri
    alamayacaksınız"); diskte başka sistem ya da veri olduğunu ayrıca
    hatırlatmaz.
  - v36'dan itibaren son onayda silinecek diskin adı kırmızı bir **DİKKAT**
    uyarısıyla yazılır. Disk adı beklediğiniz değilse **Geri Git**'e basın.
- **Yanına kur:** mevcut bir bölüm küçültülür, açılan yere atasOS kurulur.
  Açılışta GRUB menüsünden hangi sistemi açacağınızı seçersiniz.
  **Dikkat, devam etmeden önce alttaki çubuğu mutlaka kontrol edin:**
  - Varsayılan bölme noktası bölümün yarısıdır, ama atasOS'a gereken yer
    (yaklaşık 15 GB) ayrılmak zorunda olduğundan küçük bir bölümde küçültülen
    bölüme çok az yer kalabilir. Çubuğu sürükleyerek o bölüme yeterince boş yer
    bırakın.
  - v35'te, yarısından fazlası dolu bir bölümde varsayılan bölme noktası
    bölümdeki verinin altına düşebilir; küçültme yapılamaz ve kurulum yarıda
    kalır. Çubuğu, mevcut verinin rahatça sığacağı yere çekin.
  - v35'te bu seçenekle açılan yeni bölüm 1 MiB sınırına hizalanmaz (veri kaybı
    olmaz, SSD'de biraz yavaşlatabilir). Hizalama önemliyse yeri önceden açıp
    **Bölüm değiştir** ya da **Elle bölümleme** kullanın.
  - v36'dan itibaren bu iki sorun düzeltildi; çubuğu yine de kontrol edin.
  - Windows bölümünü küçültecekseniz önce Windows'ta **Hızlı başlatma**yı
    kapatın ve BitLocker açıksa askıya alın; aksi halde bölüm küçültülemez ya da
    Windows açılmayabilir.
- **Bölüm değiştir:** var olan bir bölümün yerine atasOS kurulur; o bölümdeki
  veriler silinir.
- **Elle bölümleme:** bölümleri kendiniz oluşturursunuz. Gerekenler:
  - kök bölüm `/`, **ext4**, en az 12 GB;
  - UEFI bilgisayarlarda bir EFI bölümü, `/boot/efi` olarak bağlı (FAT32, var
    olanı kullanabilirsiniz; biçimlendirmeyin, içinde Windows'un açılış dosyaları
    olabilir).

**Disk şifreleme** desteklenmez: atasOS'ta açılışta şifreyi soracak bir
initramfs yoktur, şifreli bir kök bölüm açılamaz. Bu yüzden v36'dan itibaren
"Sistemi şifrele" seçeneği gösterilmez (v35'te görünür; **seçmeyin**).

Takas (swap): **Takas yok** ya da **Takas dosyası** seçilebilir. 8 GB'tan az
belleğiniz varsa takas dosyası önerilir.

Kök bölüm için yalnızca ext4 desteklenir.

EFI bölümündeki başka sistemlerin dosyalarına dokunulmaz: atasOS yalnızca
`EFI/atasOS` klasörünü ekler. Yedek önyükleyici `EFI/BOOT/BOOTX64.EFI` yalnızca
yoksa yazılır (v34 ve öncesi, örneğin Ubuntu/Kubuntu'nun bu dosyasının üstüne
yazıyordu). Kurulum, bilgisayarın açılış listesine "atasOS" girdisini ekler ve
genellikle ilk sıraya koyar; diğer sistemler atasOS'un GRUB menüsünde listelenir.

### 6.5 Kullanıcılar

- Adınız, giriş adınız ve parolanız.
- Bilgisayar adı adınızdan kendiliğinden üretilir (ör. `ayse-atasos`);
  değiştirebilirsiniz.
- Bu kullanıcı yönetici yetkisi alır (`wheel` grubu): `sudo` ile kendi
  parolasıyla komut çalıştırabilir.
- Varsayılan olarak root parolası kullanıcı parolasıyla aynıdır.
- Parola boş bırakılamaz: parola kutuları boşken **Sonraki** düğmesi kapalıdır
  ("Parola pek kısa"). Kısa ve basit parolalar kabul edilir.
- **Parolayı sormadan kendiliğinden oturum aç** işaretlenirse bilgisayar
  açılışta giriş ekranında beklemeden doğrudan masaüstüne açılır. Parola yine
  vardır: `sudo` ve ekran kilidi onu ister.

### 6.6 Özet ve son onay

Yapılacak her şey listelenir; disk değişiklikleri kırmızıyla gösterilir.
**Kur** düğmesine bastığınızda bir kez daha onay istenir. Diske ancak bu onaydan
sonra yazılır. Emin değilseniz **Geri** ile dönün; bu noktaya kadar diske
hiçbir şey yazılmamıştır.

### 6.7 Kurulum ve bitiş

Kurulum disk hızına göre 5–20 dakika sürer. Bittiğinde **Şimdi yeniden başlat**
seçeneğini işaretleyip **Bitti**ye basın, istendiğinde USB belleği çıkarın.

Kurulum programı, kurulan sistemden kendini kaldırır; kurulu atasOS'ta "atasOS
Kur" simgesi yoktur.

## 7. İlk açılış

1. **GRUB menüsü:** diskte yalnızca atasOS varsa menü gösterilmez ve atasOS
   hemen açılır (menüyü görmek için açılışta **Esc**'ye basın). Diskte başka
   sistemler varsa atasOS temalı menü 3 saniye gösterilir; ilk girdi atasOS'tur.
2. **Giriş ekranı:** kullanıcınızı seçip parolanızı yazın. (Kurulumda
   "Parolayı sormadan kendiliğinden oturum aç" seçildiyse bu adım atlanır.)
   - Klavyeniz yoksa ya da çalışmıyorsa **Ekran klavyesi** düğmesi Türkçe ekran
     klavyesini açar.
   - Oturum olarak **Plasma (X11)** seçili gelir; başka seçenek yoktur (bkz.
     [Bilinen sorunlar](#10-bilinen-sorunlar)).
   - Yeniden başlatma ve kapatma düğmeleri de giriş ekranındadır.
3. **Masaüstü:** Breeze Koyu tema, atasOS duvar kağıdı. Alttaki panelde atasOS
   menüsü, Dolphin (dosyalar), Firefox, Konsole (uçbirim), Kate (metin
   düzenleyici) ve Sistem Ayarları bulunur.

## 8. Günlük kullanım ve ayarlar

### Ekran ölçeği

Yüksek çözünürlüklü ekranlarda ölçek kendiliğinden %200 olur. Değiştirmek için:

- **Sistem Ayarları → Ekran** bölümünden ölçek seçin; seçtiğiniz değer
  kendiliğinden ayarın yerine geçer.
- Ya da elle: `~/.config/atasos-olcek` (yalnız sizin için) veya
  `/etc/atasos/olcek` (bütün kullanıcılar için) dosyasına şunlardan birini yazın:

  ```
  OLCEK=1
  OLCEK=2
  OLCEK=otomatik
  ```

  Değişiklik bir sonraki girişte geçerli olur.

### Dokunmatik yüzey (touchpad)

Dokunarak tıklama, dokunup sürükleme ve yazarken dokunmatik yüzeyi kapatma
açıktır. **Sistem Ayarları → Giriş Aygıtları → Dokunmatik Yüzey**'den
değiştirebilirsiniz.

### Yönetici komutları

Kurulumda oluşturduğunuz kullanıcı `sudo` kullanabilir:

```bash
sudo komut
```

### Kablosuz ağ

Panelin sağındaki ağ simgesinden ağı seçip parolasını girin.

### Diğer işletim sistemleri

atasOS'u Windows ya da başka bir Linux'un yanına kurduysanız, GRUB menüsü her
açılışta 3 saniye boyunca hangisini başlatacağınızı sorar. Sonradan başka bir
sistem kurarsanız atasOS'ta `sudo grub-mkconfig -o /boot/grub/grub.cfg`
çalıştırın; menü kendiliğinden yeniden görünür.

## 9. Paketler ve güncelleme

atasOS'ta henüz düzenli bir güncelleme kanalı **yoktur**. Kurulu sistem, ISO'da
gelen paketlerle kalır. Yeni sürüm çıktığında yeniden kurmanız gerekir.

İki paket aracı geliştirme aşamasındadır:

- **atspkg** (sistemde kurulu): kendi paket biçimini kurar, kaldırır, doğrular.
  Paket deposu: <https://archive.org/details/atasos-depo>. Şimdilik depoda
  yalnızca atspkg'nin kendisi vardır. v36'daki atspkg 0.3.0, depo dizinini
  yalnızca atasOS depo anahtarıyla imzalıysa kabul eder (anahtar
  `/usr/share/atspkg/depo-anahtari.gpg`, parmak izi
  `0D5A 09FA 2D63 998C 3936  430C AD37 7A27 2348 72E2`) ve indirmelerde TLS
  sertifikasını her zaman doğrular.

  ```
  atspkg guncelle          # depo dizinini indir
  atspkg ara <desen>       # kurulu paketlerde ve depoda ara
  atspkg kur <dosya|ad>    # kur / yükselt
  atspkg sil <ad>          # kaldır
  atspkg listele           # kurulu paketler
  atspkg dogrula <ad>      # sha256 bütünlük denetimi
  ```

- **apm** (bu depodaki [`apm/`](../apm)): bağımlılık çözen, kurulumu
  ya-hep-ya-hiç yapan ve başarısızlıkta geri alan prototip paket yöneticisi.
  Henüz ISO'da yoktur.

### Firefox güncellemesi

Firefox, Mozilla'nın resmi Linux sürümüdür (`/opt/firefox`). v36'dan itibaren
uygulama menüsündeki **Firefox'u Güncelle** en yeni sürümü indirir, Mozilla'nın
imzasını ve sha512 toplamını doğrular, sonra kurar (parolanız sorulur; Firefox
açıksa önce kapatın). Uçbirimden: `atasos-firefox-guncelle`. Firefox'un kendi
içindeki güncelleme kapalıdır.

### Flatpak ve Steam

Flatpak (1.16.1) ve Flathub deposu v33'ten itibaren kurulu gelir. Flathub'daki
uygulamalar kendi kütüphaneleriyle kurulur:

```bash
flatpak install flathub <uygulama-kimliği>
flatpak search <ad>
flatpak update
```

**Steam:** atasOS yalnızca 64 bit derlendiği için Steam'in istediği 32 bit
kütüphaneler sistemde yoktur; Steam bu yüzden Flatpak ile kurulur (Flatpak
sürümü 32 bit kütüphaneleri ve ekran kartı sürücülerini kendisi getirir):

```bash
flatpak install flathub com.valvesoftware.Steam
flatpak run com.valvesoftware.Steam
```

İlk kurulum yaklaşık 1–2 GB indirir. Canlı oturumda değil, kurulu sistemde
kurun: canlı oturumun yazılabilir alanı bellekte ve küçüktür. Kurulumdan sonra Steam uygulama menüsünde
de görünür (görünmezse oturumu kapatıp açın). Kurulan kullanıcı (`wheel`
grubu) Flatpak uygulamalarını parola sormadan kurabilir.

Kolu olanlar için: atasOS çekirdeğinde `uinput` / `uhid` henüz kapalı olduğu
için Steam Input'un kol eşleme özellikleri sınırlıdır; klavye ve fareyle
oynamayı etkilemez.

Yarıda kalan bir kurulumdan sonra (ör. disk doldu) imza ya da "no signatures
found" hatası alırsanız: `sudo flatpak repair`, ardından kurulumu yeniden
başlatın.

## 10. Bilinen sorunlar

| Sorun | Durum / geçici çözüm |
|---|---|
| **Secure Boot** desteklenmiyor | ISO imzasız. BIOS/UEFI ayarlarında Secure Boot'u kapatın. |
| **Plasma Wayland** oturumu açılmıyor | Giriş ekranında gizlendi; yalnızca X11 oturumu var. |
| **AMD dizüstülerde dahili mikrofon** (SoundWire / ACP) çalışmıyor | Çekirdekte ASoC desteği kapalı. Kulaklık ve USB mikrofon çalışır. |
| **NVIDIA'nın kendi sürücüsü** yok | Açık kaynak nouveau kullanılır; yeni NVIDIA kartlarda 3B hızlandırma sınırlıdır. |
| **Steam** doğrudan kurulamaz (32 bit kütüphane yok) | Flatpak ile kurulur; bkz. [Flatpak ve Steam](#flatpak-ve-steam). |
| **Güncelleme kanalı** henüz paket sunmuyor | İmzalı kanalın altyapısı v36'da hazır (atspkg 0.3.0); paketler eklenecek. Firefox menüden güncellenir. Bkz. [Paketler ve güncelleme](#9-paketler-ve-güncelleme). |
| **Disk şifreleme** (LUKS) yok | Initramfs olmadığı için şifreli kök açılamaz; v36'da seçenek gizlendi. |
| Gerçek donanımda **sınırlı test** | Kurulum testleri sanal makinede yapıldı. Sorun bildirirseniz düzeltilir. |

Sorun bildirmek için: <https://github.com/johntitor08/atasos-tools/issues>.
Mümkünse bilgisayar modelini ve şu komutların çıktısını ekleyin:

```bash
uname -r
lspci -k
journalctl -b -p err --no-pager | tail -50
```

## 11. Kaynak kod

atasOS'taki yazılımların çoğu GPL ve benzeri özgür lisanslarla dağıtılır.
Kaynak kodları:

- **atasOS kaynak paketi:** <https://github.com/johntitor08/atasos-tools/releases/tag/v32-kaynak>
  ve v33'te eklenen Flatpak zinciri:
  <https://github.com/johntitor08/atasos-tools/releases/tag/v33-kaynak>
  - ISO'daki paketlerin kaynak arşivleri ve LFS yamaları
  - çekirdeğin kaynağı (`linux-6.16.1.tar.xz`) ve atasOS'un çekirdek ayarı
    (`config-6.16.1-atas6`)
  - kurulu sistemdeki bütün kütüphane ve KDE bileşenlerinin tam sürüm listesi
- **Derleme betikleri, tasarım dosyaları, paket araçları:** bu depo
  (<https://github.com/johntitor08/atasos-tools>).
- **Değiştirilmeden kullanılan üst kaynak paketleri** (KDE Plasma ve
  Frameworks, Qt 6, Mesa, Firefox, Calamares ve diğerleri) kendi projelerinin
  sitelerinden aynı sürüm numarasıyla indirilebilir; sürümler kaynak
  paketindeki `surumler/` klasöründe listelidir.

## 12. atasOS nasıl üretiliyor

Bu bölüm atasOS'u kendisi derlemek ya da değiştirmek isteyenler içindir.

**Kaynak sistem.** atasOS, ayrı bir disk bölümüne (geliştiricinin bilgisayarında
`/dev/nvme0n1p5`) LFS 12.3 kitabı ve BLFS izlenerek kurulmuş, üstüne KDE
Plasma 6 derlenmiştir. Bütün değişiklikler, Kubuntu'dan root olarak çalışan
numaralı betiklerle yapılır
([`scripts/2026-11-rebuild/`](../scripts/2026-11-rebuild/README.md)):

- betikler bölümü `/mnt/atasos`'a bağlar, aynı anda iki betik çalışmasın diye
  ortak bir kilit alır ve çıkarken bölümü ayırır;
- değiştirdikleri dosyaların önce yedeğini alırlar.

**Çekirdek.** `atasos-58-cekirdek-atas6.sh` Linux 6.16.1'i atasOS ayarlarıyla
derler. Initramfs kullanılmaz: açılış için gereken sürücüler (NVMe, SATA,
ext4…) çekirdeğe gömülüdür.

**Canlı ISO** (`atasos-81-v36-iso.sh`):

1. Kaynak bölüm salt okunur kullanılır; ISO'ya özel değişiklikler bir overlay
   katmanında yapılır (canlı kullanıcı, otomatik giriş, kurulum programı
   ayarları), kaynak sisteme dokunulmaz.
2. Katmanlı kök dizin **squashfs** (zstd) olarak sıkıştırılır.
3. Küçük bir **busybox initramfs**, açılışta ISOIMAGE etiketli ortamı bulur,
   squashfs'i salt okunur, üstüne bellekte yazılabilir bir katman bağlar.
4. `grub-mkrescue` BIOS ve UEFI'den açılabilen hibrit ISO üretir; GRUB teması
   ISO'ya da eklenir.
5. Betik, disk güvenliği ayarlarını (`initialPartitioningChoice: none`,
   `prompt-install: true`), sudo yetkisini, boş parola engelini, otomatik giriş
   adımını, EFI yedek önyükleyici ayarını, `root=PARTUUID` ayarını ve oturum
   ayarlarını denetler; biri eksikse ISO üretmez.
6. v36'dan itibaren Calamares 3.3.14 resmi kaynağından, atasOS yamasıyla
   ([`atasos-calamares-3.3.14.patch`](../scripts/2026-11-rebuild/atasos-calamares-3.3.14.patch))
   aynı overlay içinde derlenir; kaynak sisteme yine dokunulmaz.

**Yayın.** `atasos-63-archive-yukle.sh` ISO'yu archive.org'a yükler, indirme
adresini ve sha256'yı doğrular, ancak bundan sonra eski sürümleri (tek tek
sorarak) siler.

**Tasarım dosyaları** (logo, giriş ekranı teması, duvar kağıdı, GRUB teması,
kurulum slaytları): [`branding/`](../branding/README.md).

**Kurulum güvenliği neden bu kadar sıkı?** v21–v28 ISO'ları, başka bir
dağıtımın kurulum programı diski sildiği için kayboldu. atasOS'un kurulum
programı bu yüzden hiçbir disk seçeneğini önceden seçmez ve diske yazmadan önce
son bir onay ister.

## 13. Sürüm geçmişi

| Sürüm | Tarih | Değişiklikler |
|---|---|---|
| **v36** | 2026-11-17 | Yamalı Calamares: "Yanına kur" ile açılan bölüm 1 MiB sınırından başlar, çubuğun varsayılanı bölümdeki verinin altına inmez, "Diski sil" son onayında silinecek disk kırmızı uyarıyla yazılır, disk şifreleme seçeneği gizlendi (initramfs olmadığı için şifreli sistem açılmıyordu). Menüde **Firefox'u Güncelle**. atspkg 0.3.0: depo dizini imzalı olmak zorunda, indirmelerde TLS her zaman doğrulanır. Tek sistemli diskte GRUB menüsü gizli (Esc ile açılır). |
| v35 | 2026-11-14 | Kurulum, EFI bölümündeki başka bir sistemin yedek önyükleyicisinin (`EFI/BOOT/BOOTX64.EFI`, ör. Kubuntu'nun) üstüne yazmaz, yalnızca yoksa yazar; kurulan GRUB sistemi `root=PARTUUID=` ile açar (önceden aygıt adıyla, ör. `/dev/nvme0n1p4`; disk sırası değişince açılmazdı). Sanal NVMe diskte dört bölümleme seçeneğinin hepsiyle denendi. |
| v34 | 2026-11-13 | Kurulumda boş parola kabul edilmez (v33 boş parolayla kurulan sisteme girilemiyordu); "Parolayı sormadan kendiliğinden oturum aç" seçeneği artık çalışır. |
| v33 | 2026-11-08 | Flatpak 1.16.1 ve Flathub deposu (Steam Flatpak ile kurulur). |
| v32 | 2026-11-08 | Wayland oturumu giriş ekranında gizlendi (açılmıyordu ve yeni kullanıcılar için seçili geliyordu). |
| v31 | 2026-11-07 | Çekirdek atas6 (AMD, NVIDIA, MediaTek/Realtek Wi-Fi); Breeze Koyu + atasOS mavisi, duvar kağıdı, GRUB teması; dokunarak tıklama; ISO dosyasından açılabilme. |
| v30 | 2026-11-07 | Kurulumdan sonra kurulum programı kaldırılır; kurulan kullanıcıya sudo; logo, Türkçe ekran klavyeli giriş ekranı, otomatik HiDPI ölçeği. |
| v29 | 2026-11-07 | Disk silinmesinin ardından yeniden kurulan sistemden ilk ISO. |
| v13–v20 | 2026-07 – 2026-09 | İlk canlı ISO'lar ve Calamares kurulumu. |

Yalnızca en son sürüm (v36) indirilebilir.
