# Linux RVC Voice Changer

Linux RVC Voice Changer is a real-time voice conversion app for Linux with a
Plasma 6 panel widget. Choose a voice model, select your microphone, and send
the converted audio to any application through a persistent virtual
microphone.

## Features

- Real-time RVC voice conversion
- Plasma 6 panel widget
- NVIDIA CUDA, AMD ROCm, and CPU inference
- Automatic selection of the best available inference device
- Persistent **RVC Virtual Microphone** for Discord and other applications
- Microphone passthrough while conversion is disabled
- Independent microphone and application-audio translation
- Configurable KDE global shortcuts for each voice/translation pipeline
- Input and monitor-device selection
- Automatic voice-model discovery
- Pitch, index, protection, cleanup, gain, and latency controls
- Per-stage latency profiling and rolling logs
- Immediate setting changes with automatic saving

## Requirements

- Linux with PipeWire, WirePlumber, and PipeWire-Pulse (`pactl`)
- Plasma 6
- Python 3.11 or newer
- An NVIDIA or AMD GPU for accelerated inference, or a supported CPU

## Install

```bash
git clone https://github.com/DevL0rd/Linux-RVC-Voice-Changer.git
cd Linux-RVC-Voice-Changer
./install.sh
```

The installer creates an isolated Python environment, installs the appropriate
inference runtime, downloads the required model components, installs the Plasma
widget, and enables the user service. It does not require `sudo`.

After installation, add **RVC Voice Changer** from Plasma's **Add Widgets**
menu.

## Add voice models

Place each voice in its own subfolder inside `models/`:

```text
models/
├── Voice One/
│   ├── voice-one.pth
│   └── added_IVF.index
└── Voice Two/
    └── voice-two.pth
```

Each folder requires one `.pth` model. A matching `.index` file is optional.
Models are kept out of Git.

Use **Open folder** in the widget to open the correct location, then select
**Rescan** after adding or removing voices.

## Use with Discord

Select **RVC Virtual Microphone** as the input device in Discord. The same
device carries converted audio while the voice changer is on and your normal
microphone audio while it is off.

Plasma classifies software-only microphones as virtual devices. To manage the
RVC microphone from the Audio Volume tray applet, enable **Show virtual devices**.

## Live translation

Expand **Live translation** in the applet, choose a target language, and save a
Gemini API key before enabling translated output. Translation uses the
`gemini-3.5-live-translate-preview` model and therefore requires an internet
connection. With voice conversion enabled, translation runs after RVC; with
voice conversion disabled, it translates the original microphone directly.
Source language detection is automatic.

**Original voice volume** mixes the immediate microphone signal into the RVC
Virtual Microphone while Gemini's translated speech arrives later. At 0% only
translated speech is sent. With voice conversion enabled the immediate signal
is the RVC voice; otherwise it is the physical microphone.

Application translation can capture one currently running PipeWire playback
stream, translate it independently to English or another target language, and
play the translated speech through its own selected output device. The
application's original audio route is not changed, and microphone translation
can run at the same time using a separate Gemini Live session.

The applet's **Keyboard shortcuts** section controls three independent global
toggles. By default, microphone translation uses `Alt+T`; voice change and
application translation have no shortcut until one is assigned.

The API key is stored in the local user configuration with owner-only file
permissions and is not returned by the daemon's state endpoint. Live Translate
is a preview service; its output adds network latency and voice replication can
vary, especially after long pauses or with multiple speakers.

## Command line

```bash
rvc-voice-changer-ctl status
rvc-voice-changer-ctl rescan
rvc-voice-changer-ctl select "Voice One"
rvc-voice-changer-ctl on
rvc-voice-changer-ctl off
```

Service logs are available with:

```bash
journalctl --user -u linux-rvc-voice-changer.service -f
```

## Uninstall

```bash
./uninstall.sh
```

Uninstalling keeps downloaded voice models and saved settings.

## License

Linux RVC Voice Changer is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party notices.
