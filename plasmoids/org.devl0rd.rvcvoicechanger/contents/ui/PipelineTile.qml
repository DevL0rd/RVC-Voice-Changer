import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: tile

    property string label
    property string iconName
    property color accent: Kirigami.Theme.highlightColor
    property bool active: false
    property bool available: true
    property real latency: 0
    property string status
    property bool error: false
    property string help
    signal switched(bool value)

    readonly property bool hot: tileHover.hovered && available

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 5
    radius: Kirigami.Units.cornerRadius * 2
    color: active ? Qt.alpha(accent, hot ? 0.2 : 0.14) : Qt.alpha(Kirigami.Theme.textColor, hot ? 0.075 : 0.045)
    border.width: 1
    border.color: error ? Qt.alpha(Kirigami.Theme.negativeTextColor, 0.6) : active ? Qt.alpha(accent, 0.5) : Qt.alpha(Kirigami.Theme.textColor, 0.07)
    opacity: available ? 1 : 0.6
    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }

    HoverHandler { id: tileHover; cursorShape: tile.available ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: tile.available
        onTapped: tile.switched(!tile.active)
    }
    QQC2.ToolTip.visible: tileHover.hovered && tile.help !== ""
    QQC2.ToolTip.delay: 600
    QQC2.ToolTip.text: root.formatTooltip(tile.help)

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing * 2.5
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: tile.iconName
                color: tile.active ? tile.accent : Kirigami.Theme.textColor
                isMask: true
                opacity: tile.active ? 1 : 0.6
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: tile.label
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
                color: tile.active ? tile.accent : Kirigami.Theme.textColor
                opacity: tile.active ? 1 : 0.65
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                spacing: 2
                PlasmaComponents.Label {
                    id: bigValue
                    text: tile.active && tile.latency > 0 ? Math.round(tile.latency) + "" : tile.active ? "…" : i18n("Off")
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: tile.active ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                    Layout.alignment: Qt.AlignBaseline
                }
                PlasmaComponents.Label {
                    visible: tile.active && tile.latency > 0
                    text: "ms"
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    Layout.alignment: Qt.AlignBaseline
                }
            }
            Item { Layout.fillWidth: true }
            QQC2.Switch {
                checked: tile.active
                enabled: tile.available
                palette.highlight: tile.accent
                onToggled: tile.switched(checked)
                Accessible.name: tile.label
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: tile.status
            font: Kirigami.Theme.smallFont
            color: tile.error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            opacity: tile.error ? 1 : 0.65
            elide: Text.ElideRight
        }
    }
}
