import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "lib"

MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real thickness: vertical ? width : height
    readonly property bool showLatency: Plasmoid.configuration.compactShowLatency
    readonly property bool showPipelines: Plasmoid.configuration.compactShowPipelines
    readonly property real iconSize: Math.round(Math.min(Kirigami.Units.iconSizes.medium, thickness * 0.62))
    property bool wasExpanded: false

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    onPressed: function(mouse) { wasExpanded = root.expanded }
    onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton)
            root.middleClick()
        else
            root.expanded = !wasExpanded
    }

    Layout.minimumWidth: vertical ? 0 : grid.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: vertical ? grid.implicitHeight + Kirigami.Units.smallSpacing * 2 : 0
    Layout.preferredHeight: Layout.minimumHeight

    component Light: Rectangle {
        required property bool active
        required property color accent
        width: Math.max(4, Math.round(compact.iconSize * 0.2))
        height: width
        radius: width / 2
        color: active ? accent : Qt.alpha(Kirigami.Theme.textColor, 0.18)
        Behavior on color { ColorAnimation { duration: 220 } }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, compact.containsMouse || root.expanded ? 0.08 : 0)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    GridLayout {
        id: grid
        anchors.centerIn: parent
        flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.alignment: Qt.AlignCenter
            spacing: 2

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: compact.iconSize
                Layout.preferredHeight: compact.iconSize
                Kirigami.Icon {
                    anchors.fill: parent
                    source: root.voiceOn ? "microphone-sensitivity-high" : "audio-input-microphone"
                    color: !root.reachable || root.failed ? Kirigami.Theme.negativeTextColor
                         : root.voiceOn ? root.voiceAccent : Kirigami.Theme.textColor
                    opacity: root.reachable ? 1 : 0.55
                    isMask: true
                }
            }
            Row {
                visible: compact.showPipelines
                Layout.alignment: Qt.AlignHCenter
                spacing: Math.max(2, Math.round(compact.iconSize * 0.12))
                Light { active: root.voiceOn; accent: root.voiceAccent }
                Light { active: root.micTranslateOn; accent: root.translateAccent }
                Light { active: root.appTranslateOn; accent: root.incomingAccent }
            }
        }

        PopChip {
            visible: compact.showLatency
            Layout.alignment: Qt.AlignCenter
            vertical: compact.vertical
            panelThickness: compact.thickness
            chipStyle: "none"
            widestValue: compact.vertical ? "" : "888"
            widestSecondary: compact.vertical ? "" : "ms"
            value: !root.reachable ? "—" : root.voiceOn && root.runtime.latency_ms > 0 ? Math.round(root.runtime.latency_ms) + "" : i18n("Off")
            valueColor: !root.reachable || root.failed ? Kirigami.Theme.negativeTextColor
                      : root.voiceOn ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
            secondary: root.voiceOn && root.runtime.latency_ms > 0 ? "ms" : ""
        }
    }
}
