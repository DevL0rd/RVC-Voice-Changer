import QtQuick
import QtQuick.Layouts
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.components as PlasmaComponents

SettingRow {
    id: shortcut

    property string sequence
    signal changed(string sequence)

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: shortcut.markedLabel
            textFormat: Text.StyledText
            elide: Text.ElideRight
            opacity: 0.85
        }
        KQuickControls.KeySequenceItem {
            keySequence: shortcut.sequence
            multiKeyShortcutsAllowed: false
            modifierOnlyAllowed: false
            modifierlessAllowed: false
            onKeySequenceModified: shortcut.changed(String(keySequence))
        }
    }
}
