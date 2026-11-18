// atasOS Baslat: panel dugmesi (atasOS logosu) + acilir pencere: arama, tum uygulamalar (izgara), guc dugmeleri.
// Modeller Plasma'nin kendi Kicker eklentisinden (Kickoff/Kicker ile ayni veri: menu, KRunner, oturum islemleri).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: kok

    Plasmoid.icon: "atasos"
    toolTipMainText: i18n("atasOS")
    toolTipSubText: i18n("Uygulamalar ve arama")
    preferredRepresentation: compactRepresentation

    // Kickoff/Kicker'in kok modeli: yalniz "Tum uygulamalar" (duz, alfabetik). Satir 0 = tum uygulamalar listesi.
    Kicker.RootModel {
        id: kokModel
        autoPopulate: false
        appletInterface: kok
        flat: true
        sorted: true
        showSeparators: false
        showAllApps: true
        showAllAppsCategorized: false
        showTopLevelItems: false
        showRecentApps: false
        showRecentDocs: false
        Component.onCompleted: refresh()
    }
    readonly property var uygulamalar: kokModel.count > 0 ? kokModel.modelForRow(0) : null

    Kicker.RunnerModel {
        id: arayici
        appletInterface: kok
        mergeResults: true
        runners: ["krunner_services", "krunner_systemsettings", "krunner_sessions", "krunner_powerdevil",
                  "calculator", "unitconverter"]
    }

    Kicker.SystemModel {
        id: oturum
    }

    compactRepresentation: MouseArea {
        id: dugme
        hoverEnabled: true
        Layout.minimumWidth: Kirigami.Units.iconSizes.medium
        onClicked: kok.expanded = !kok.expanded
        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: Math.round(Kirigami.Units.smallSpacing / 2)
            source: "atasos"
            active: dugme.containsMouse || kok.expanded
        }
    }

    fullRepresentation: Item {
        id: pencere
        Layout.preferredWidth: Kirigami.Units.gridUnit * 34
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20

        readonly property bool aramada: ara.text.length > 0
        readonly property var gosterilen: aramada ? (arayici.count > 0 ? arayici.modelForRow(0) : null) : kok.uygulamalar

        function calistir(model, satir) {
            if (!model || satir < 0) return;
            model.trigger(satir, "", null);
            kok.expanded = false;
        }

        Connections {
            target: kok
            function onExpandedChanged() {
                if (kok.expanded) {
                    ara.text = "";
                    izgara.currentIndex = -1;
                    izgara.positionViewAtBeginning();
                    ara.forceActiveFocus();
                }
            }
        }

        // Bulaniklik (blur) olmayan ekranlarda arkadaki pencereler okunmasin: neredeyse opak zemin
        Rectangle {
            anchors.fill: parent
            anchors.margins: -Kirigami.Units.smallSpacing
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.94)
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            PlasmaExtras.SearchField {
                id: ara
                Layout.fillWidth: true
                placeholderText: i18n("Uygulama, ayar ya da komut ara…")
                onTextChanged: arayici.query = text
                Keys.onReturnPressed: pencere.calistir(pencere.gosterilen, izgara.currentIndex >= 0 ? izgara.currentIndex : 0)
                Keys.onDownPressed: { izgara.forceActiveFocus(); if (izgara.currentIndex < 0) izgara.currentIndex = 0; }
                Keys.onEscapePressed: kok.expanded = false
            }

            PC3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: izgara
                    readonly property int sutun: Math.max(3, Math.floor(width / (Kirigami.Units.gridUnit * 6.5)))
                    model: pencere.gosterilen
                    cellWidth: Math.floor(width / sutun)
                    cellHeight: Kirigami.Units.iconSizes.large + Kirigami.Units.gridUnit * 3
                    clip: true
                    keyNavigationEnabled: true
                    highlightFollowsCurrentItem: true
                    highlight: PlasmaExtras.Highlight {}
                    Keys.onReturnPressed: pencere.calistir(model, currentIndex)
                    Keys.onEscapePressed: kok.expanded = false

                    delegate: MouseArea {
                        id: oge
                        required property int index
                        required property var model
                        width: izgara.cellWidth
                        height: izgara.cellHeight
                        hoverEnabled: true
                        onEntered: izgara.currentIndex = index
                        onClicked: pencere.calistir(izgara.model, index)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                                source: oge.model.decoration
                                active: oge.containsMouse
                            }
                            PC3.Label {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: oge.model.display
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignTop
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: pencere.aramada && izgara.count === 0
                        iconName: "edit-none"
                        text: i18n("Sonuç yok")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "atasos"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PC3.Label {
                    text: "atasOS"
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: oturum
                    delegate: PC3.ToolButton {
                        id: gucDugmesi
                        required property int index
                        required property var model
                        // decoration bir QIcon; Kirigami.Icon hem QIcon'u hem simge adini gosterir
                        contentItem: Kirigami.Icon {
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            source: gucDugmesi.model.decoration
                        }
                        text: model.display
                        PC3.ToolTip.text: model.display
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: pencere.calistir(oturum, index)
                    }
                }
            }
        }
    }
}
