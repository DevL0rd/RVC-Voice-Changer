pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property string api: "http://127.0.0.1:17843/v1"
    property var snapshot: ({ config: {}, models: [], devices: {}, runtime: {} })
    property string requestError: ""
    property bool resetArmed: false
    property bool logsExpanded: false
    property var logEntries: []
    property int latestLogId: 0
    property var menuFlickable: null
    readonly property var cfg: snapshot.config || ({})
    readonly property var audio: cfg.audio || ({})
    readonly property var modelSettings: cfg.model || ({})
    readonly property var cleanup: cfg.cleanup || ({})
    readonly property var gpu: cfg.gpu || ({})
    readonly property var translate: cfg.translate || ({})
    readonly property var incomingTranslate: cfg.incoming_translate || ({})
    readonly property var shortcuts: cfg.shortcuts || ({})
    readonly property var runtime: snapshot.runtime || ({})
    readonly property var profile: runtime.profile_ms || ({})
    readonly property var voices: snapshot.models || []
    readonly property var inputs: (snapshot.devices || {}).inputs || []
    readonly property var monitors: (snapshot.devices || {}).monitors || []
    readonly property var outputs: (snapshot.devices || {}).outputs || []
    readonly property var applications: (snapshot.devices || {}).applications || []
    readonly property var translationLanguages: snapshot.translation_languages || []
    readonly property color voiceAccent: Kirigami.Theme.positiveTextColor
    readonly property color translateAccent: Kirigami.Theme.linkColor
    readonly property color incomingAccent: Kirigami.Theme.neutralTextColor
    readonly property var profileStages: [
        { key: "capture_wait", label: i18n("Microphone capture wait") },
        { key: "input_preprocess", label: i18n("Input gain and filters") },
        { key: "input_resample", label: i18n("Input resampling") },
        { key: "voice_activity_detection", label: i18n("Voice activity detection") },
        { key: "pitch_extraction", label: i18n("Pitch extraction") },
        { key: "contentvec", label: i18n("ContentVec features") },
        { key: "index_retrieval", label: i18n("Index retrieval") },
        { key: "feature_blend", label: i18n("Feature preparation") },
        { key: "generator", label: i18n("RVC generator") },
        { key: "rms_envelope", label: i18n("RMS envelope") },
        { key: "noise_cleanup", label: i18n("Noise cleanup") },
        { key: "output_resample", label: i18n("Output resampling") },
        { key: "sola_alignment", label: i18n("SOLA alignment") },
        { key: "silence_output", label: i18n("Silence handling") },
        { key: "inference_overhead", label: i18n("Inference CPU/dispatch overhead") },
        { key: "output_postprocess", label: i18n("Output gain and encoding") },
        { key: "pipewire_write", label: i18n("Output backpressure") }
    ]

    Plasmoid.icon: runtime.enabled ? "microphone-sensitivity-high" : "audio-input-microphone"
    Plasmoid.title: i18n("RVC Voice Changer")
    toolTipMainText: i18n("RVC Voice Changer")
    toolTipSubText: trayStatusText()
    preferredRepresentation: compactRepresentation

    function request(method, path, payload, done) {
        var xhr = new XMLHttpRequest()
        xhr.open(method, api + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var data = ({})
            try { data = JSON.parse(xhr.responseText || "{}") } catch (error) {}
            if (xhr.status >= 200 && xhr.status < 300) {
                requestError = ""
                if (data.config) {
                    if (!data.devices || Object.keys(data.devices).length === 0)
                        data.devices = snapshot.devices
                    snapshot = data
                }
                if (done) done(data)
            } else {
                requestError = data.error || i18n("Daemon is unavailable")
                if (data.runtime) {
                    var next = snapshot
                    next.runtime = data.runtime
                    snapshot = next
                }
            }
        }
        xhr.send(payload === undefined ? null : JSON.stringify(payload))
    }

    function refresh() { request("GET", "/state", undefined, null) }
    function refreshSummary() { request("GET", "/state?devices=0", undefined, null) }
    function refreshLogs() {
        request("GET", "/logs?after=" + latestLogId, undefined, function(data) {
            if (data.reset) logEntries = []
            if (data.entries && data.entries.length > 0) {
                var combined = logEntries.concat(data.entries)
                logEntries = combined.slice(Math.max(0, combined.length - 100))
            }
            latestLogId = Number(data.latest_id || 0)
        })
    }
    function rollingLogText() {
        if (logEntries.length === 0) return i18n("No events recorded yet.")
        var lines = []
        for (var i = 0; i < logEntries.length; ++i) {
            var entry = logEntries[i]
            var clock = String(entry.time || "").slice(11, 19)
            lines.push(clock + "  " + String(entry.level || "info").toUpperCase() + "  " + entry.message)
        }
        return lines.join("\n")
    }
    function patch(section, key, value) {
        var body = ({})
        body[section] = ({})
        body[section][key] = value
        request("PATCH", "/config", body, null)
    }
    function setEnabled(value) { request("POST", "/enabled", { enabled: value }, null) }
    function indexOfId(items, id) {
        for (var i = 0; i < items.length; ++i) if (items[i].id === id) return i
        return -1
    }
    function selectedVoiceName() {
        var index = indexOfId(voices, modelSettings.selected || "")
        return index >= 0 ? voices[index].name : i18n("No voice selected")
    }
    function trayStatusText() {
        if (runtime.status === "error") return runtime.error
        return i18n(
            "Voice %1 · Mic translate %2 · App translate %3",
            runtime.enabled ? i18n("On") : i18n("Off"),
            translate.enabled ? i18n("On") : i18n("Off"),
            incomingTranslate.enabled ? i18n("On") : i18n("Off")
        )
    }
    function stageLabel(key) {
        for (var i = 0; i < profileStages.length; ++i)
            if (profileStages[i].key === key) return profileStages[i].label
        return key || i18n("Collecting…")
    }
    function resetDefaults() {
        request("POST", "/config/reset", {}, function() {
            resetArmed = false
            refresh()
        })
    }
    function formatTooltip(value) {
        var words = String(value || "").trim().split(/\s+/)
        var lines = []
        var line = ""
        for (var i = 0; i < words.length; ++i) {
            var candidate = line === "" ? words[i] : line + " " + words[i]
            if (candidate.length > 72 && line !== "") {
                lines.push(line)
                line = words[i]
            } else {
                line = candidate
            }
        }
        if (line !== "") lines.push(line)
        return lines.join("\n")
    }
    function scrollMenu(wheel) {
        if (!menuFlickable) return
        var delta = wheel.pixelDelta.y
        if (delta === 0) delta = wheel.angleDelta.y / 2
        if (wheel.inverted) delta = -delta
        var minimum = menuFlickable.originY
        var maximum = Math.max(minimum, minimum + menuFlickable.contentHeight - menuFlickable.height)
        menuFlickable.contentY = Math.max(minimum, Math.min(maximum, menuFlickable.contentY - delta))
        wheel.accepted = true
    }

    Component.onCompleted: refresh()
    Timer { interval: 2000; running: root.expanded; repeat: true; onTriggered: root.refresh() }
    Timer {
        interval: 1000
        running: !root.expanded
        repeat: true
        onTriggered: root.refreshSummary()
    }
    Timer {
        interval: 2000
        running: root.expanded && root.logsExpanded
        repeat: true
        onTriggered: root.refreshLogs()
    }
    Timer { id: resetTimer; interval: 5000; onTriggered: root.resetArmed = false }

    compactRepresentation: MouseArea {
        id: compact
        implicitWidth: Kirigami.Units.gridUnit * 1.5
        implicitHeight: Kirigami.Units.gridUnit * 1.5
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            anchors.bottomMargin: Kirigami.Units.smallSpacing * 1.5
            source: root.runtime.enabled ? "microphone-sensitivity-high" : "audio-input-microphone"
            color: root.runtime.enabled ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            spacing: 2
            StatusDot {
                active: !!root.runtime.enabled
                accent: root.voiceAccent
            }
            StatusDot {
                active: !!root.translate.enabled
                accent: root.translateAccent
            }
            StatusDot {
                active: !!root.incomingTranslate.enabled
                accent: root.incomingAccent
            }
        }
    }

    component StatusDot: Rectangle {
        required property bool active
        required property color accent
        width: 5
        height: 5
        radius: width / 2
        color: active ? accent : Qt.alpha(Kirigami.Theme.backgroundColor, 0.75)
        border.width: 1
        border.color: active ? Qt.lighter(accent, 1.25) : Qt.alpha(accent, 0.55)
    }

    component Card: Rectangle {
        id: card
        property string title: ""
        property bool collapsible: true
        property bool sectionExpanded: false
        default property alias content: body.data
        Layout.fillWidth: true
        implicitHeight: layout.implicitHeight + Kirigami.Units.largeSpacing * 2
        clip: true
        radius: Kirigami.Units.smallSpacing
        color: Qt.alpha(Kirigami.Theme.textColor, 0.045)
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                visible: !card.collapsible
                text: card.title
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            QQC2.ToolButton {
                visible: card.collapsible
                Layout.fillWidth: true
                onClicked: card.sectionExpanded = !card.sectionExpanded
                Accessible.name: card.sectionExpanded
                    ? i18n("Collapse %1", card.title)
                    : i18n("Expand %1", card.title)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Label {
                        text: card.title
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    Kirigami.Icon {
                        source: card.sectionExpanded ? "go-down" : "go-next"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: width
                    }
                }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 450
                QQC2.ToolTip.text: root.formatTooltip(card.sectionExpanded
                    ? i18n("Collapses the %1 section to hide its controls without changing or resetting any settings.", card.title)
                    : i18n("Expands the %1 section to show its controls. Collapsing a section never disables its active settings.", card.title))
            }
            ColumnLayout {
                id: body
                visible: !card.collapsible || card.sectionExpanded
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
            }
        }
        Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    component DevicePicker: ColumnLayout {
        id: picker
        property string label: ""
        property string help: ""
        property var entries: []
        property string selectedId: ""
        signal chosen(string value)
        Layout.fillWidth: true
        spacing: 2
        PlasmaComponents.Label { text: picker.label; opacity: 0.72; font: Kirigami.Theme.smallFont }
        QQC2.ComboBox {
            id: deviceCombo
            Layout.fillWidth: true
            wheelEnabled: false
            model: picker.entries
            textRole: "name"
            currentIndex: root.indexOfId(picker.entries, picker.selectedId)
            displayText: currentIndex >= 0 ? picker.entries[currentIndex].name : i18n("Select device…")
            onActivated: function(index) { picker.chosen(picker.entries[index].id) }
            QQC2.ToolTip.visible: hovered && picker.help !== ""
            QQC2.ToolTip.delay: 450
            QQC2.ToolTip.text: root.formatTooltip(picker.help)
        }
    }

    component PipelineToggle: ColumnLayout {
        id: pipelineToggle
        property string label: ""
        property string latency: i18n("— ms")
        property string help: ""
        property color accent: Kirigami.Theme.textColor
        property bool active: false
        property bool available: true
        signal switched(bool value)
        Layout.fillWidth: true
        spacing: 0
        PlasmaComponents.Label {
            text: pipelineToggle.label
            color: pipelineToggle.active
                ? pipelineToggle.accent
                : Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        QQC2.Switch {
            checked: pipelineToggle.active
            enabled: pipelineToggle.available
            palette.highlight: pipelineToggle.accent
            Layout.alignment: Qt.AlignHCenter
            onToggled: pipelineToggle.switched(checked)
            Accessible.name: pipelineToggle.label
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 450
            QQC2.ToolTip.text: root.formatTooltip(pipelineToggle.help)
        }
        PlasmaComponents.Label {
            text: pipelineToggle.latency
            color: pipelineToggle.active
                ? pipelineToggle.accent
                : Kirigami.Theme.disabledTextColor
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
    }

    component ShortcutPicker: RowLayout {
        id: shortcutPicker
        property string label: ""
        property string sequence: ""
        signal changed(string sequence)
        Layout.fillWidth: true
        PlasmaComponents.Label {
            text: shortcutPicker.label
            Layout.fillWidth: true
        }
        KQuickControls.KeySequenceItem {
            keySequence: shortcutPicker.sequence
            multiKeyShortcutsAllowed: false
            modifierOnlyAllowed: false
            modifierlessAllowed: false
            onKeySequenceModified: shortcutPicker.changed(String(keySequence))
        }
    }

    component TuningSlider: ColumnLayout {
        id: tune
        property string label: ""
        property string help: ""
        property real value: 0
        property real from: 0
        property real to: 1
        property real stepSize: 0.01
        property string suffix: ""
        property int decimals: 2
        property bool pendingCommit: false
        signal committed(real value)
        function applyPending() {
            if (!pendingCommit) return
            pendingCommit = false
            committed(slider.value)
        }
        Layout.fillWidth: true
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label { text: tune.label; Layout.fillWidth: true; opacity: 0.8 }
            PlasmaComponents.Label { text: Number(slider.value).toFixed(tune.decimals) + tune.suffix; font.weight: Font.DemiBold }
        }
        QQC2.Slider {
            id: slider
            Layout.fillWidth: true
            wheelEnabled: false
            from: tune.from
            to: tune.to
            stepSize: tune.stepSize
            value: tune.value
            onMoved: {
                tune.pendingCommit = true
                sliderCommitTimer.restart()
            }
            onPressedChanged: if (!pressed) {
                sliderCommitTimer.stop()
                tune.applyPending()
            }
            QQC2.ToolTip.visible: hovered && tune.help !== ""
            QQC2.ToolTip.delay: 450
            QQC2.ToolTip.text: root.formatTooltip(tune.help)
            MouseArea {
                anchors.fill: parent
                z: 1000
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) { root.scrollMenu(wheel) }
            }
        }
        Timer {
            id: sliderCommitTimer
            interval: 100
            onTriggered: tune.applyPending()
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth: Kirigami.Units.gridUnit * 27
        Layout.minimumHeight: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 38

        QQC2.ScrollView {
            id: settingsScroll
            anchors.fill: parent
            contentWidth: availableWidth
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
            Component.onCompleted: root.menuFlickable = contentItem
            Component.onDestruction: if (root.menuFlickable === contentItem) root.menuFlickable = null

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        source: root.runtime.enabled ? "microphone-sensitivity-high" : "audio-input-microphone"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: width
                    }
                    PlasmaComponents.Label {
                        text: i18n("RVC Voice Changer")
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                        font.weight: Font.Bold
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.largeSpacing
                    PipelineToggle {
                        label: i18n("Voice")
                        accent: root.voiceAccent
                        active: !!root.runtime.enabled
                        latency: active
                            ? i18n("%1 ms", Number(root.runtime.latency_ms || 0).toFixed(1))
                            : i18n("— ms")
                        help: i18n("Switches RVC voice conversion on or off. Translation controls remain independent.")
                        onSwitched: function(value) { root.setEnabled(value) }
                    }
                    PipelineToggle {
                        label: i18n("Mic translate")
                        accent: root.translateAccent
                        active: !!root.translate.enabled
                        available: active || !!root.translate.api_key_set
                        latency: root.runtime.translation_status === "running"
                            && Number(root.runtime.translation_latency_ms || 0) > 0
                            ? i18n("%1 ms", Number(root.runtime.translation_latency_ms).toFixed(1))
                            : active ? i18n("… ms") : i18n("— ms")
                        help: root.translate.api_key_set
                            ? i18n("Translates microphone output. With Voice enabled it translates the converted voice; otherwise it translates the original microphone.")
                            : i18n("Save a Gemini API key in Live translation settings first.")
                        onSwitched: function(value) { root.patch("translate", "enabled", value) }
                    }
                    PipelineToggle {
                        label: i18n("App translate")
                        accent: root.incomingAccent
                        active: !!root.incomingTranslate.enabled
                        available: active || (!!root.translate.api_key_set
                            && !!root.incomingTranslate.application
                            && root.indexOfId(root.applications, root.incomingTranslate.application) >= 0
                            && !!root.incomingTranslate.output_device)
                        latency: root.runtime.incoming_translation_status === "running"
                            && Number(root.runtime.incoming_translation_latency_ms || 0) > 0
                            ? i18n("%1 ms", Number(root.runtime.incoming_translation_latency_ms).toFixed(1))
                            : active ? i18n("… ms") : i18n("— ms")
                        help: available
                            ? i18n("Translates the selected running application's audio to its own output device.")
                            : i18n("Choose a running application and an application-translation output device below first.")
                        onSwitched: function(value) { root.patch("incoming_translate", "enabled", value) }
                    }
                }

                PlasmaComponents.Label {
                    visible: root.requestError !== "" || root.runtime.error
                    text: root.requestError || root.runtime.error
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                }

                Card {
                    title: i18n("Voice")
                    collapsible: false
                    QQC2.ComboBox {
                        Layout.fillWidth: true
                        wheelEnabled: false
                        model: root.voices
                        textRole: "name"
                        currentIndex: root.indexOfId(root.voices, root.modelSettings.selected || "")
                        displayText: currentIndex >= 0 ? root.voices[currentIndex].name : i18n("Select a voice…")
                        onActivated: function(index) { root.patch("model", "selected", root.voices[index].id) }
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Selects the target RVC voice. Each entry represents one model folder containing a .pth file and, optionally, a .index file. Changing voices while running reloads the inference pipeline and briefly interrupts audio. Model quality and training data have the largest effect on the final voice."))
                    }
                    DevicePicker {
                        label: i18n("Translate to")
                        entries: root.translationLanguages
                        selectedId: root.translate.target_language || "en"
                        help: i18n("Selects the language spoken by Gemini Live Translate. Gemini detects the input language automatically. Changing this reconnects the translation stream when translation is enabled.")
                        onChosen: function(value) { root.patch("translate", "target_language", value) }
                    }
                    TuningSlider {
                        label: i18n("Original voice volume")
                        value: Number(root.translate.original_voice_volume || 0) * 100
                        help: i18n("Mixes the immediate microphone signal into the RVC Virtual Microphone while translated speech arrives later. With Voice enabled, the immediate signal is voice-changed; with Voice disabled, it is the original microphone. Set this to 0% for translated speech only.")
                        from: 0
                        to: 100
                        stepSize: 1
                        suffix: "%"
                        decimals: 0
                        onCommitted: function(value) { root.patch("translate", "original_voice_volume", value / 100) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: root.voices.length === 0 ? i18n("Add a model folder under models/") : i18np("%1 voice found", "%1 voices found", root.voices.length)
                            opacity: 0.65
                        }
                        QQC2.Button {
                            text: i18n("Open folder")
                            icon.name: "folder-open"
                            enabled: !!root.snapshot.models_url
                            onClicked: Qt.openUrlExternally(root.snapshot.models_url)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Opens the models directory in the file manager. Put each voice in its own subfolder with one .pth model and an optional .index retrieval file. Files placed here are local and are not added to Git."))
                        }
                        QQC2.Button {
                            text: i18n("Rescan")
                            icon.name: "view-refresh"
                            onClicked: root.request("POST", "/models/rescan", {}, null)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Scans the models directory again after files are added, removed, or renamed. A folder without a .pth file is listed as incomplete. Rescanning does not stop the current voice unless its selected folder no longer exists."))
                        }
                    }
                }

                Card {
                    title: i18n("Audio routing")
                    DevicePicker {
                        label: i18n("Input microphone")
                        help: i18n("The physical microphone captured by the converter. Selecting the wrong source can capture silence, desktop audio, or feedback. Changing it while running restarts the audio pipeline and causes a short interruption.")
                        entries: root.inputs
                        selectedId: root.audio.input_device || ""
                        onChosen: function(value) { root.patch("audio", "input_device", value) }
                    }
                    QQC2.CheckBox {
                        text: i18n("Monitor converted voice")
                        checked: !!root.audio.monitor_enabled
                        onToggled: root.patch("audio", "monitor_enabled", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Sends a second copy of the converted voice to the selected monitor device so you can hear yourself. Monitoring adds another PipeWire stream and may create an echo or feedback loop when speakers are near the microphone. Headphones are strongly recommended."))
                    }
                    DevicePicker {
                        label: i18n("Monitor device")
                        help: i18n("The headphones or speakers used for local monitoring. This does not change what Discord receives. Avoid selecting the same physical path used as an open microphone source, because acoustic or software loopback can create feedback.")
                        entries: root.monitors
                        selectedId: root.audio.monitor_device || ""
                        onChosen: function(value) { root.patch("audio", "monitor_device", value) }
                    }
                    TuningSlider {
                        label: i18n("Input gain"); value: root.audio.input_gain_db || 0
                        help: i18n("Amplifies or attenuates the microphone before filtering and RVC inference. Increase it when speech is too quiet for reliable pitch detection; reduce it if peaks distort. Excessive gain clips the waveform, raises background noise, and produces harsh conversion artifacts.")
                        from: -24; to: 24; stepSize: 0.5; suffix: " dB"; decimals: 1
                        onCommitted: function(value) { root.patch("audio", "input_gain_db", value) }
                    }
                    TuningSlider {
                        label: i18n("Output gain"); value: root.audio.output_gain_db || 0
                        help: i18n("Adjusts converted volume sent to RVC Virtual Microphone. It does not improve model detection. High positive gain can clip the converted waveform and sound distorted in Discord; negative gain preserves headroom but may be too quiet.")
                        from: -24; to: 24; stepSize: 0.5; suffix: " dB"; decimals: 1
                        onCommitted: function(value) { root.patch("audio", "output_gain_db", value) }
                    }
                    TuningSlider {
                        label: i18n("Monitor gain"); value: root.audio.monitor_gain_db || 0
                        help: i18n("Controls only the local monitor copy. It does not affect the virtual microphone or Discord level. Raising it too far can damage hearing, clip the monitor stream, or increase acoustic feedback risk.")
                        from: -24; to: 24; stepSize: 0.5; suffix: " dB"; decimals: 1
                        onCommitted: function(value) { root.patch("audio", "monitor_gain_db", value) }
                    }
                }

                Card {
                    title: i18n("Model settings")
                    TuningSlider {
                        label: i18n("Pitch"); value: root.modelSettings.pitch || 0
                        help: i18n("Shifts detected pitch in semitones before synthesis. Positive values raise the voice and negative values lower it; 12 semitones equals one octave. Large shifts can make speech unnatural, move it outside the model's trained range, and increase metallic or unstable artifacts.")
                        from: -24; to: 24; stepSize: 1; suffix: " st"; decimals: 0
                        onCommitted: function(value) { root.patch("model", "pitch", Math.round(value)) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("Speaker ID"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.SpinBox {
                            wheelEnabled: false
                            from: 0; to: 255; value: root.modelSettings.speaker_id || 0
                            onValueModified: root.patch("model", "speaker_id", value)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Selects a speaker slot inside a multi-speaker RVC checkpoint. Most downloadable voice models contain only speaker 0, so leave this at 0 unless the model author documents other IDs. An unavailable ID can produce the wrong voice or prevent inference. Changing it reloads the model and briefly interrupts audio."))
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("Pitch extraction"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.ComboBox {
                            wheelEnabled: false
                            model: ["rmvpe", "fcpe", "crepe", "crepe-tiny"]
                            currentIndex: Math.max(0, model.indexOf(root.modelSettings.f0_method || "rmvpe"))
                            onActivated: function(index) { root.patch("model", "f0_method", model[index]) }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Chooses the pitch detector on the active inference device. RMVPE is the balanced default and usually handles speech and singing well. FCPE can be faster but may track difficult voices differently. CREPE is heavier and often raises latency, especially on CPU; CREPE-tiny trades some pitch accuracy for lower compute cost. Changing this reloads the pipeline and briefly interrupts audio."))
                        }
                    }
                    TuningSlider {
                        label: i18n("Index rate"); value: root.modelSettings.index_rate ?? 0.75
                        help: i18n("Blends features retrieved from the voice's .index file with ContentVec features. 0 disables retrieval; higher values can strengthen the target identity and recover trained details. Very high values can copy training noise, reduce clarity, or create pronunciation artifacts. This has no effect when the voice has no .index file.")
                        onCommitted: function(value) { root.patch("model", "index_rate", value) }
                    }
                    TuningSlider {
                        label: i18n("Protect consonants"); value: root.modelSettings.protect ?? 0.33
                        help: i18n("Preserves unvoiced consonants and breathy sounds from the source to reduce tearing and metallic sibilants. Lower values apply more protection; 0.5 effectively disables it. Too much protection can leak more of the original voice, while too little can damage S, T, F, and breath sounds.")
                        from: 0; to: 0.5; stepSize: 0.01
                        onCommitted: function(value) { root.patch("model", "protect", value) }
                    }
                    TuningSlider {
                        label: i18n("RMS mix"); value: root.modelSettings.rms_mix_rate ?? 0.25
                        help: i18n("Controls how strongly output loudness follows the model instead of the source microphone envelope. Lower values preserve the source's natural dynamics; higher values use more of the synthesized level. Extremes can cause pumping, inconsistent loudness, or flattened expression depending on the model.")
                        onCommitted: function(value) { root.patch("model", "rms_mix_rate", value) }
                    }
                    QQC2.CheckBox {
                        text: i18n("Autotune pitch")
                        checked: !!root.modelSettings.autotune
                        onToggled: root.patch("model", "autotune", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Pulls detected pitch toward the nearest musical notes before synthesis. It can improve intentionally sung notes but often makes normal speech sound robotic or stepped. Strong autotune can erase slides, vibrato, and expressive pitch movement."))
                    }
                    TuningSlider {
                        label: i18n("Autotune strength"); value: root.modelSettings.autotune_strength ?? 1.0
                        help: i18n("Sets how far pitch is moved toward the nearest musical note. 0 leaves pitch unchanged and 1 snaps fully to the note. Higher values sound more tuned but can produce obvious pitch jumps and robotic speech; lower values retain more natural movement.")
                        onCommitted: function(value) { root.patch("model", "autotune_strength", value) }
                    }
                    QQC2.CheckBox {
                        text: i18n("Automatically target a pitch range")
                        checked: !!root.modelSettings.proposed_pitch
                        onToggled: root.patch("model", "proposed_pitch", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Measures the current median voice pitch and automatically shifts it toward the target pitch, limited to one octave in either direction. This helps match models trained for a different vocal range. Unstable or noisy pitch detection can make the calculated shift jump between chunks, and it should not normally be combined with manual pitch correction unless that is intentional."))
                    }
                    TuningSlider {
                        label: i18n("Target pitch"); value: root.modelSettings.proposed_pitch_threshold || 255
                        help: i18n("The center frequency, in hertz, used by automatic target-pitch shifting. 255 Hz is a relatively high vocal target. Lower values produce a deeper range and higher values a lighter range. A target far from your natural pitch may hit the one-octave limit or produce strained, synthetic artifacts.")
                        from: 50; to: 1200; stepSize: 5; suffix: " Hz"; decimals: 0
                        onCommitted: function(value) { root.patch("model", "proposed_pitch_threshold", value) }
                    }
                }

                Card {
                    title: i18n("Latency")
                    TuningSlider {
                        label: i18n("Block size"); value: root.audio.block_ms || 250
                        help: i18n("How much new microphone audio is processed per inference block. Smaller blocks reduce responsiveness delay but run the models more often, increasing device load and the risk of underruns, crackles, or unstable pitch. CPU inference commonly needs a larger block than GPU inference. Larger blocks are more reliable and efficient but add directly noticeable latency. Changing this restarts the stream.")
                        from: 20; to: 1000; stepSize: 10; suffix: " ms"; decimals: 0
                        onCommitted: function(value) { root.patch("audio", "block_ms", Math.round(value)) }
                    }
                    TuningSlider {
                        label: i18n("Crossfade"); value: root.audio.crossfade_ms || 50
                        help: i18n("Overlaps adjacent converted blocks and aligns them with SOLA before blending. More crossfade hides clicks and discontinuities but increases buffering and can smear fast consonants. Too little causes seams or crackles; values approaching the block size waste work and can sound phasey. Changing it restarts the stream.")
                        from: 0; to: 250; stepSize: 5; suffix: " ms"; decimals: 0
                        onCommitted: function(value) { root.patch("audio", "crossfade_ms", Math.round(value)) }
                    }
                    TuningSlider {
                        label: i18n("Extra context"); value: root.audio.extra_ms || 2500
                        help: i18n("Includes older audio when extracting pitch and voice features so the model has enough context for stable conversion. More context can improve continuity and difficult phonemes but raises processing time and GPU or system-memory use. Too little causes unstable timbre; too much may make inference slower than real time, particularly on CPU. Changing it restarts the stream.")
                        from: 100; to: 5000; stepSize: 100; suffix: " ms"; decimals: 0
                        onCommitted: function(value) { root.patch("audio", "extra_ms", Math.round(value)) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("Sample rate"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.ComboBox {
                            wheelEnabled: false
                            model: [32000, 40000, 44100, 48000]
                            currentIndex: Math.max(0, model.indexOf(root.audio.sample_rate || 48000))
                            textRole: ""
                            displayText: (root.audio.sample_rate || 48000) + " Hz"
                            onActivated: function(index) { root.patch("audio", "sample_rate", model[index]) }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Sets the PipeWire capture and playback rate. 48 kHz gives full voice bandwidth and is the usual desktop-audio rate. Lower rates reduce bandwidth and I/O work but may sound dull; unsupported hardware rates are resampled by PipeWire. Changing the rate rebuilds resamplers and restarts audio."))
                        }
                    }
                }

                Card {
                    title: i18n("Cleanup")
                    QQC2.CheckBox {
                        text: i18n("Voice activity detection")
                        checked: !!root.cleanup.vad_enabled
                        onToggled: root.patch("cleanup", "vad_enabled", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Detects whether each block contains speech and forces non-speech output to silence, which can suppress idle conversion residue and background artifacts. The RVC pipeline still runs during silence to keep inference response stable, so this does not reduce device usage. VAD adds a small CPU cost and may cut quiet or breathy speech. Toggling it reloads the pipeline."))
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("VAD sensitivity"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.SpinBox {
                            wheelEnabled: false
                            from: 0; to: 3; value: root.cleanup.vad_sensitivity ?? 3
                            onValueModified: root.patch("cleanup", "vad_sensitivity", value)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Controls WebRTC voice-detection aggressiveness from 0 to 3. Higher values are stricter about what counts as speech and suppress more noise, but can reject soft words, breaths, singing, or distant speech. Lower values preserve more quiet material while allowing more background noise through. Changing it reloads the pipeline."))
                        }
                    }
                    QQC2.CheckBox {
                        text: i18n("Noise suppression")
                        checked: !!root.cleanup.noise_suppression
                        onToggled: root.patch("cleanup", "noise_suppression", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Runs spectral noise reduction on the converted signal using the active inference device. It can reduce steady fan, hiss, and room noise, but adds processing work and may remove quiet consonants or create watery artifacts. Its cost is especially noticeable on CPU. Toggling it reloads the conversion pipeline."))
                    }
                    TuningSlider {
                        label: i18n("Suppression strength"); value: root.cleanup.noise_suppression_strength ?? 0.5
                        help: i18n("Controls how aggressively spectral noise is reduced. Higher values remove more background noise but are more likely to dull speech, damage breaths and consonants, or create swirling artifacts. Lower values preserve detail but leave more noise.")
                        onCommitted: function(value) { root.patch("cleanup", "noise_suppression_strength", value) }
                    }
                    TuningSlider {
                        label: i18n("Noise gate"); value: root.cleanup.noise_gate_db ?? -60
                        help: i18n("Treats microphone blocks below this level as silence and forces their output to silence. Raising the threshold suppresses more room noise and conversion residue, but can cut off quiet words and word endings. The RVC pipeline still runs to keep inference response stable, so gating does not reduce CPU or GPU usage. Lower thresholds preserve soft speech while allowing more background artifacts.")
                        from: -100; to: 0; stepSize: 1; suffix: " dB"; decimals: 0
                        onCommitted: function(value) { root.patch("cleanup", "noise_gate_db", value) }
                    }
                    TuningSlider {
                        label: i18n("High-pass filter"); value: root.cleanup.high_pass_hz || 0
                        help: i18n("Removes frequencies below the selected cutoff before RVC inference. It reduces desk vibration, handling noise, electrical hum, and low rumble. Setting it too high makes the voice thin, removes chest resonance, and can reduce model similarity. 0 Hz disables it.")
                        from: 0; to: 500; stepSize: 10; suffix: " Hz"; decimals: 0
                        onCommitted: function(value) { root.patch("cleanup", "high_pass_hz", Math.round(value)) }
                    }
                    TuningSlider {
                        label: i18n("Low-pass filter"); value: root.cleanup.low_pass_hz || 16000
                        help: i18n("Removes frequencies above the selected cutoff before conversion. Lower values reduce hiss and harsh high-frequency noise, but also dull S sounds, air, and clarity. Values at or above half the selected sample rate are effectively bypassed.")
                        from: 4000; to: 24000; stepSize: 500; suffix: " Hz"; decimals: 0
                        onCommitted: function(value) { root.patch("cleanup", "low_pass_hz", Math.round(value)) }
                    }
                }

                Card {
                    title: i18n("Live latency profile")
                    PlasmaComponents.Label {
                        visible: !root.runtime.enabled || root.profile.processing_total === undefined
                        text: root.runtime.enabled
                            ? i18n("Collecting the first audio block…")
                            : i18n("Start conversion to collect per-stage timing.")
                        opacity: 0.65
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        visible: root.profile.processing_total !== undefined
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: i18n("Paced loop total")
                            font.weight: Font.DemiBold
                        }
                        PlasmaComponents.Label {
                            text: Number(root.profile.processing_total || 0).toFixed(1) + " ms"
                            font.weight: Font.DemiBold
                        }
                    }
                    RowLayout {
                        visible: root.profile.compute_total !== undefined
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: i18n("Actual compute total")
                            opacity: 0.8
                        }
                        PlasmaComponents.Label {
                            text: Number(root.profile.compute_total || 0).toFixed(1) + " ms"
                            font.weight: Font.DemiBold
                        }
                    }
                    RowLayout {
                        visible: root.profile.processing_total !== undefined
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: i18n("Real-time load")
                            opacity: 0.8
                        }
                        PlasmaComponents.Label {
                            text: Number(root.runtime.realtime_factor || 0).toFixed(2) + "×"
                            color: (root.runtime.realtime_factor || 0) < 1
                                ? Kirigami.Theme.positiveTextColor
                                : Kirigami.Theme.negativeTextColor
                            font.weight: Font.DemiBold
                        }
                    }
                    Repeater {
                        model: root.profileStages
                        delegate: RowLayout {
                            id: profileRow
                            required property var modelData
                            readonly property bool available: root.profile[profileRow.modelData.key] !== undefined
                            visible: available
                            Layout.fillWidth: true
                            Layout.preferredHeight: available ? implicitHeight : 0
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: profileRow.modelData.label
                                color: root.runtime.bottleneck === profileRow.modelData.key
                                    ? Kirigami.Theme.neutralTextColor
                                    : Kirigami.Theme.textColor
                                font.weight: root.runtime.bottleneck === profileRow.modelData.key ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                            PlasmaComponents.Label {
                                text: Number(root.profile[profileRow.modelData.key] || 0).toFixed(2) + " ms"
                                font.family: "monospace"
                                font.weight: root.runtime.bottleneck === profileRow.modelData.key ? Font.Bold : Font.Normal
                            }
                        }
                    }
                    PlasmaComponents.Label {
                        visible: root.runtime.bottleneck
                        text: i18n("Highest compute stage: %1", root.stageLabel(root.runtime.bottleneck))
                        color: Kirigami.Theme.neutralTextColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        visible: root.profile.processing_total !== undefined
                        text: i18n("Values are a rolling average. Capture wait and output backpressure pace the real-time stream; they are visible here but excluded from compute load and the bottleneck result. A capture wait means the next block is still accumulating microphone samples, not that capture is using CPU. A compute load below 1× means processing finishes before the next block is due.")
                        opacity: 0.65
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                Card {
                    title: i18n("Inference")
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Icon { source: "checkmark"; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: width }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: root.runtime.inference_device
                                ? i18n("Active: %1 (%2)", root.runtime.inference_device, String(root.runtime.inference_backend || "").toUpperCase())
                                : root.runtime.cuda_available
                                    ? i18n("GPU and CPU inference available")
                                    : i18n("CPU inference available")
                            color: Kirigami.Theme.positiveTextColor
                            wrapMode: Text.Wrap
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("Backend"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.ComboBox {
                            wheelEnabled: false
                            model: [i18n("Auto"), i18n("GPU"), i18n("CPU")]
                            currentIndex: root.gpu.backend === "cpu" ? 2 : root.gpu.backend === "cuda" ? 1 : 0
                            onActivated: function(index) { root.patch("gpu", "backend", ["auto", "cuda", "cpu"][index]) }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Chooses where every RVC model runs. Auto prefers an available NVIDIA CUDA or AMD ROCm GPU and falls back to CPU on machines without a usable accelerator. GPU forces accelerated inference and reports an error if its PyTorch runtime is unavailable. CPU keeps GPU resources free for games but is usually slower and may require a larger block size to avoid audio underruns. Changing this unloads and reloads the full pipeline."))
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        enabled: root.gpu.backend === "cuda" || (root.gpu.backend !== "cpu" && root.runtime.cuda_available)
                        PlasmaComponents.Label { text: i18n("GPU device"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.SpinBox {
                            wheelEnabled: false
                            from: 0; to: 15; value: root.gpu.device || 0
                            onValueModified: root.patch("gpu", "device", value)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Selects the accelerated PyTorch device index used for every neural model. Device 0 is the first NVIDIA CUDA or AMD ROCm GPU visible to PyTorch. In Auto mode, an invalid saved index falls back to GPU 0; forced GPU mode reports an error instead. Changing devices unloads and reloads the full pipeline."))
                        }
                    }
                    QQC2.CheckBox {
                        text: i18n("Allow TensorFloat-32 acceleration")
                        enabled: (root.gpu.backend === "cuda" || (root.gpu.backend !== "cpu" && root.runtime.cuda_available)) && !root.runtime.rocm_available
                        checked: root.gpu.allow_tf32 !== false
                        onToggled: root.patch("gpu", "allow_tf32", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("Allows NVIDIA TensorFloat-32 math for compatible float32 matrix operations. On RTX GPUs this can improve inference speed with a very small numerical precision tradeoff that is normally inaudible. It has no effect on CPU or AMD ROCm inference. Disabling it favors strict float32 behavior but may increase NVIDIA GPU latency. Changing it reloads the pipeline."))
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: i18n("CPU threads"); Layout.fillWidth: true; opacity: 0.8 }
                        QQC2.SpinBox {
                            wheelEnabled: false
                            from: 0; to: 256; value: root.gpu.cpu_threads || 0
                            onValueModified: root.patch("gpu", "cpu_threads", value)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Limits PyTorch CPU inference threads. 0 automatically uses half of the machine's logical CPUs, leaving capacity for desktop audio and games. More threads can reduce CPU inference time but increase power use, heat, and contention with other programs; too many may make latency less stable. This is stored even while a GPU backend is active and takes effect whenever CPU inference is selected."))
                        }
                    }
                    PlasmaComponents.Label {
                        text: i18n("Auto is recommended. Select CPU temporarily when a game needs the GPU, then switch back to Auto afterward.")
                        opacity: 0.65
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                Card {
                    title: i18n("Live translation")
                    collapsible: true
                    PlasmaComponents.Label {
                        text: i18n("Microphone translation")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        visible: !root.translate.api_key_set
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Kirigami.Theme.neutralTextColor
                        text: i18n("Save an API key below to enable the translation switches at the top.")
                    }
                    QQC2.CheckBox {
                        text: i18n("Keep speech already in the target language")
                        checked: !!root.translate.echo_target_language
                        onToggled: root.patch("translate", "echo_target_language", checked)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: 450
                        QQC2.ToolTip.text: root.formatTooltip(i18n("When enabled, Gemini repeats speech that is already in the selected target language. When disabled, it stays silent for that speech. Leave this off unless callers may already speak the target language; enabling it can introduce artifacts from background noise or music."))
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: i18n("Gemini API key")
                        opacity: 0.72
                        font: Kirigami.Theme.smallFont
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.TextField {
                            id: translateApiKey
                            Layout.fillWidth: true
                            placeholderText: root.translate.api_key_set
                                ? i18n("API key saved — enter to replace")
                                : i18n("Enter API key")
                            echoMode: TextInput.Password
                            onEditingFinished: {
                                var key = text.trim()
                                if (key !== "") {
                                    root.patch("translate", "api_key", key)
                                    clear()
                                }
                            }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Stored only in your local user configuration with owner-only file permissions. The key is never returned by the daemon's state API. Entering a new key replaces the saved one when you leave this field."))
                        }
                        QQC2.Button {
                            text: i18n("Clear")
                            enabled: !!root.translate.api_key_set
                            onClicked: {
                                translateApiKey.clear()
                                root.patch("translate", "api_key", "")
                            }
                        }
                    }
                    PlasmaComponents.Label {
                        visible: !!root.translate.enabled
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: root.runtime.translation_status === "error" ? 1.0 : 0.65
                        color: root.runtime.translation_status === "error"
                            ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.textColor
                        text: root.runtime.translation_status === "running"
                            ? i18n("Connected · translated audio is live")
                            : root.runtime.translation_status === "connecting"
                                ? i18n("Connecting to Gemini…")
                                : root.runtime.translation_status === "reconnecting"
                                    ? i18n("Reconnecting to Gemini…")
                                    : root.runtime.translation_status === "error"
                                        ? i18n("Translation unavailable: %1", root.runtime.translation_error || i18n("unknown error"))
                                        : i18n("Starting translation…")
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: i18n("Application translation")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    DevicePicker {
                        label: i18n("Running application")
                        entries: root.applications
                        selectedId: root.incomingTranslate.application || ""
                        help: i18n("Captures one currently running PipeWire application playback stream. If the application restarts, select its new stream again.")
                        onChosen: function(value) { root.patch("incoming_translate", "application", value) }
                    }
                    DevicePicker {
                        label: i18n("Translated audio output")
                        entries: root.outputs
                        selectedId: root.incomingTranslate.output_device || ""
                        help: i18n("Plays translated application speech through this device. This is independent from the microphone monitor device.")
                        onChosen: function(value) { root.patch("incoming_translate", "output_device", value) }
                    }
                    DevicePicker {
                        label: i18n("Translate application to")
                        entries: root.translationLanguages
                        selectedId: root.incomingTranslate.target_language || "en"
                        help: i18n("Selects the application-audio translation language. English is the default, and Gemini detects the application's source language automatically.")
                        onChosen: function(value) { root.patch("incoming_translate", "target_language", value) }
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: 0.65
                        text: i18n("The application's original audio continues playing normally. Translated speech is added on the selected output device.")
                    }
                    PlasmaComponents.Label {
                        visible: !!root.incomingTranslate.enabled
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: root.runtime.incoming_translation_status === "error" ? 1.0 : 0.65
                        color: root.runtime.incoming_translation_status === "error"
                            ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.textColor
                        text: root.runtime.incoming_translation_status === "running"
                            ? i18n("Connected · application translation is live")
                            : root.runtime.incoming_translation_status === "connecting"
                                ? i18n("Connecting application translation…")
                                : root.runtime.incoming_translation_status === "reconnecting"
                                    ? i18n("Reconnecting application translation…")
                                    : root.runtime.incoming_translation_status === "error"
                                        ? i18n("Application translation unavailable: %1", root.runtime.incoming_translation_error || i18n("unknown error"))
                                        : i18n("Starting application translation…")
                    }
                }

                Card {
                    title: i18n("Keyboard shortcuts")
                    collapsible: true
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: 0.65
                        text: i18n("These shortcuts work globally. Clear a shortcut to disable it.")
                    }
                    ShortcutPicker {
                        label: i18n("Toggle voice change")
                        sequence: root.shortcuts.voice_change || ""
                        onChanged: function(value) { root.patch("shortcuts", "voice_change", value) }
                    }
                    ShortcutPicker {
                        label: i18n("Toggle microphone translation")
                        sequence: root.shortcuts.translation_out === undefined
                            ? "Alt+T"
                            : root.shortcuts.translation_out
                        onChanged: function(value) { root.patch("shortcuts", "translation_out", value) }
                    }
                    ShortcutPicker {
                        label: i18n("Toggle application translation")
                        sequence: root.shortcuts.translation_in || ""
                        onChanged: function(value) { root.patch("shortcuts", "translation_in", value) }
                    }
                }

                Card {
                    title: i18n("Rolling logs")
                    onSectionExpandedChanged: {
                        root.logsExpanded = sectionExpanded
                        if (sectionExpanded && root.expanded) root.refreshLogs()
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        QQC2.Button {
                            text: i18n("Copy all")
                            icon.name: "edit-copy"
                            enabled: root.logEntries.length > 0
                            onClicked: {
                                logArea.selectAll()
                                logArea.copy()
                                logArea.deselect()
                            }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Copies every log entry currently displayed in this section to the clipboard as plain text. The rolling in-memory log is not cleared or changed."))
                        }
                    }
                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 12
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                        QQC2.TextArea {
                            id: logArea
                            readOnly: true
                            selectByMouse: true
                            text: root.rollingLogText()
                            wrapMode: Text.WrapAnywhere
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            background: Rectangle {
                                color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.55)
                                radius: Kirigami.Units.smallSpacing
                            }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 450
                            QQC2.ToolTip.text: root.formatTooltip(i18n("Shows lifecycle, model scan, setting-change, backend, bypass, and stream-error events from the current daemon process. The ring is intentionally bounded, restarts clear it, and profile samples are excluded to avoid per-block log overhead. Selecting text does not change settings."))
                        }
                    }
                }

                QQC2.Button {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    text: root.resetArmed ? i18n("Click again to reset everything") : i18n("Reset to defaults")
                    icon.name: "edit-undo"
                    onClicked: {
                        if (root.resetArmed) {
                            resetTimer.stop()
                            root.resetDefaults()
                        } else {
                            root.resetArmed = true
                            resetTimer.restart()
                        }
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 450
                    QQC2.ToolTip.text: root.formatTooltip(i18n("Restores every setting to the shipped defaults and saves them immediately. This stops conversion, clears the selected microphone and voice, and disables monitoring and cleanup options. RVC Virtual Microphone remains present but is silent until an input microphone is selected. Your model files are not deleted. A second click within five seconds is required to prevent accidental resets."))
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    text: i18n("Every change is applied immediately and saved for the next launch.")
                    opacity: 0.6
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            }
        }
    }
}
