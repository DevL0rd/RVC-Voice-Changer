import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_compactShowLatency: compactShowLatency.checked
    property alias cfg_compactShowPipelines: compactShowPipelines.checked
    property alias cfg_middleClickToggle: middleClickToggle.checked
    property alias cfg_rememberTab: rememberTab.checked
    property string cfg_defaultTab
    property string cfg_currentTab
    property string cfg_collapsedCards

    QQC2.CheckBox { id: compactShowLatency; Kirigami.FormData.label: i18n("Panel shows:"); text: i18n("Voice latency") }
    QQC2.CheckBox { id: compactShowPipelines; text: i18n("Voice, mic translate and app translate lights") }
    QQC2.CheckBox { id: middleClickToggle; text: i18n("Middle-click switches the voice on and off") }

    Item { Kirigami.FormData.isSection: true }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Open on:")
        enabled: !rememberTab.checked
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Voice"), value: "main" },
            { text: i18n("Translate"), value: "translate" },
            { text: i18n("Tuning"), value: "tuning" },
            { text: i18n("System"), value: "system" }
        ]
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_defaultTab))
        onActivated: cfg_defaultTab = currentValue
    }
    QQC2.CheckBox { id: rememberTab; text: i18n("Reopen on the last tab") }
}
