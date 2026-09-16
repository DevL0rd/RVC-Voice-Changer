import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.Label {
    id: note

    property bool available: true
    property Item section: null

    Layout.fillWidth: true
    visible: available && (root.query === "" || (section !== null && section.titleMatched))
    wrapMode: Text.Wrap
    font: Kirigami.Theme.smallFont
    opacity: 0.65

    Component.onCompleted: {
        let item = parent
        while (item && item.isSection !== true)
            item = item.parent
        section = item
    }
}
