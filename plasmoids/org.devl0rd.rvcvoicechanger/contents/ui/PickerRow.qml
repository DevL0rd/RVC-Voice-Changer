import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

SettingRow {
    id: picker

    property var entries: []
    property string selectedId
    property string placeholder: i18n("Select…")
    signal chosen(string value)

    PlasmaComponents.Label {
        text: picker.markedLabel
        textFormat: Text.StyledText
        font: Kirigami.Theme.smallFont
        opacity: 0.72
    }
    QQC2.ComboBox {
        Layout.fillWidth: true
        wheelEnabled: false
        model: picker.entries
        textRole: "name"
        currentIndex: root.indexOfId(picker.entries, picker.selectedId)
        displayText: currentIndex >= 0 ? picker.entries[currentIndex].name : picker.placeholder
        onActivated: function(index) { picker.chosen(picker.entries[index].id) }
        QQC2.ToolTip.visible: hovered && picker.help !== ""
        QQC2.ToolTip.delay: 450
        QQC2.ToolTip.text: picker.tip
    }
}
