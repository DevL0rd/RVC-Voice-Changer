import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "lib/Highlight.js" as Highlight

ColumnLayout {
    id: row

    property string label
    property string help
    property var keywords: []
    property bool available: true
    property Item section: null
    readonly property bool matched: root.query !== "" && label !== "" && Highlight.matchesAny([label].concat(keywords), root.query)
    readonly property bool searchHidden: root.query !== "" && !matched && !(section && section.titleMatched)
    readonly property string markedLabel: Highlight.mark(label, root.query, Kirigami.Theme.highlightColor)
    readonly property string tip: root.formatTooltip(help)

    Layout.fillWidth: true
    spacing: 2
    visible: available && !searchHidden

    Component.onCompleted: {
        let item = parent
        while (item && item.isSection !== true)
            item = item.parent
        section = item
    }
}
