import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "lib"
import "lib/PopStyle.js" as Style
import "lib/Highlight.js" as Highlight

ColumnLayout {
    Layout.fillWidth: true
    visible: root.query === "" ? root.tabKey === "tuning" : Array.from(children).some(child => child.isSection === true && child.available && child.anyMatch)
    spacing: Kirigami.Units.largeSpacing

    Section {
        id: profileSection
        key: "profile"
        tab: "tuning"
        title: i18n("Live latency profile")
        icon: "office-chart-line"
        keywords: [i18n("latency"), i18n("performance"), i18n("bottleneck"), i18n("load")]
        trailing: root.voiceOn && root.runtime.latency_ms > 0 ? root.ms(root.runtime.latency_ms) : ""

        readonly property bool hasProfile: root.profile.processing_total !== undefined
        readonly property real stageMax: {
            let max = 0
            for (const stage of root.profileStages) {
                const value = Number(root.profile[stage.key] || 0)
                if (value > max)
                    max = value
            }
            return max
        }

        Note {
            available: !root.voiceOn || !profileSection.hasProfile
            text: root.voiceOn ? i18n("Collecting the first audio block…") : i18n("Start conversion to collect per-stage timing.")
        }

        RowLayout {
            visible: profileSection.hasProfile && root.query === ""
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            PopStat {
                Layout.fillWidth: true
                label: i18n("Paced loop")
                value: Number(root.profile.processing_total || 0).toFixed(1)
                unit: "ms"
            }
            PopStat {
                Layout.fillWidth: true
                label: i18n("Compute")
                value: Number(root.profile.compute_total || 0).toFixed(1)
                unit: "ms"
            }
            PopStat {
                Layout.fillWidth: true
                label: i18n("Real-time load")
                value: Number(root.runtime.realtime_factor || 0).toFixed(2)
                unit: "×"
                color: (root.runtime.realtime_factor || 0) < 1 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
            }
        }

        Sparkline {
            visible: root.voiceOn && root.query === ""
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3.4
            values: root.series("latency")
            gradient: false
            lineColor: root.voiceAccent
            rangeFloor: 50
            tipText: function(value) { return root.ms(value) }
        }

        PopBar {
            visible: profileSection.hasProfile && root.query === ""
            Layout.fillWidth: true
            label: i18n("Compute load per block")
            value: Math.min(100, Number(root.runtime.realtime_factor || 0) * 100)
            valueText: Math.round(Number(root.runtime.realtime_factor || 0) * 100) + "%"
            color: Style.heatStrong(Number(root.runtime.realtime_factor || 0) * 100, 70, 95, Kirigami.Theme)
        }

        Repeater {
            model: profileSection.hasProfile ? root.profileStages : []
            delegate: SettingRow {
                id: stageRow
                required property var modelData
                readonly property real stageMs: Number(root.profile[modelData.key] || 0)
                readonly property bool bottleneck: root.runtime.bottleneck === modelData.key
                label: modelData.label
                keywords: [modelData.key]
                available: root.profile[modelData.key] !== undefined
                PopBar {
                    Layout.fillWidth: true
                    label: stageRow.label + (stageRow.bottleneck ? "  ·  " + i18n("slowest") : "")
                    value: profileSection.stageMax > 0 ? stageRow.stageMs / profileSection.stageMax * 100 : 0
                    valueText: stageRow.stageMs.toFixed(2) + " ms"
                    color: stageRow.bottleneck ? Kirigami.Theme.neutralTextColor : stageRow.modelData.pacing ? Qt.alpha(Kirigami.Theme.textColor, 0.35) : root.voiceAccent
                    thickness: Kirigami.Units.smallSpacing
                    tooltip: stageRow.modelData.pacing ? i18n("Pacing stage: excluded from compute load") : ""
                }
            }
        }

        Note {
            available: root.runtime.bottleneck !== undefined && root.runtime.bottleneck !== ""
            opacity: 1
            color: Kirigami.Theme.neutralTextColor
            text: i18n("Highest compute stage: %1", root.stageLabel(root.runtime.bottleneck))
        }
        Note {
            available: profileSection.hasProfile
            text: i18n("Values are a rolling average. Capture wait and output backpressure pace the real-time stream; they are visible here but excluded from compute load and the bottleneck result. A capture wait means the next block is still accumulating microphone samples, not that capture is using CPU. A compute load below 1× means processing finishes before the next block is due.")
        }
    }

    Section {
        key: "model"
        tab: "tuning"
        title: i18n("Model settings")
        icon: "audio-x-generic"
        keywords: [i18n("voice model")]

        TuningSlider {
            label: i18n("Pitch")
            keywords: [i18n("semitones"), i18n("octave")]
            value: root.modelSettings.pitch || 0
            help: i18n("Shifts detected pitch in semitones before synthesis. Positive values raise the voice and negative values lower it; 12 semitones equals one octave. Large shifts can make speech unnatural, move it outside the model's trained range, and increase metallic or unstable artifacts.")
            from: -24; to: 24; stepSize: 1; suffix: " st"; decimals: 0
            onCommitted: function(value) { root.patch("model", "pitch", Math.round(value)) }
        }
        SpinRow {
            label: i18n("Speaker ID")
            keywords: [i18n("speaker")]
            from: 0; to: 255
            value: root.modelSettings.speaker_id || 0
            help: i18n("Selects a speaker slot inside a multi-speaker RVC checkpoint. Most downloadable voice models contain only speaker 0, so leave this at 0 unless the model author documents other IDs. An unavailable ID can produce the wrong voice or prevent inference. Changing it reloads the model and briefly interrupts audio.")
            onModified: function(value) { root.patch("model", "speaker_id", value) }
        }
        ChoiceRow {
            label: i18n("Pitch extraction")
            keywords: ["rmvpe", "fcpe", "crepe", "f0"]
            options: ["rmvpe", "fcpe", "crepe", "crepe-tiny"]
            currentIndex: Math.max(0, options.indexOf(root.modelSettings.f0_method || "rmvpe"))
            help: i18n("Chooses the pitch detector on the active inference device. RMVPE is the balanced default and usually handles speech and singing well. FCPE can be faster but may track difficult voices differently. CREPE is heavier and often raises latency, especially on CPU; CREPE-tiny trades some pitch accuracy for lower compute cost. Changing this reloads the pipeline and briefly interrupts audio.")
            onActivated: function(index) { root.patch("model", "f0_method", options[index]) }
        }
        TuningSlider {
            label: i18n("Index rate")
            keywords: [i18n("retrieval")]
            value: root.modelSettings.index_rate ?? 0.75
            help: i18n("Blends features retrieved from the voice's .index file with ContentVec features. 0 disables retrieval; higher values can strengthen the target identity and recover trained details. Very high values can copy training noise, reduce clarity, or create pronunciation artifacts. This has no effect when the voice has no .index file.")
            onCommitted: function(value) { root.patch("model", "index_rate", value) }
        }
        TuningSlider {
            label: i18n("Protect consonants")
            keywords: [i18n("protect")]
            value: root.modelSettings.protect ?? 0.33
            help: i18n("Preserves unvoiced consonants and breathy sounds from the source to reduce tearing and metallic sibilants. Lower values apply more protection; 0.5 effectively disables it. Too much protection can leak more of the original voice, while too little can damage S, T, F, and breath sounds.")
            from: 0; to: 0.5; stepSize: 0.01
            onCommitted: function(value) { root.patch("model", "protect", value) }
        }
        TuningSlider {
            label: i18n("RMS mix")
            keywords: [i18n("loudness"), i18n("envelope")]
            value: root.modelSettings.rms_mix_rate ?? 0.25
            help: i18n("Controls how strongly output loudness follows the model instead of the source microphone envelope. Lower values preserve the source's natural dynamics; higher values use more of the synthesized level. Extremes can cause pumping, inconsistent loudness, or flattened expression depending on the model.")
            onCommitted: function(value) { root.patch("model", "rms_mix_rate", value) }
        }
        ToggleRow {
            label: i18n("Autotune pitch")
            checked: !!root.modelSettings.autotune
            help: i18n("Pulls detected pitch toward the nearest musical notes before synthesis. It can improve intentionally sung notes but often makes normal speech sound robotic or stepped. Strong autotune can erase slides, vibrato, and expressive pitch movement.")
            onToggled: function(value) { root.patch("model", "autotune", value) }
        }
        TuningSlider {
            label: i18n("Autotune strength")
            value: root.modelSettings.autotune_strength ?? 1.0
            help: i18n("Sets how far pitch is moved toward the nearest musical note. 0 leaves pitch unchanged and 1 snaps fully to the note. Higher values sound more tuned but can produce obvious pitch jumps and robotic speech; lower values retain more natural movement.")
            onCommitted: function(value) { root.patch("model", "autotune_strength", value) }
        }
        ToggleRow {
            label: i18n("Automatically target a pitch range")
            keywords: [i18n("proposed pitch")]
            checked: !!root.modelSettings.proposed_pitch
            help: i18n("Measures the current median voice pitch and automatically shifts it toward the target pitch, limited to one octave in either direction. This helps match models trained for a different vocal range. Unstable or noisy pitch detection can make the calculated shift jump between chunks, and it should not normally be combined with manual pitch correction unless that is intentional.")
            onToggled: function(value) { root.patch("model", "proposed_pitch", value) }
        }
        TuningSlider {
            label: i18n("Target pitch")
            keywords: [i18n("hz")]
            value: root.modelSettings.proposed_pitch_threshold || 255
            help: i18n("The center frequency, in hertz, used by automatic target-pitch shifting. 255 Hz is a relatively high vocal target. Lower values produce a deeper range and higher values a lighter range. A target far from your natural pitch may hit the one-octave limit or produce strained, synthetic artifacts.")
            from: 50; to: 1200; stepSize: 5; suffix: " Hz"; decimals: 0
            onCommitted: function(value) { root.patch("model", "proposed_pitch_threshold", value) }
        }
    }

    Section {
        key: "latency"
        tab: "tuning"
        title: i18n("Latency")
        icon: "chronometer"
        keywords: [i18n("buffer"), i18n("block")]

        TuningSlider {
            label: i18n("Block size")
            keywords: [i18n("block")]
            value: root.audio.block_ms || 250
            help: i18n("How much new microphone audio is processed per inference block. Smaller blocks reduce responsiveness delay but run the models more often, increasing device load and the risk of underruns, crackles, or unstable pitch. CPU inference commonly needs a larger block than GPU inference. Larger blocks are more reliable and efficient but add directly noticeable latency. Changing this restarts the stream.")
            from: 20; to: 1000; stepSize: 10; suffix: " ms"; decimals: 0
            onCommitted: function(value) { root.patch("audio", "block_ms", Math.round(value)) }
        }
        TuningSlider {
            label: i18n("Crossfade")
            keywords: [i18n("sola")]
            value: root.audio.crossfade_ms || 50
            help: i18n("Overlaps adjacent converted blocks and aligns them with SOLA before blending. More crossfade hides clicks and discontinuities but increases buffering and can smear fast consonants. Too little causes seams or crackles; values approaching the block size waste work and can sound phasey. Changing it restarts the stream.")
            from: 0; to: 250; stepSize: 5; suffix: " ms"; decimals: 0
            onCommitted: function(value) { root.patch("audio", "crossfade_ms", Math.round(value)) }
        }
        TuningSlider {
            label: i18n("Extra context")
            keywords: [i18n("context")]
            value: root.audio.extra_ms || 2500
            help: i18n("Includes older audio when extracting pitch and voice features so the model has enough context for stable conversion. More context can improve continuity and difficult phonemes but raises processing time and GPU or system-memory use. Too little causes unstable timbre; too much may make inference slower than real time, particularly on CPU. Changing it restarts the stream.")
            from: 100; to: 5000; stepSize: 100; suffix: " ms"; decimals: 0
            onCommitted: function(value) { root.patch("audio", "extra_ms", Math.round(value)) }
        }
        ChoiceRow {
            label: i18n("Sample rate")
            keywords: [i18n("hz"), i18n("khz")]
            options: [32000, 40000, 44100, 48000]
            currentIndex: Math.max(0, options.indexOf(root.audio.sample_rate || 48000))
            displayText: (root.audio.sample_rate || 48000) + " Hz"
            help: i18n("Sets the PipeWire capture and playback rate. 48 kHz gives full voice bandwidth and is the usual desktop-audio rate. Lower rates reduce bandwidth and I/O work but may sound dull; unsupported hardware rates are resampled by PipeWire. Changing the rate rebuilds resamplers and restarts audio.")
            onActivated: function(index) { root.patch("audio", "sample_rate", options[index]) }
        }
    }

    Section {
        key: "cleanup"
        tab: "tuning"
        title: i18n("Cleanup")
        icon: "edit-clear-all"
        keywords: [i18n("noise"), i18n("filter")]

        ToggleRow {
            label: i18n("Voice activity detection")
            keywords: ["vad"]
            checked: !!root.cleanup.vad_enabled
            help: i18n("Detects whether each block contains speech and forces non-speech output to silence, which can suppress idle conversion residue and background artifacts. The RVC pipeline still runs during silence to keep inference response stable, so this does not reduce device usage. VAD adds a small CPU cost and may cut quiet or breathy speech. Toggling it reloads the pipeline.")
            onToggled: function(value) { root.patch("cleanup", "vad_enabled", value) }
        }
        SpinRow {
            label: i18n("VAD sensitivity")
            keywords: ["vad"]
            from: 0; to: 3
            value: root.cleanup.vad_sensitivity ?? 3
            help: i18n("Controls WebRTC voice-detection aggressiveness from 0 to 3. Higher values are stricter about what counts as speech and suppress more noise, but can reject soft words, breaths, singing, or distant speech. Lower values preserve more quiet material while allowing more background noise through. Changing it reloads the pipeline.")
            onModified: function(value) { root.patch("cleanup", "vad_sensitivity", value) }
        }
        ToggleRow {
            label: i18n("Noise suppression")
            keywords: [i18n("denoise")]
            checked: !!root.cleanup.noise_suppression
            help: i18n("Runs spectral noise reduction on the converted signal using the active inference device. It can reduce steady fan, hiss, and room noise, but adds processing work and may remove quiet consonants or create watery artifacts. Its cost is especially noticeable on CPU. Toggling it reloads the conversion pipeline.")
            onToggled: function(value) { root.patch("cleanup", "noise_suppression", value) }
        }
        TuningSlider {
            label: i18n("Suppression strength")
            keywords: [i18n("noise")]
            value: root.cleanup.noise_suppression_strength ?? 0.5
            help: i18n("Controls how aggressively spectral noise is reduced. Higher values remove more background noise but are more likely to dull speech, damage breaths and consonants, or create swirling artifacts. Lower values preserve detail but leave more noise.")
            onCommitted: function(value) { root.patch("cleanup", "noise_suppression_strength", value) }
        }
        TuningSlider {
            label: i18n("Noise gate")
            keywords: [i18n("gate"), i18n("threshold")]
            value: root.cleanup.noise_gate_db ?? -60
            help: i18n("Treats microphone blocks below this level as silence and forces their output to silence. Raising the threshold suppresses more room noise and conversion residue, but can cut off quiet words and word endings. The RVC pipeline still runs to keep inference response stable, so gating does not reduce CPU or GPU usage. Lower thresholds preserve soft speech while allowing more background artifacts.")
            from: -100; to: 0; stepSize: 1; suffix: " dB"; decimals: 0
            onCommitted: function(value) { root.patch("cleanup", "noise_gate_db", value) }
        }
        TuningSlider {
            label: i18n("High-pass filter")
            keywords: [i18n("rumble"), i18n("hum")]
            value: root.cleanup.high_pass_hz || 0
            help: i18n("Removes frequencies below the selected cutoff before RVC inference. It reduces desk vibration, handling noise, electrical hum, and low rumble. Setting it too high makes the voice thin, removes chest resonance, and can reduce model similarity. 0 Hz disables it.")
            from: 0; to: 500; stepSize: 10; suffix: " Hz"; decimals: 0
            onCommitted: function(value) { root.patch("cleanup", "high_pass_hz", Math.round(value)) }
        }
        TuningSlider {
            label: i18n("Low-pass filter")
            keywords: [i18n("hiss")]
            value: root.cleanup.low_pass_hz || 16000
            help: i18n("Removes frequencies above the selected cutoff before conversion. Lower values reduce hiss and harsh high-frequency noise, but also dull S sounds, air, and clarity. Values at or above half the selected sample rate are effectively bypassed.")
            from: 4000; to: 24000; stepSize: 500; suffix: " Hz"; decimals: 0
            onCommitted: function(value) { root.patch("cleanup", "low_pass_hz", Math.round(value)) }
        }
    }
}
