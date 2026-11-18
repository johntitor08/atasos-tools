// atasOS acilis ekrani (giristen masaustune gecerken). ksplashqml 'stage' degerini 1..6 arasinda arttirir.
import QtQuick

Rectangle {
    id: root
    property int stage
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0e1a2b" }
        GradientStop { position: 1.0; color: "#05090f" }
    }

    onStageChanged: {
        if (stage === 2) icerik.opacity = 1
        if (stage === 5) icerik.opacity = 0.0
    }

    Item {
        id: icerik
        anchors.centerIn: parent
        width: Math.min(root.width, root.height) * 0.5
        height: logo.height + yazi.height + cubuk.height + root.height * 0.06
        opacity: 0
        Behavior on opacity { OpacityAnimator { duration: 600; easing.type: Easing.InOutQuad } }

        Image {
            id: logo
            anchors.horizontalCenter: parent.horizontalCenter
            source: "file:///usr/share/icons/hicolor/scalable/apps/atasos.svg"
            sourceSize.width: Math.round(Math.min(root.width, root.height) * 0.16)
            sourceSize.height: sourceSize.width
            smooth: true
        }
        Text {
            id: yazi
            anchors.top: logo.bottom
            anchors.topMargin: root.height * 0.03
            anchors.horizontalCenter: parent.horizontalCenter
            text: "atasOS"
            color: "#e8eef5"
            font.pixelSize: Math.round(root.height * 0.045)
            font.weight: Font.DemiBold
            font.letterSpacing: 2
        }
        Rectangle {
            id: cubuk
            anchors.top: yazi.bottom
            anchors.topMargin: root.height * 0.03
            anchors.horizontalCenter: parent.horizontalCenter
            width: logo.sourceSize.width * 1.6
            height: Math.max(3, Math.round(root.height * 0.004))
            radius: height / 2
            color: "#1f2b3d"
            Rectangle {
                height: parent.height
                radius: parent.radius
                color: "#3daee9"
                width: parent.width * Math.min(1, root.stage / 6)
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }
}
