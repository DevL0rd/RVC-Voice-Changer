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
- Input and monitor-device selection
- Automatic voice-model discovery
- Pitch, index, protection, cleanup, gain, and latency controls
- Per-stage latency profiling and rolling logs
- Immediate setting changes with automatic saving

## Requirements

- Linux with PipeWire and WirePlumber
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
