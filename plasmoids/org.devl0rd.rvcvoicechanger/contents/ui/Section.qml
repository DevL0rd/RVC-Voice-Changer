import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "lib"
import "lib/Highlight.js" as Highlight

PopCard {
    id: section

    property string key
    property string tab
    property var keywords: []
    property bool available: true
    readonly property bool isSection: true
    readonly property bool titleMatched: root.query !== "" && Highlight.matchesAny([title].concat(keywords), root.query)
    readonly property bool anyMatch: {
        if (root.query === "")
            return false
        if (titleMatched)
            return true
        for (let i = 0; i < content.length; ++i) {
            if (content[i].matched === true)
                return true
        }
        return false
    }

    collapsible: key !== "" && root.query === ""
    collapsed: root.isCollapsed(key)
    onCollapseToggled: root.toggleCollapsed(key)
    visible: available && (root.query === "" ? root.tabKey === tab : anyMatch)
}
