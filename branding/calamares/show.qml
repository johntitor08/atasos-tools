// atasOS kurulum slaytlari (Calamares slideshowAPI 2)
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function onActivate() { degistir.running = true }
    function onLeave() { degistir.running = false }

    Timer { id: degistir; interval: 6000; running: false; repeat: true; onTriggered: presentation.goToNextSlide() }

    Slide {
        Column {
            anchors.centerIn: parent; spacing: 16
            Image { anchors.horizontalCenter: parent.horizontalCenter; source: "logo.png"; width: 96; height: 96; sourceSize.width: 256; sourceSize.height: 256 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "atasOS 1.0 kuruluyor"; font.pixelSize: 24; font.bold: true; color: "#1b2733" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 15; color: "#3b4a59"
                   text: "Linux From Scratch 12.3 tabanlı, KDE Plasma 6 masaüstlü Türkçe dağıtım.\nBu işlem birkaç dakika sürer; bilgisayarı kapatmayın." }
        }
    }
    Slide {
        Column {
            anchors.centerIn: parent; spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Kurulumdan sonra"; font.pixelSize: 22; font.bold: true; color: "#1b2733" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 15; color: "#3b4a59"
                   text: "Firefox, Dolphin, Konsole, Kate ve Sistem Ayarları hazır gelir.\nYüksek çözünürlüklü ekranlarda yazı ve simgeler otomatik büyütülür.\nÖlçeği Sistem Ayarları > Ekran bölümünden değiştirebilirsiniz." }
        }
    }
    Slide {
        Column {
            anchors.centerIn: parent; spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Giriş ekranı"; font.pixelSize: 22; font.bold: true; color: "#1b2733" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 15; color: "#3b4a59"
                   text: "Giriş ekranının sol altındaki \"Ekran klavyesi\" düğmesi\nTürkçe dokunmatik klavyeyi açar.\nDiskteki diğer işletim sistemleri açılış menüsünde (GRUB) listelenir." }
        }
    }
}
