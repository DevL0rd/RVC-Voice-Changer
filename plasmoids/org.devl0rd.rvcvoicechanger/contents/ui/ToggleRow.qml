import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

SettingRow {
    id: toggle

    property bool checked: false
    property bool interactive: true
    signal toggled(bool value)

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: toggle.markedLabel
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            opacity: toggle.interactive ? 0.85 : 0.45
        }
        QQC2.Switch {
            checked: toggle.checked
            enabled: toggle.interactive
            onToggled: toggle.toggled(checked)
            Accessible.name: toggle.label
            QQC2.ToolTip.visible: hovered && toggle.help !== ""
            QQC2.ToolTip.delay: 450
            QQC2.ToolTip.text: toggle.tip
        }
    }
}
