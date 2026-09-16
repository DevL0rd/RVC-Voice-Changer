import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

SettingRow {
    id: choice

    property var options: []
    property int currentIndex: 0
    property string displayText
    signal activated(int index)

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: choice.markedLabel
            textFormat: Text.StyledText
            elide: Text.ElideRight
            opacity: 0.85
        }
        QQC2.ComboBox {
            wheelEnabled: false
            model: choice.options
            currentIndex: choice.currentIndex
            displayText: choice.displayText !== "" ? choice.displayText : currentText
            onActivated: function(index) { choice.activated(index) }
            QQC2.ToolTip.visible: hovered && choice.help !== ""
            QQC2.ToolTip.delay: 450
            QQC2.ToolTip.text: choice.tip
        }
    }
}
