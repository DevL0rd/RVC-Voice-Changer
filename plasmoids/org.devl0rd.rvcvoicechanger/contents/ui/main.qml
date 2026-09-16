import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "lib"
import "lib/History.js" as History

PlasmoidItem {
    id: root

    readonly property string api: "http://127.0.0.1:17843/v1"
    property var cfg: ({})
    property var voices: []
    property var devices: ({})
    property var runtime: ({})
    property var translationLanguages: []
    property string modelsUrl: ""
    property var stamps: ({})
    property bool reachable: false
    property bool loaded: false
    property string requestError: ""
    property var logEntries: []
    property int latestLogId: 0
    property int tick: 0
    property var history: History.make(90)
    property string query: ""
    property Item menuFlickable: null
    property string tabKey: Plasmoid.configuration.rememberTab ? Plasmoid.configuration.currentTab : Plasmoid.configuration.defaultTab
    onTabKeyChanged: Plasmoid.configuration.currentTab = tabKey
    readonly property var collapsedCards: Plasmoid.configuration.collapsedCards.split(",").filter(name => name !== "")

    readonly property var audio: cfg.audio || ({})
    readonly property var modelSettings: cfg.model || ({})
    readonly property var cleanup: cfg.cleanup || ({})
    readonly property var gpu: cfg.gpu || ({})
    readonly property var translate: cfg.translate || ({})
    readonly property var incomingTranslate: cfg.incoming_translate || ({})
    readonly property var shortcuts: cfg.shortcuts || ({})
    readonly property var profile: runtime.profile_ms || ({})
    readonly property var inputs: devices.inputs || []
    readonly property var monitors: devices.monitors || []
    readonly property var outputs: devices.outputs || []
    readonly property var applications: devices.applications || []

    readonly property color voiceAccent: Kirigami.Theme.positiveTextColor
    readonly property color translateAccent: Kirigami.Theme.linkColor
    readonly property color incomingAccent: Kirigami.Theme.neutralTextColor

    readonly property bool voiceOn: !!runtime.enabled
    readonly property bool micTranslateOn: !!translate.enabled
    readonly property bool appTranslateOn: !!incomingTranslate.enabled
    readonly property bool failed: runtime.status === "error"
    readonly property bool micTranslateAvailable: micTranslateOn || !!translate.api_key_set
    readonly property bool appTranslateAvailable: appTranslateOn || (!!translate.api_key_set
        && !!incomingTranslate.application
        && indexOfId(applications, incomingTranslate.application) >= 0
        && !!incomingTranslate.output_device)

    readonly property var profileStages: [
        { key: "capture_wait", label: i18n("Microphone capture wait"), pacing: true },
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
        { key: "pipewire_write", label: i18n("Output backpressure"), pacing: true }
    ]

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool dataWanted: inPanel || visible
    readonly property bool shown: inPanel ? expanded : visible
    onShownChanged: if (shown) refresh()
    property bool popupAlive: !inPanel
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    onExpandedChanged: function() {
        if (root.expanded) {
            if (!Plasmoid.configuration.rememberTab)
                tabKey = Plasmoid.configuration.defaultTab
            releasePopup.stop()
            popupAlive = true
        } else if (inPanel) {
            releasePopup.restart()
        }
    }
    Timer {
        id: releasePopup
        interval: 1500
        onTriggered: root.popupAlive = root.expanded || !root.inPanel
    }

    Plasmoid.icon: voiceOn ? "microphone-sensitivity-high" : "audio-input-microphone"
    Plasmoid.title: i18n("RVC Voice Changer")
    toolTipMainText: i18n("RVC Voice Changer")
    toolTipSubText: trayStatusText()

    function request(method, path, payload, done) {
        const xhr = new XMLHttpRequest()
        xhr.open(method, api + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            let data = ({})
            try { data = JSON.parse(xhr.responseText || "{}") } catch (error) {}
            if (xhr.status === 0) {
                refreshing = false
                reachable = false
                requestError = i18n("Daemon is unavailable")
                return
            }
            reachable = true
            if (xhr.status >= 200 && xhr.status < 300) {
                requestError = ""
                if (data.config)
                    applyState(data)
                if (done)
                    done(data)
            } else {
                refreshing = false
                requestError = data.error || i18n("Daemon is unavailable")
                if (data.runtime)
                    take("runtime", data.runtime)
            }
        }
        xhr.send(payload === undefined ? null : JSON.stringify(payload))
    }

    function take(key, value) {
        const text = JSON.stringify(value)
        if (stamps[key] === text)
            return
        stamps[key] = text
        root[key] = value
    }
    function applyState(data) {
        take("cfg", data.config)
        take("voices", data.models || [])
        if (data.devices && Object.keys(data.devices).length > 0)
            take("devices", data.devices)
        take("runtime", data.runtime || {})
        take("translationLanguages", data.translation_languages || [])
        take("modelsUrl", data.models_url || "")
        loaded = true
    }

    function recordHistory() {
        if (!popupAlive || !shown)
            return
        History.push(history, "latency", voiceOn ? Number(runtime.latency_ms || 0) : 0)
        History.push(history, "load", voiceOn ? Number(runtime.realtime_factor || 0) * 100 : 0)
        History.push(history, "level", Math.max(0, Number(runtime.input_level_db ?? -100) + 100))
        tick++
    }
    function series(key) {
        tick
        return History.values(history, key)
    }

    property bool refreshing: false
    function refresh() {
        if (refreshing)
            return
        refreshing = true
        request("GET", "/state", undefined, function() { refreshing = false })
    }
    function refreshSummary() { request("GET", "/state?devices=0", undefined, recordHistory) }
    function refreshLogs() {
        request("GET", "/logs?after=" + latestLogId, undefined, function(data) {
            if (data.reset)
                logEntries = []
            if (data.entries && data.entries.length > 0) {
                const combined = logEntries.concat(data.entries)
                logEntries = combined.slice(Math.max(0, combined.length - 100))
            }
            latestLogId = Number(data.latest_id || 0)
        })
    }
    function rollingLogText() {
        return logEntries.map(entry => String(entry.time || "").slice(11, 19) + "  " + String(entry.level || "info").toUpperCase() + "  " + entry.message).join("\n")
    }
    function patch(section, key, value) {
        const body = ({})
        body[section] = ({})
        body[section][key] = value
        request("PATCH", "/config", body, null)
    }
    function setEnabled(value) { request("POST", "/enabled", { enabled: value }, null) }
    function rescan() { request("POST", "/models/rescan", {}, null) }
    function resetDefaults() { request("POST", "/config/reset", {}, function() { refresh() }) }
    function indexOfId(items, id) {
        for (let i = 0; i < items.length; ++i)
            if (items[i].id === id)
                return i
        return -1
    }
    function nameOf(items, id, fallback) {
        const index = indexOfId(items, id)
        return index >= 0 ? items[index].name : fallback
    }
    function selectedVoiceName() {
        return nameOf(voices, modelSettings.selected || "", i18n("No voice selected"))
    }
    function ms(value) {
        return Number(value || 0).toFixed(1) + " ms"
    }
    function trayStatusText() {
        if (!reachable)
            return i18n("Daemon is unavailable")
        if (failed)
            return runtime.error
        return i18n("Voice %1 · Mic translate %2 · App translate %3",
                    voiceOn ? i18n("On") : i18n("Off"),
                    micTranslateOn ? i18n("On") : i18n("Off"),
                    appTranslateOn ? i18n("On") : i18n("Off"))
    }
    function stageLabel(key) {
        const stage = profileStages.find(entry => entry.key === key)
        return stage ? stage.label : key || i18n("Collecting…")
    }
    function translationStatusText(status, error, liveText, connectingText, reconnectingText, errorText, startingText) {
        if (status === "running") return liveText
        if (status === "connecting") return connectingText
        if (status === "reconnecting") return reconnectingText
        if (status === "error") return errorText + ": " + (error || i18n("unknown error"))
        return startingText
    }
    function formatTooltip(value) {
        const words = String(value || "").trim().split(/\s+/)
        const lines = []
        let line = ""
        for (const word of words) {
            const candidate = line === "" ? word : line + " " + word
            if (candidate.length > 72 && line !== "") {
                lines.push(line)
                line = word
            } else {
                line = candidate
            }
        }
        if (line !== "")
            lines.push(line)
        return lines.join("\n")
    }
    function isCollapsed(key) {
        return query === "" && collapsedCards.indexOf(key) >= 0
    }
    function toggleCollapsed(key) {
        const next = collapsedCards.filter(entry => entry !== key)
        if (next.length === collapsedCards.length)
            next.push(key)
        Plasmoid.configuration.collapsedCards = next.join(",")
    }
    function scrollMenu(wheel) {
        if (!menuFlickable)
            return
        let delta = wheel.pixelDelta.y
        if (delta === 0)
            delta = wheel.angleDelta.y / 2
        if (wheel.inverted)
            delta = -delta
        const minimum = menuFlickable.originY
        const maximum = Math.max(minimum, minimum + menuFlickable.contentHeight - menuFlickable.height)
        menuFlickable.contentY = Math.max(minimum, Math.min(maximum, menuFlickable.contentY - delta))
        wheel.accepted = true
    }
    function middleClick() {
        if (Plasmoid.configuration.middleClickToggle)
            setEnabled(!voiceOn)
    }

    Component.onCompleted: refresh()
    Timer {
        interval: 1000
        running: root.dataWanted
        repeat: true
        onTriggered: root.refreshSummary()
    }
    Timer {
        interval: 5000
        running: root.shown
        repeat: true
        onTriggered: root.refresh()
    }

    compactRepresentation: CompactView {}
    fullRepresentation: FullView {}
}
