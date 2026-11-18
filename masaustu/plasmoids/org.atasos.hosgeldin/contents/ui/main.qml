// atasOS'a Hos Geldin: 'atasos-hosgeldin' bunu plasmawindowed ile pencerede acar.
// Komutlar Plasma'nin "executable" veri motoruyla calistirilir (yalniz asagidaki sabit komutlar).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: kok
    preferredRepresentation: fullRepresentation

    property bool canli: false          // canli ISO: kurulum programi var
    property bool gizli: false          // "acilista gosterme" secili

    P5Support.DataSource {
        id: komut
        engine: "executable"
        connectedSources: []
        onNewData: function (kaynak, veri) {
            if (kaynak.indexOf("atasos-hosgeldin-durum") >= 0) {
                const s = (veri["stdout"] || "");
                kok.canli = s.indexOf("canli") >= 0;
                kok.gizli = s.indexOf("gizli") >= 0;
            }
            disconnectSource(kaynak);
        }
        function calistir(k) { connectSource(k); }
    }

    Component.onCompleted: komut.calistir("/usr/bin/atasos-hosgeldin --durum # atasos-hosgeldin-durum")

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 38
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        Layout.minimumWidth: Kirigami.Units.gridUnit * 28
        Layout.minimumHeight: Kirigami.Units.gridUnit * 26
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing * 2
            Kirigami.Icon {
                source: "atasos"
                Layout.preferredWidth: Kirigami.Units.iconSizes.enormous
                Layout.preferredHeight: Kirigami.Units.iconSizes.enormous
            }
            ColumnLayout {
                Layout.fillWidth: true
                Kirigami.Heading { text: i18n("atasOS'a hoş geldin"); level: 1 }
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: i18n("atasOS; kaynaktan derlenmiş, Türkçe ve KDE Plasma tabanlı bir işletim sistemi. Aşağıdaki kısayollarla başlayabilirsin.")
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.largeSpacing
            columns: 2
            rowSpacing: Kirigami.Units.largeSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            component Kart: PC3.Button {
                id: kart
                property string aciklama
                Layout.fillWidth: true
                Layout.preferredWidth: 1      // iki sutun esit genislikte
                Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        source: kart.icon.name
                        Layout.preferredWidth: Kirigami.Units.iconSizes.large
                        Layout.preferredHeight: Kirigami.Units.iconSizes.large
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        PC3.Label { text: kart.text; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        PC3.Label { text: kart.aciklama; opacity: 0.75; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                }
            }

            Kart {
                visible: kok.canli
                Layout.columnSpan: 2
                icon.name: "atasos"
                text: i18n("atasOS'u bilgisayarına kur")
                aciklama: i18n("Kurulum programını açar (son onaydan önce diske hiçbir şey yazılmaz)")
                onClicked: komut.calistir("/usr/bin/atasos-hosgeldin --kur")
            }
            Kart {
                icon.name: "system-software-update"
                text: i18n("Sistemi güncelle")
                aciklama: i18n("İmzalı atasOS deposundan güvenlik ve yazılım güncellemeleri")
                onClicked: komut.calistir("/usr/bin/atasos-hosgeldin --guncelle")
            }
            Kart {
                icon.name: "system-software-install"
                text: i18n("Uygulama bul (Flathub)")
                aciklama: i18n("Steam, oyunlar ve binlerce uygulama")
                onClicked: Qt.openUrlExternally("https://flathub.org/tr")
            }
            Kart {
                icon.name: "preferences-desktop-theme-global"
                text: i18n("atasOS görünümünü uygula")
                aciklama: i18n("atasOS renkleri, ortada yüzen panel ve başlatıcı (paneli sıfırlar)")
                onClicked: komut.calistir("/usr/bin/atasos-hosgeldin --gorunum")
            }
            Kart {
                icon.name: "systemsettings"
                text: i18n("Sistem Ayarları")
                aciklama: i18n("Ekran, ses, ağ, klavye ve daha fazlası")
                onClicked: komut.calistir("/usr/bin/atasos-hosgeldin --ayarlar")
            }
            Kart {
                icon.name: "utilities-terminal"
                text: i18n("Sistem bilgisi")
                aciklama: i18n("fastfetch ile donanım ve sürüm bilgisi")
                onClicked: komut.calistir("/usr/bin/atasos-hosgeldin --bilgi")
            }
            Kart {
                icon.name: "help-about"
                text: i18n("atasOS hakkında")
                aciklama: i18n("Kaynak kodu, sürümler ve indirme")
                onClicked: Qt.openUrlExternally("https://github.com/johntitor08/atasos-tools")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            PC3.CheckBox {
                text: i18n("Açılışta gösterme")
                checked: kok.gizli
                onToggled: {
                    kok.gizli = checked;
                    komut.calistir("/usr/bin/atasos-hosgeldin " + (checked ? "--gizle" : "--goster"));
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
