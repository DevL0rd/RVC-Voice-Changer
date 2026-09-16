import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "lib"
import "lib/Highlight.js" as Highlight

ColumnLayout {
    Layout.fillWidth: true
    visible: root.query === "" ? root.tabKey === "main" : Array.from(children).some(child => child.isSection === true && child.available && child.anyMatch)
    spacing: Kirigami.Units.largeSpacing

    Section {
        key: "voice"
        tab: "main"
        title: i18n("Voice")
        icon: "audio-input-microphone"
        keywords: [i18n("model"), i18n("voices")]
        trailing: root.voices.length === 0 ? "" : i18np("%1 voice", "%1 voices", root.voices.length)
        trailingColor: Kirigami.Theme.disabledTextColor

        SettingRow {
            id: voicePicker
            label: i18n("Voices")
            keywords: root.voices.map(voice => voice.name)
            readonly property var shownVoices: root.query === "" || matched && Highlight.matches(label, root.query) || (section && section.titleMatched)
                ? root.voices : root.voices.filter(voice => Highlight.matches(voice.name, root.query))

            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: voicePicker.shownVoices

                    Rectangle {
                        id: voiceChip
                        required property var modelData
                        readonly property bool selected: modelData.id === root.modelSettings.selected
                        readonly property bool ready: modelData.ready !== false
                        readonly property color hue: Qt.hsla((Array.from(modelData.name).reduce((sum, ch) => sum + ch.charCodeAt(0) * 7, 0) % 360) / 360, 0.55, 0.55, 1)

                        width: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 3
                        height: chipRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: height / 2
                        color: selected ? Qt.alpha(root.voiceAccent, 0.2) : chipHover.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.1) : Qt.alpha(Kirigami.Theme.textColor, 0.055)
                        border.width: 1
                        border.color: selected ? Qt.alpha(root.voiceAccent, 0.6) : !ready ? Qt.alpha(Kirigami.Theme.neutralTextColor, 0.5) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.patch("model", "selected", voiceChip.modelData.id) }
                        QQC2.ToolTip.visible: chipHover.hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: voiceChip.modelData.warning
                            ? voiceChip.modelData.warning
                            : voiceChip.modelData.index_path ? i18n("Model with retrieval index") : i18n("Model without an index file")

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Kirigami.Units.smallSpacing

                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                radius: width / 2
                                color: Qt.alpha(voiceChip.hue, voiceChip.selected ? 0.9 : 0.55)
                                PlasmaComponents.Label {
                                    anchors.centerIn: parent
                                    text: voiceChip.modelData.name.charAt(0).toUpperCase()
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                            PlasmaComponents.Label {
                                text: Highlight.mark(voiceChip.modelData.name, root.query, Kirigami.Theme.highlightColor)
                                textFormat: Text.StyledText
                                font.weight: voiceChip.selected ? Font.DemiBold : Font.Normal
                            }
                            Kirigami.Icon {
                                visible: !voiceChip.ready
                                source: "dialog-warning"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                            Rectangle {
                                visible: voiceChip.ready && !!voiceChip.modelData.index_path
                                Layout.preferredHeight: indexLabel.implicitHeight
                                Layout.preferredWidth: indexLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                                radius: height / 2
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
                                PlasmaComponents.Label {
                                    id: indexLabel
                                    anchors.centerIn: parent
                                    text: i18n("index")
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                                    opacity: 0.7
                                }
                            }
                        }
                    }
                }
            }
        }

        Note {
            available: root.voices.length === 0
            text: i18n("No voices yet. Put each voice in its own folder under models/ with one .pth file and an optional .index file.")
        }

        SettingRow {
            label: i18n("Voice models folder")
            keywords: [i18n("open folder"), i18n("rescan"), i18n("models")]
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.voices.length === 0 ? i18n("Add a model folder under models/") : i18np("%1 voice found", "%1 voices found", root.voices.length)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                    elide: Text.ElideRight
                }
                PlasmaComponents.ToolButton {
                    text: i18n("Open folder")
                    icon.name: "folder-open"
                    enabled: !!root.modelsUrl
                    onClicked: Qt.openUrlExternally(root.modelsUrl)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 450
                    QQC2.ToolTip.text: root.formatTooltip(i18n("Opens the models directory in the file manager. Put each voice in its own subfolder with one .pth model and an optional .index retrieval file. Files placed here are local and are not added to Git."))
                }
                PlasmaComponents.ToolButton {
                    text: i18n("Rescan")
                    icon.name: "view-refresh"
                    onClicked: root.rescan()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 450
                    QQC2.ToolTip.text: root.formatTooltip(i18n("Scans the models directory again after files are added, removed, or renamed. A folder without a .pth file is listed as incomplete. Rescanning does not stop the current voice unless its selected folder no longer exists."))
                }
            }
        }

        SettingRow {
            id: micLevel
            label: i18n("Microphone level")
            keywords: [i18n("input level"), i18n("volume"), i18n("dropped blocks")]
            help: i18n("The live level of the selected microphone. Dropped blocks count audio blocks that could not be processed in time.")
            readonly property real db: Number(root.runtime.input_level_db ?? -100)
            PopBar {
                Layout.fillWidth: true
                label: micLevel.label
                value: Math.max(0, Math.min(100, micLevel.db + 100))
                valueText: micLevel.db <= -99 ? i18n("silent") : Math.round(micLevel.db) + " dB"
                color: micLevel.db > -3 ? Kirigami.Theme.negativeTextColor : micLevel.db > -9 ? Kirigami.Theme.neutralTextColor : root.voiceAccent
                tooltip: micLevel.tip
            }
            PlasmaComponents.Label {
                visible: Number(root.runtime.dropped_blocks || 0) > 0
                text: i18np("%1 dropped block", "%1 dropped blocks", root.runtime.dropped_blocks)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.neutralTextColor
            }
        }
    }

    Section {
        key: "routing"
        tab: "main"
        title: i18n("Audio routing")
        icon: "audio-card"
        keywords: [i18n("devices"), i18n("microphone"), i18n("monitor")]

        PickerRow {
            label: i18n("Input microphone")
            keywords: [i18n("input device"), i18n("source")]
            help: i18n("The physical microphone captured by the converter. Selecting the wrong source can capture silence, desktop audio, or feedback. Changing it while running restarts the audio pipeline and causes a short interruption.")
            entries: root.inputs
            selectedId: root.audio.input_device || ""
            placeholder: i18n("Select device…")
            onChosen: function(value) { root.patch("audio", "input_device", value) }
        }
        ToggleRow {
            label: i18n("Monitor converted voice")
            keywords: [i18n("hear yourself"), i18n("listen")]
            checked: !!root.audio.monitor_enabled
            help: i18n("Sends a second copy of the converted voice to the selected monitor device so you can hear yourself. Monitoring adds another PipeWire stream and may create an echo or feedback loop when speakers are near the microphone. Headphones are strongly recommended.")
            onToggled: function(value) { root.patch("audio", "monitor_enabled", value) }
        }
        PickerRow {
            label: i18n("Monitor device")
            keywords: [i18n("headphones"), i18n("speakers")]
            help: i18n("The headphones or speakers used for local monitoring. This does not change what Discord receives. Avoid selecting the same physical path used as an open microphone source, because acoustic or software loopback can create feedback.")
            entries: root.monitors
            selectedId: root.audio.monitor_device || ""
            placeholder: i18n("Select device…")
            onChosen: function(value) { root.patch("audio", "monitor_device", value) }
        }
        TuningSlider {
            label: i18n("Input gain")
            keywords: [i18n("volume")]
            value: root.audio.input_gain_db || 0
            help: i18n("Amplifies or attenuates the microphone before filtering and RVC inference. Increase it when speech is too quiet for reliable pitch detection; reduce it if peaks distort. Excessive gain clips the waveform, raises background noise, and produces harsh conversion artifacts.")
            from: -24; to: 24; stepSize: 0.5; suffix: " dB"; decimals: 1
            onCommitted: function(value) { root.patch("audio", "input_gain_db", value) }
        }
        TuningSlider {
            label: i18n("Output gain")
            keywords: [i18n("volume")]
            value: root.audio.output_gain_db || 0
            help: i18n("Adjusts converted volume sent to RVC Virtual Microphone. It does not improve model detection. High positive gain can clip the converted waveform and sound distorted in Discord; negative gain preserves headroom but may be too quiet.")
            from: -24; to: 24; stepSize: 0.5; suffix: " dB"; decimals: 1
            onCommitted: function(value) { root.patch("audio", "output_gain_db", value) }
        }
        TuningSlider {
            label: i18n("Monitor gain")
            keywords: [i18n("volume")]
            value: root.audio.monitor_gain_db || 0
            help: i18n("Controls only the local monitor copy. It does not affect the virtual microphone or Discord level. Raising it too far can damage hearing, clip the monitor stream, or increase acoustic feedback risk.")
            from: -24; to: 24; stepSize: 0.5; suffix: " dB"; decimals: 1
            onCommitted: function(value) { root.patch("audio", "monitor_gain_db", value) }
        }
    }
}
