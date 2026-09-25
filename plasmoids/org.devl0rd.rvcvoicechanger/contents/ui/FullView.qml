import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "lib"

Item {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.preferredHeight: Kirigami.Units.gridUnit * 40

    readonly property var tabDefs: [
        { key: "main", label: i18n("Voice"), icon: "audio-input-microphone" },
        { key: "translate", label: i18n("Translate"), icon: "languages" },
        { key: "tuning", label: i18n("Tuning"), icon: "adjustlevels" },
        { key: "system", label: i18n("System"), icon: "preferences-system" }
    ]

    component TabLoader: Loader {
        required property string key
        Layout.fillWidth: true
        active: root.query !== "" || root.tabKey === key
        visible: item !== null && (root.query === "" || Array.from(item.children).some(child => child.isSection === true && child.available && child.anyMatch))
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root.popupAlive
        sourceComponent: shellComponent
        onLoaded: if (root.expanded) item.focusSearch()
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded && loader.item)
                loader.item.focusSearch()
        }
    }

    Component {
        id: shellComponent

        PopupShell {
            id: shell

            readonly property int tabIndex: Math.max(0, full.tabDefs.findIndex(tab => tab.key === root.tabKey))
            readonly property var statusInfo: {
                if (!root.reachable)
                    return { color: Kirigami.Theme.negativeTextColor, text: i18n("Daemon is unavailable") }
                const status = root.runtime.status
                if (status === "error")
                    return { color: Kirigami.Theme.negativeTextColor, text: i18n("Error: %1", root.runtime.error || i18n("unknown")) }
                if (status === "loading")
                    return { color: Kirigami.Theme.neutralTextColor, text: i18n("Loading the voice model…") }
                if (status === "running")
                    return { color: Kirigami.Theme.positiveTextColor, text: i18n("Converting your voice") }
                if (status === "bypass")
                    return { color: Kirigami.Theme.disabledTextColor, text: i18n("Bypass · your microphone passes through unchanged") }
                return { color: Kirigami.Theme.disabledTextColor, text: i18n("Idle") }
            }

            function sections() {
                const found = []
                const walk = item => {
                    for (const child of item.children) {
                        if (child.isSection === true)
                            found.push(child)
                        else
                            walk(child)
                    }
                }
                walk(scroll.column)
                return found
            }
            readonly property int matchTotal: {
                root.query
                root.tick
                return root.query === "" ? -1 : sections().filter(section => section.visible).length
            }

            anchors.fill: parent
            icon: root.voiceOn ? "microphone-sensitivity-high" : "audio-input-microphone"
            title: i18n("RVC Voice Changer")
            subtitle: {
                const parts = [root.selectedVoiceName()]
                if (root.runtime.inference_device)
                    parts.push(i18n("%1 · %2", root.runtime.inference_device, String(root.runtime.inference_backend || "").toUpperCase()))
                else if (root.runtime.gpu_name)
                    parts.push(root.runtime.gpu_name.replace("NVIDIA GeForce ", "").replace("NVIDIA ", "").replace("AMD Radeon ", "Radeon "))
                return parts.join("  ·  ")
            }
            statusColor: statusInfo.color
            statusText: statusInfo.text
            searchPlaceholder: i18n("Search voices, devices, settings…")
            matchCount: matchTotal
            onSearchTextChanged: root.query = searchText.trim()
            Component.onDestruction: root.query = ""
            onCloseRequested: root.expanded = false
            onSearchAccepted: {
                const first = sections().find(section => section.visible)
                if (first)
                    scroll.scrollTo(first)
            }

            headerActions: [
                PlasmaComponents.ToolButton {
                    icon.name: "folder-open"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Open voice models folder")
                    enabled: !!root.modelsUrl
                    onClicked: Qt.openUrlExternally(root.modelsUrl)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                },
                PlasmaComponents.ToolButton {
                    icon.name: "configure"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Configure…")
                    onClicked: Plasmoid.internalAction("configure").trigger()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                }
            ]

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.largeSpacing

                GridLayout {
                    Layout.fillWidth: true
                    columns: shell.width < Kirigami.Units.gridUnit * 21 ? 1 : 3
                    columnSpacing: Kirigami.Units.smallSpacing * 1.5
                    rowSpacing: Kirigami.Units.smallSpacing * 1.5
                    visible: root.loaded

                    PipelineTile {
                        label: i18n("Voice")
                        iconName: "audio-input-microphone"
                        accent: root.voiceAccent
                        active: root.voiceOn
                        latency: Number(root.runtime.latency_ms || 0)
                        error: root.failed
                        status: root.failed ? i18n("Error")
                              : root.runtime.status === "loading" ? i18n("Loading %1…", root.selectedVoiceName())
                              : root.selectedVoiceName()
                        help: i18n("Switches RVC voice conversion on or off. Translation controls remain independent.")
                        onSwitched: function(value) { root.setEnabled(value) }
                    }
                    PipelineTile {
                        label: i18n("Mic translate")
                        iconName: "languages"
                        accent: root.translateAccent
                        active: root.micTranslateOn
                        available: root.micTranslateAvailable
                        latency: root.runtime.translation_status === "running" ? Number(root.runtime.translation_latency_ms || 0) : 0
                        error: root.micTranslateOn && root.runtime.translation_status === "error"
                        status: !root.translate.api_key_set ? i18n("Needs a Gemini API key")
                              : !root.micTranslateOn ? i18n("To %1", root.nameOf(root.translationLanguages, root.translate.target_language || "en", ""))
                              : root.translationStatusText(root.runtime.translation_status, root.runtime.translation_error,
                                                          i18n("Live · to %1", root.nameOf(root.translationLanguages, root.translate.target_language || "en", "")),
                                                          i18n("Connecting…"), i18n("Reconnecting…"), i18n("Error"), i18n("Starting…"))
                        help: root.translate.api_key_set
                            ? i18n("Translates microphone output. With Voice enabled it translates the converted voice; otherwise it translates the original microphone.")
                            : i18n("Save a Gemini API key in Live translation settings first.")
                        onSwitched: function(value) { root.patch("translate", "enabled", value) }
                    }
                    PipelineTile {
                        label: i18n("App translate")
                        iconName: "applications-multimedia"
                        accent: root.incomingAccent
                        active: root.appTranslateOn
                        available: root.appTranslateAvailable
                        latency: root.runtime.incoming_translation_status === "running" ? Number(root.runtime.incoming_translation_latency_ms || 0) : 0
                        error: root.appTranslateOn && root.runtime.incoming_translation_status === "error"
                        status: !root.appTranslateAvailable ? i18n("Pick an app and output")
                              : !root.appTranslateOn ? root.incomingTranslate.application || ""
                              : root.translationStatusText(root.runtime.incoming_translation_status, root.runtime.incoming_translation_error,
                                                          i18n("Live · %1", root.incomingTranslate.application || ""),
                                                          i18n("Connecting…"), i18n("Reconnecting…"), i18n("Error"), i18n("Starting…"))
                        help: available
                            ? i18n("Translates the selected running application's audio to its own output device.")
                            : i18n("Choose a running application and an application-translation output device below first.")
                        onSwitched: function(value) { root.patch("incoming_translate", "enabled", value) }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.loaded && (root.requestError !== "" || !!root.runtime.error)
                    implicitHeight: errorRow.implicitHeight + Kirigami.Units.smallSpacing * 3
                    radius: Kirigami.Units.cornerRadius * 2
                    color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.12)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.4)
                    RowLayout {
                        id: errorRow
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: "dialog-error"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: root.requestError || root.runtime.error || ""
                            color: Kirigami.Theme.negativeTextColor
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                    }
                }

                PopTabs {
                    visible: root.loaded && root.query === ""
                    Layout.fillWidth: true
                    model: full.tabDefs
                    currentIndex: shell.tabIndex
                    onActivated: function(index) {
                        root.tabKey = full.tabDefs[index].key
                        scroll.contentItem.contentY = 0
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    PopScroll {
                        id: scroll
                        anchors.fill: parent
                        visible: root.loaded
                        Component.onCompleted: root.menuFlickable = contentItem
                        Component.onDestruction: if (root.menuFlickable === contentItem) root.menuFlickable = null

                        TabLoader { key: "main"; sourceComponent: MainTab {} }
                        TabLoader { key: "translate"; sourceComponent: TranslateTab {} }
                        TabLoader { key: "tuning"; sourceComponent: TuningTab {} }
                        TabLoader { key: "system"; sourceComponent: SystemTab {} }
                        Item { Layout.preferredHeight: 1 }
                    }

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        visible: root.loaded && shell.matchTotal === 0
                        iconName: "edit-find"
                        text: i18n("No matches")
                        explanation: i18n("Try a voice name, pitch, gain, shortcut, GPU or noise")
                    }

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        visible: !root.loaded
                        iconName: "audio-input-microphone"
                        text: root.reachable ? i18n("Loading…") : i18n("The voice changer isn't running")
                        explanation: root.reachable ? "" : i18n("Start linux-rvc-voice-changer.service, or run install.sh if it isn't installed.")
                    }
                }
            }
        }
    }
}
