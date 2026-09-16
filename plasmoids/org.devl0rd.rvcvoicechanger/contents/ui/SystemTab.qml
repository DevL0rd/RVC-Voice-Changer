import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "lib"
import "lib/Highlight.js" as Highlight

ColumnLayout {
    id: systemTab
    Layout.fillWidth: true
    visible: root.query === "" ? root.tabKey === "system" : Array.from(children).some(child => child.isSection === true && child.available && child.anyMatch)
    spacing: Kirigami.Units.largeSpacing

    readonly property bool gpuUsable: root.gpu.backend === "cuda" || (root.gpu.backend !== "cpu" && !!root.runtime.cuda_available)

    Section {
        key: "inference"
        tab: "system"
        title: i18n("Inference")
        icon: "cpu"
        keywords: [i18n("gpu"), i18n("cpu"), i18n("cuda"), i18n("rocm"), i18n("backend")]
        trailing: root.runtime.inference_backend ? String(root.runtime.inference_backend).toUpperCase() : ""
        trailingColor: Kirigami.Theme.positiveTextColor

        RowLayout {
            Layout.fillWidth: true
            visible: root.query === ""
            spacing: Kirigami.Units.largeSpacing
            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                radius: Kirigami.Units.cornerRadius * 2
                color: Qt.alpha(root.runtime.inference_device ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor, 0.12)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                    source: root.runtime.inference_backend === "cpu" || (!root.runtime.cuda_available && !root.runtime.rocm_available) ? "cpu" : "video-card"
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.runtime.inference_device
                        ? i18n("Active: %1 (%2)", root.runtime.inference_device, String(root.runtime.inference_backend || "").toUpperCase())
                        : root.runtime.cuda_available ? i18n("GPU and CPU inference available") : i18n("CPU inference available")
                    color: Kirigami.Theme.positiveTextColor
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: !!root.runtime.gpu_name
                    text: root.runtime.gpu_name + (root.runtime.rocm_available ? "  ·  ROCm" : root.runtime.cuda_available ? "  ·  CUDA" : "")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: !!root.runtime.virtual_microphone_name
                    text: root.runtime.virtual_microphone
                        ? i18n("%1 is ready", root.runtime.virtual_microphone_name)
                        : i18n("%1 is missing", root.runtime.virtual_microphone_name)
                    color: root.runtime.virtual_microphone ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                    font: Kirigami.Theme.smallFont
                    opacity: root.runtime.virtual_microphone ? 0.7 : 1
                    elide: Text.ElideRight
                }
            }
        }

        ChoiceRow {
            label: i18n("Backend")
            keywords: [i18n("gpu"), i18n("cpu"), i18n("auto")]
            options: [i18n("Auto"), i18n("GPU"), i18n("CPU")]
            currentIndex: root.gpu.backend === "cpu" ? 2 : root.gpu.backend === "cuda" ? 1 : 0
            help: i18n("Chooses where every RVC model runs. Auto prefers an available NVIDIA CUDA or AMD ROCm GPU and falls back to CPU on machines without a usable accelerator. GPU forces accelerated inference and reports an error if its PyTorch runtime is unavailable. CPU keeps GPU resources free for games but is usually slower and may require a larger block size to avoid audio underruns. Changing this unloads and reloads the full pipeline.")
            onActivated: function(index) { root.patch("gpu", "backend", ["auto", "cuda", "cpu"][index]) }
        }
        SpinRow {
            label: i18n("GPU device")
            keywords: [i18n("gpu index")]
            interactive: systemTab.gpuUsable
            from: 0; to: 15
            value: root.gpu.device || 0
            help: i18n("Selects the accelerated PyTorch device index used for every neural model. Device 0 is the first NVIDIA CUDA or AMD ROCm GPU visible to PyTorch. In Auto mode, an invalid saved index falls back to GPU 0; forced GPU mode reports an error instead. Changing devices unloads and reloads the full pipeline.")
            onModified: function(value) { root.patch("gpu", "device", value) }
        }
        ToggleRow {
            label: i18n("Allow TensorFloat-32 acceleration")
            keywords: ["tf32", i18n("precision")]
            checked: root.gpu.allow_tf32 !== false
            interactive: systemTab.gpuUsable && !root.runtime.rocm_available
            help: i18n("Allows NVIDIA TensorFloat-32 math for compatible float32 matrix operations. On RTX GPUs this can improve inference speed with a very small numerical precision tradeoff that is normally inaudible. It has no effect on CPU or AMD ROCm inference. Disabling it favors strict float32 behavior but may increase NVIDIA GPU latency. Changing it reloads the pipeline.")
            onToggled: function(value) { root.patch("gpu", "allow_tf32", value) }
        }
        SpinRow {
            label: i18n("CPU threads")
            keywords: [i18n("threads")]
            from: 0; to: 256
            value: root.gpu.cpu_threads || 0
            help: i18n("Limits PyTorch CPU inference threads. 0 automatically uses half of the machine's logical CPUs, leaving capacity for desktop audio and games. More threads can reduce CPU inference time but increase power use, heat, and contention with other programs; too many may make latency less stable. This is stored even while a GPU backend is active and takes effect whenever CPU inference is selected.")
            onModified: function(value) { root.patch("gpu", "cpu_threads", value) }
        }
        Note {
            text: i18n("Auto is recommended. Select CPU temporarily when a game needs the GPU, then switch back to Auto afterward.")
        }
    }

    Section {
        key: "shortcuts"
        tab: "system"
        title: i18n("Keyboard shortcuts")
        icon: "preferences-desktop-keyboard-shortcut"
        keywords: [i18n("hotkeys"), i18n("keys")]

        Note {
            text: i18n("These shortcuts work globally. Clear a shortcut to disable it.")
        }
        ShortcutRow {
            label: i18n("Toggle voice change")
            sequence: root.shortcuts.voice_change || ""
            onChanged: function(value) { root.patch("shortcuts", "voice_change", value) }
        }
        ShortcutRow {
            label: i18n("Toggle microphone translation")
            sequence: root.shortcuts.translation_out === undefined ? "Alt+T" : root.shortcuts.translation_out
            onChanged: function(value) { root.patch("shortcuts", "translation_out", value) }
        }
        ShortcutRow {
            label: i18n("Toggle application translation")
            sequence: root.shortcuts.translation_in || ""
            onChanged: function(value) { root.patch("shortcuts", "translation_in", value) }
        }
    }

    Section {
        id: logsSection
        key: "logs"
        tab: "system"
        title: i18n("Rolling logs")
        icon: "view-list-text"
        keywords: [i18n("events"), i18n("errors"), i18n("log")]
        trailing: root.logEntries.length > 0 ? root.logEntries.length + "" : ""
        trailingColor: Kirigami.Theme.disabledTextColor

        readonly property bool live: root.shown && visible && !collapsed
        onLiveChanged: if (live) root.refreshLogs()

        Timer {
            interval: 2000
            repeat: true
            running: logsSection.live
            onTriggered: root.refreshLogs()
        }

        TextEdit {
            id: clipboard
            visible: false
        }

        SettingRow {
            label: i18n("Log entries")
            keywords: [i18n("copy logs")]
            help: i18n("Shows lifecycle, model scan, setting-change, backend, bypass, and stream-error events from the current daemon process. The ring is intentionally bounded, restarts clear it, and profile samples are excluded to avoid per-block log overhead.")

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.logEntries.length === 0 ? i18n("No events recorded yet.") : i18np("Last %1 event", "Last %1 events", root.logEntries.length)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                }
                PlasmaComponents.ToolButton {
                    text: i18n("Copy all")
                    icon.name: "edit-copy"
                    enabled: root.logEntries.length > 0
                    onClicked: {
                        clipboard.text = root.rollingLogText()
                        clipboard.selectAll()
                        clipboard.copy()
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 450
                    QQC2.ToolTip.text: root.formatTooltip(i18n("Copies every log entry currently displayed in this section to the clipboard as plain text. The rolling in-memory log is not cleared or changed."))
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 12
                visible: root.logEntries.length > 0
                radius: Kirigami.Units.cornerRadius
                color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.55)
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.06)

                ListView {
                    id: logList
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    clip: true
                    model: root.logEntries
                    spacing: 2
                    onCountChanged: positionViewAtEnd()
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                    delegate: RowLayout {
                        id: logRow
                        required property var modelData
                        readonly property string level: String(modelData.level || "info").toLowerCase()
                        width: logList.width - Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignTop
                            text: String(logRow.modelData.time || "").slice(11, 19)
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.5
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                            Layout.preferredWidth: levelLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                            Layout.preferredHeight: levelLabel.implicitHeight
                            radius: height / 2
                            color: Qt.alpha(logRow.level === "error" ? Kirigami.Theme.negativeTextColor : logRow.level === "warning" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor, 0.14)
                            PlasmaComponents.Label {
                                id: levelLabel
                                anchors.centerIn: parent
                                text: logRow.level.toUpperCase()
                                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.8
                                font.weight: Font.DemiBold
                                color: logRow.level === "error" ? Kirigami.Theme.negativeTextColor : logRow.level === "warning" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                            }
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: Highlight.mark(logRow.modelData.message, root.query, Kirigami.Theme.highlightColor)
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }
        }
    }

    Section {
        key: ""
        tab: "system"
        title: i18n("Reset")
        icon: "edit-undo"
        keywords: [i18n("defaults"), i18n("factory")]

        SettingRow {
            label: i18n("Reset to defaults")
            help: i18n("Restores every setting to the shipped defaults and saves them immediately. This stops conversion, clears the selected microphone and voice, and disables monitoring and cleanup options. RVC Virtual Microphone remains present but is silent until an input microphone is selected. Your model files are not deleted. A second click within five seconds is required to prevent accidental resets.")
            PopConfirm {
                Layout.fillWidth: true
                label: i18n("Reset to defaults")
                iconName: "edit-undo"
                confirmText: i18n("Click again to reset everything")
                onConfirmed: root.resetDefaults()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 450
                QQC2.ToolTip.text: parent.tip
            }
        }
        Note {
            horizontalAlignment: Text.AlignHCenter
            text: i18n("Every change is applied immediately and saved for the next launch.")
        }
    }
}
