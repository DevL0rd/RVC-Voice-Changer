import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "lib"

ColumnLayout {
    Layout.fillWidth: true
    visible: root.query === "" ? root.tabKey === "translate" : Array.from(children).some(child => child.isSection === true && child.available && child.anyMatch)
    spacing: Kirigami.Units.largeSpacing

    Section {
        key: ""
        tab: "translate"
        title: i18n("Live translation")
        icon: "languages"
        keywords: [i18n("gemini"), i18n("translate")]
        trailing: root.translate.api_key_set ? i18n("Key saved") : i18n("No key")
        trailingColor: root.translate.api_key_set ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor

        GridLayout {
            Layout.fillWidth: true
            visible: root.query === ""
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            PopStat {
                Layout.fillWidth: true
                label: i18n("Microphone")
                value: !root.micTranslateOn ? i18n("Off") : root.runtime.translation_status === "running" ? Math.round(root.runtime.translation_latency_ms || 0) + "" : "…"
                unit: root.micTranslateOn && root.runtime.translation_status === "running" ? "ms" : ""
                color: root.micTranslateOn ? root.translateAccent : Kirigami.Theme.disabledTextColor
            }
            PopStat {
                Layout.fillWidth: true
                label: i18n("Application")
                value: !root.appTranslateOn ? i18n("Off") : root.runtime.incoming_translation_status === "running" ? Math.round(root.runtime.incoming_translation_latency_ms || 0) + "" : "…"
                unit: root.appTranslateOn && root.runtime.incoming_translation_status === "running" ? "ms" : ""
                color: root.appTranslateOn ? root.incomingAccent : Kirigami.Theme.disabledTextColor
            }
        }

        Note {
            available: !root.translate.api_key_set
            opacity: 1
            color: Kirigami.Theme.neutralTextColor
            text: i18n("Save an API key below to enable the translation switches at the top.")
        }

        ToggleRow {
            label: i18n("Keep speech already in the target language")
            keywords: [i18n("echo")]
            checked: !!root.translate.echo_target_language
            help: i18n("When enabled, Gemini repeats speech that is already in the selected target language. When disabled, it stays silent for that speech. Leave this off unless callers may already speak the target language; enabling it can introduce artifacts from background noise or music.")
            onToggled: function(value) { root.patch("translate", "echo_target_language", value) }
        }

        PickerRow {
            label: i18n("Translate microphone to")
            keywords: [i18n("language")]
            entries: root.translationLanguages
            selectedId: root.translate.target_language || "en"
            help: i18n("Selects the language spoken by Gemini Live Translate. Gemini detects the input language automatically. Changing this reconnects the translation stream when translation is enabled.")
            onChosen: function(value) { root.patch("translate", "target_language", value) }
        }

        TuningSlider {
            label: i18n("Original voice volume")
            keywords: [i18n("mix")]
            value: Number(root.translate.original_voice_volume || 0) * 100
            help: i18n("Mixes the immediate microphone signal into the RVC Virtual Microphone while translated speech arrives later. With Voice enabled, the immediate signal is voice-changed; with Voice disabled, it is the original microphone. Set this to 0% for translated speech only.")
            from: 0
            to: 100
            stepSize: 1
            suffix: "%"
            decimals: 0
            onCommitted: function(value) { root.patch("translate", "original_voice_volume", value / 100) }
        }

        SettingRow {
            label: i18n("Gemini API key")
            keywords: [i18n("api key"), i18n("token")]
            help: i18n("Stored only in your local user configuration with owner-only file permissions. The key is never returned by the daemon's state API. Entering a new key replaces the saved one when you leave this field.")
            PlasmaComponents.Label {
                text: parent.markedLabel
                textFormat: Text.StyledText
                font: Kirigami.Theme.smallFont
                opacity: 0.72
            }
            RowLayout {
                Layout.fillWidth: true
                QQC2.TextField {
                    id: apiKey
                    Layout.fillWidth: true
                    placeholderText: root.translate.api_key_set ? i18n("API key saved — enter to replace") : i18n("Enter API key")
                    echoMode: TextInput.Password
                    onEditingFinished: {
                        const key = text.trim()
                        if (key !== "") {
                            root.patch("translate", "api_key", key)
                            clear()
                        }
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 450
                    QQC2.ToolTip.text: parent.parent.tip
                }
                PlasmaComponents.Button {
                    text: i18n("Clear")
                    icon.name: "edit-clear"
                    enabled: !!root.translate.api_key_set
                    onClicked: {
                        apiKey.clear()
                        root.patch("translate", "api_key", "")
                    }
                }
            }
        }

        Note {
            available: root.micTranslateOn
            opacity: root.runtime.translation_status === "error" ? 1 : 0.65
            color: root.runtime.translation_status === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            text: root.translationStatusText(root.runtime.translation_status, root.runtime.translation_error,
                                             i18n("Connected · translated audio is live"),
                                             i18n("Connecting to Gemini…"),
                                             i18n("Reconnecting to Gemini…"),
                                             i18n("Translation unavailable"),
                                             i18n("Starting translation…"))
        }
    }

    Section {
        key: "apptranslate"
        tab: "translate"
        title: i18n("Application translation")
        icon: "applications-multimedia"
        keywords: [i18n("app translate"), i18n("incoming")]
        trailing: root.appTranslateOn ? i18n("On") : ""
        trailingColor: root.incomingAccent

        PickerRow {
            label: i18n("Running application")
            keywords: [i18n("app")]
            entries: root.applications
            selectedId: root.incomingTranslate.application || ""
            placeholder: root.applications.length === 0 ? i18n("No application is playing audio") : i18n("Select application…")
            help: i18n("Captures one currently running PipeWire application playback stream. If the application restarts, select its new stream again.")
            onChosen: function(value) { root.patch("incoming_translate", "application", value) }
        }
        PickerRow {
            label: i18n("Translated audio output")
            keywords: [i18n("output device"), i18n("speakers"), i18n("headphones")]
            entries: root.outputs
            selectedId: root.incomingTranslate.output_device || ""
            placeholder: i18n("Select device…")
            help: i18n("Plays translated application speech through this device. This is independent from the microphone monitor device.")
            onChosen: function(value) { root.patch("incoming_translate", "output_device", value) }
        }
        PickerRow {
            label: i18n("Translate application to")
            keywords: [i18n("language")]
            entries: root.translationLanguages
            selectedId: root.incomingTranslate.target_language || "en"
            help: i18n("Selects the application-audio translation language. English is the default, and Gemini detects the application's source language automatically.")
            onChosen: function(value) { root.patch("incoming_translate", "target_language", value) }
        }
        Note {
            text: i18n("The application's original audio continues playing normally. Translated speech is added on the selected output device.")
        }
        Note {
            available: root.appTranslateOn
            opacity: root.runtime.incoming_translation_status === "error" ? 1 : 0.65
            color: root.runtime.incoming_translation_status === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            text: root.translationStatusText(root.runtime.incoming_translation_status, root.runtime.incoming_translation_error,
                                             i18n("Connected · application translation is live"),
                                             i18n("Connecting application translation…"),
                                             i18n("Reconnecting application translation…"),
                                             i18n("Application translation unavailable"),
                                             i18n("Starting application translation…"))
        }
    }
}
