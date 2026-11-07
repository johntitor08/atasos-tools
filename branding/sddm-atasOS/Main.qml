// atasOS SDDM giris ekrani (v2): ekran yogunluguna gore otomatik olcek, Turkce ekran klavyesi,
// hata mesaji, saat, yeniden baslat / kapat. Yalniz QtQuick + QtQuick.VirtualKeyboard kullanir.
import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.VirtualKeyboard 2.15
import QtQuick.VirtualKeyboard.Settings 2.15

Rectangle {
    id: root
    width: 1280
    height: 800

    // --- olcek: fiziksel DPI (Screen.pixelDensity = piksel/mm). Qt zaten olcekliyorsa (QT_SCREEN_SCALE_FACTORS)
    // mantiksal yogunluk ~96 dpi olur ve s=1 kalir -> cift olcek olmaz. EDID mm bilgisi yoksa: 1800+ satir = 2.
    readonly property real dpi: Screen.pixelDensity * 25.4
    readonly property real s: (dpi >= 170 || Screen.height >= 1800) ? 2 : 1
    property string secilenKullanici: userModel.lastUser
    property int secilenOturum: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool klavyeAcik: false
    property bool x11Secildi: false

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0f2235" }
        GradientStop { position: 1.0; color: "#1b4f8a" }
    }

    // atasOS duvar kagidi + okunabilirlik icin koyu ortu (resim yoksa yalniz gradyan kalir)
    Image {
        anchors.fill: parent
        source: "background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        smooth: true
    }
    Rectangle { anchors.fill: parent; color: "#07111d"; opacity: 0.35 }

    Component.onCompleted: {
        VirtualKeyboardSettings.locale = "tr_TR"
        VirtualKeyboardSettings.activeLocales = ["tr_TR", "en_US"]
        sifre.forceActiveFocus()
    }

    function girisYap() {
        if (secilenKullanici === "") { hata.text = "Kullanıcı seçin"; return }
        hata.text = ""
        durum.text = "Giriş yapılıyor…"
        sddm.login(secilenKullanici, sifre.text, secilenOturum)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            durum.text = ""
            hata.text = "Şifre yanlış. Tekrar deneyin."
            sifre.text = ""
            sifre.forceActiveFocus()
        }
        function onLoginSucceeded() { durum.text = "" }
    }

    // --- sag ust: saat ---
    Column {
        anchors { top: parent.top; right: parent.right; margins: 24 * s }
        Text {
            id: saat
            anchors.right: parent.right
            color: "white"; font.pixelSize: 34 * s; font.weight: Font.Light
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: tarih
            anchors.right: parent.right
            color: "#c8d8ea"; font.pixelSize: 14 * s
            text: Qt.locale("tr_TR").toString(new Date(), "d MMMM yyyy, dddd")
        }
        Timer {
            interval: 10000; running: true; repeat: true
            onTriggered: { saat.text = Qt.formatTime(new Date(), "HH:mm"); tarih.text = Qt.locale("tr_TR").toString(new Date(), "d MMMM yyyy, dddd") }
        }
    }

    // --- orta: logo, kullanicilar, sifre ---
    Column {
        id: orta
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(16 * s, (root.height - (klavyeAcik && klavye.active ? klavye.height : 0) - height) / 2)
        spacing: 14 * s
        Behavior on y { NumberAnimation { duration: 150 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "atasOS"; color: "white"
            font.pixelSize: 30 * s; font.bold: true
        }

        ListView {
            id: kullanicilar
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(count, 5) * (96 * s) + Math.max(0, Math.min(count, 5) - 1) * spacing
            height: 104 * s
            orientation: ListView.Horizontal
            spacing: 12 * s
            interactive: count > 5
            model: userModel
            currentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
            onCurrentIndexChanged: if (currentItem) secilenKullanici = currentItem.kullaniciAdi
            Component.onCompleted: if (currentItem && secilenKullanici === "") secilenKullanici = currentItem.kullaniciAdi
            delegate: Item {
                property string kullaniciAdi: model.name
                width: 96 * s; height: 104 * s
                Rectangle {
                    id: avatar
                    width: 64 * s; height: width; radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: (kullanicilar.currentIndex === index) ? "#3daee9" : "#22ffffff"
                    border.color: (kullanicilar.currentIndex === index) ? "white" : "transparent"
                    border.width: 2 * s
                    Text {
                        anchors.centerIn: parent
                        text: (model.name || "?").charAt(0).toUpperCase()
                        color: "white"; font.pixelSize: 28 * s; font.bold: true
                    }
                }
                Text {
                    anchors { top: avatar.bottom; topMargin: 8 * s; horizontalCenter: parent.horizontalCenter }
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: model.realName !== "" ? model.realName : model.name
                    color: "white"; font.pixelSize: 14 * s
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { kullanicilar.currentIndex = index; sifre.forceActiveFocus() }
                }
            }
        }

        // sifre kutusu
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300 * s; height: 40 * s; radius: 6 * s
            color: "#ffffff"
            border.color: sifre.activeFocus ? "#3daee9" : "#55ffffff"; border.width: 2 * s
            TextInput {
                id: sifre
                anchors { fill: parent; leftMargin: 12 * s; rightMargin: 12 * s }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                font.pixelSize: 16 * s
                color: "#1d1d1d"
                clip: true
                focus: true
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                Keys.onReturnPressed: girisYap()
                Keys.onEnterPressed: girisYap()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Şifre"; color: "#888888"; font.pixelSize: 16 * s
                    visible: sifre.text.length === 0
                }
            }
        }

        // giris dugmesi
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300 * s; height: 40 * s; radius: 6 * s
            color: girisFare.pressed ? "#1d7fbf" : (girisFare.containsMouse ? "#4fbcf0" : "#3daee9")
            Text { anchors.centerIn: parent; text: "Giriş"; color: "white"; font.pixelSize: 16 * s; font.bold: true }
            MouseArea { id: girisFare; anchors.fill: parent; hoverEnabled: true; onClicked: girisYap() }
        }

        Text {
            id: hata
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ffb4b4"; font.pixelSize: 14 * s; text: ""
        }
        Text {
            id: durum
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#c8d8ea"; font.pixelSize: 13 * s; text: ""
        }

        // oturum secimi (Plasma X11 / Wayland ...)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8 * s
            visible: sessionModel.rowCount() > 1
            Repeater {
                model: sessionModel
                delegate: Rectangle {
                    // yeni kurulan sistemde onceki oturum yok: atasOS'un varsayilani Plasma X11
                    Component.onCompleted: if (sessionModel.lastIndex < 0 && !x11Secildi && String(model.file).indexOf("x11") >= 0) { secilenOturum = index; x11Secildi = true }
                    height: 28 * s; radius: height / 2
                    width: oturumAdi.implicitWidth + 24 * s
                    color: index === secilenOturum ? "#33ffffff" : "transparent"
                    border.color: "#55ffffff"; border.width: 1
                    Text { id: oturumAdi; anchors.centerIn: parent; text: model.name; color: "white"; font.pixelSize: 12 * s }
                    MouseArea { anchors.fill: parent; onClicked: secilenOturum = index }
                }
            }
        }
    }

    // --- alt sol: ekran klavyesi ---
    Rectangle {
        id: klavyeDugmesi
        anchors { left: parent.left; bottom: parent.bottom; margins: 20 * s }
        anchors.bottomMargin: 20 * s + (klavyeAcik && klavye.active ? klavye.height : 0)
        width: klavyeYazi.implicitWidth + 28 * s; height: 36 * s; radius: 6 * s
        color: klavyeAcik ? "#3daee9" : (klavyeFare.containsMouse ? "#33ffffff" : "#1affffff")
        Text { id: klavyeYazi; anchors.centerIn: parent; text: klavyeAcik ? "Klavyeyi gizle" : "Ekran klavyesi"; color: "white"; font.pixelSize: 13 * s }
        MouseArea {
            id: klavyeFare; anchors.fill: parent; hoverEnabled: true
            onClicked: { klavyeAcik = !klavyeAcik; sifre.forceActiveFocus(); if (klavyeAcik) Qt.inputMethod.show() }
        }
    }

    // --- alt sag: yeniden baslat / kapat ---
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 20 * s }
        anchors.bottomMargin: 20 * s + (klavyeAcik && klavye.active ? klavye.height : 0)
        spacing: 10 * s
        Repeater {
            model: [
                { ad: "Yeniden başlat", izin: sddm.canReboot, is: "reboot" },
                { ad: "Kapat", izin: sddm.canPowerOff, is: "poweroff" }
            ]
            delegate: Rectangle {
                visible: modelData.izin
                width: gucYazi.implicitWidth + 28 * s; height: 36 * s; radius: 6 * s
                color: gucFare.containsMouse ? "#33ffffff" : "#1affffff"
                Text { id: gucYazi; anchors.centerIn: parent; text: modelData.ad; color: "white"; font.pixelSize: 13 * s }
                MouseArea {
                    id: gucFare; anchors.fill: parent; hoverEnabled: true
                    onClicked: modelData.is === "reboot" ? sddm.reboot() : sddm.powerOff()
                }
            }
        }
    }

    // --- Turkce ekran klavyesi (QT_IM_MODULE=qtvirtualkeyboard; SDDM varsayilani) ---
    InputPanel {
        id: klavye
        z: 99
        // genis ekranda klavye ortada ve sinirli genislikte (yuksekligi genislikle orantili)
        width: Math.min(root.width, 900 * s)
        x: (root.width - width) / 2
        y: (klavyeAcik && active) ? root.height - height : root.height
        visible: klavyeAcik && active
        Behavior on y { NumberAnimation { duration: 150 } }
    }
}
