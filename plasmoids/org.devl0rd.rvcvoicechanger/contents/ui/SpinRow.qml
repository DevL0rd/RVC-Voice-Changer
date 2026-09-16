import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

SettingRow {
    id: spin

    property int from: 0
    property int to: 100
    property int value: 0
    property bool interactive: true
    signal modified(int value)

    RowLayout {
        Layout.fillWidth: true
        enabled: spin.interactive
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: spin.markedLabel
            textFormat: Text.StyledText
            elide: Text.ElideRight
            opacity: 0.85
        }
        QQC2.SpinBox {
            wheelEnabled: false
            from: spin.from
            to: spin.to
            value: spin.value
            onValueModified: spin.modified(value)
            QQC2.ToolTip.visible: hovered && spin.help !== ""
            QQC2.ToolTip.delay: 450
            QQC2.ToolTip.text: spin.tip
        }
    }
}
