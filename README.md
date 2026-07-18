# Linux RVC Voice Changer

A native Linux RVC voice changer controlled from a Plasma 6 panel
applet. It is deliberately smaller than Applio: one local daemon, one model
folder, one virtual microphone, and no browser UI or training stack.

## Features

- Plasma 6 dropdown with voice selection and on/off control
- Input, output, and optional monitor-device routing
- Pitch, F0 method, speaker ID, index rate, protection, RMS mix, and filter settings
- Block, crossfade, context, sample-rate, and gain settings
- VAD, noise suppression, gate, high-pass, and low-pass cleanup settings
- Rolling per-stage CPU, CUDA/ROCm, audio-processing, and PipeWire latency profiling
- Bounded in-memory rolling logs with one-click clipboard copying
- Immediate setting application with atomic persistence across daemon restarts
- Confirmed factory reset from the bottom of the Plasma applet
- Model discovery from one subfolder per voice (`.pth` plus optional `.index`)
- A localhost JSON control API and command-line controller
- A systemd user service with install/uninstall scripts
- An owned PipeWire input named **RVC Virtual Microphone**
- Stable bypass mode that passes the physical microphone through when RVC is off
- Automatic NVIDIA CUDA, AMD ROCm, or CPU inference with a live manual override
- Moderate CPU scheduling priority without restricting the scheduler's core choices
- Live RVC v1/v2 conversion using Applio's ContentVec and
  RMVPE/FCPE/CREPE inference implementation
- Native PipeWire capture/playback without PortAudio device-name translation

## Voice folders

```text
models/
├── Voice One/
│   ├── voice-one.pth
│   └── added_IVF.index
└── Voice Two/
    └── voice-two.pth
```

Only the first `.pth` and `.index` in each immediate subfolder are selected.
The index is optional. Models are ignored by Git.

## Install

Requirements are Plasma 6, PipeWire/WirePlumber, and Python 3.11 or newer. The
installer creates an isolated Python environment, detects working NVIDIA CUDA,
an AMD GPU for ROCm, or CPU-only operation, installs the matching PyTorch build,
and downloads the required ContentVec and pitch-extractor weights. If an
auto-detected AMD GPU cannot initialize through ROCm, installation safely
replaces that build with CPU-only PyTorch. It does not use `sudo` or mutate
system packages.

```bash
git clone https://github.com/DevL0rd/Linux-RVC-Voice-Changer.git
cd Linux-RVC-Voice-Changer
./install.sh
```

Detection can be overridden with `RVC_TORCH_BACKEND=cpu`, `cuda`, or `rocm`.
For an unusual accelerator build, set `RVC_TORCH_INDEX_URL` to its official
PyTorch-compatible wheel index. Auto inference prefers any accelerator visible
to PyTorch and otherwise uses CPU; the applet can switch to CPU temporarily to
free the GPU for a game.

The installed user service uses normal (non-realtime) scheduling with
`CPUWeight=250`. It deliberately leaves CPU affinity unrestricted: the kernel
may schedule light GPU-dispatch work on performance cores while CPU inference
can still use the whole machine. This gives the service a moderate share under
contention without allowing inference to preempt PipeWire's genuine realtime
audio threads.

Then right-click the Plasma panel, choose **Add Widgets**, search for **RVC
Voice Changer**, and add it to the panel.

Useful commands:

```bash
rvc-voice-changer-ctl status
rvc-voice-changer-ctl rescan
rvc-voice-changer-ctl select "Voice One"
rvc-voice-changer-ctl on
rvc-voice-changer-ctl off
journalctl --user -u linux-rvc-voice-changer.service -f
```

Discord should always use **RVC Virtual Microphone** as its input. While
conversion is enabled it carries the converted voice; while conversion is off
it carries the selected physical microphone unchanged. The node remains stable
across On/Off changes and is removed only when the daemon exits.

## Uninstall

```bash
./uninstall.sh
```

Uninstalling keeps the repository, voice models, and local configuration.

## Control API

The daemon binds only to `127.0.0.1:17843`:

- `GET /v1/state`
- `GET /v1/health`
- `GET /v1/logs?after=0`
- `PATCH /v1/config`
- `POST /v1/enabled`
- `POST /v1/models/rescan`
- `POST /v1/config/reset`

Settings are saved atomically to
`~/.config/Linux-RVC-Voice-Changer/config.json` after each change and loaded when
the daemon starts. Live tuning values take effect on the next audio block;
device, model, cleanup, latency, and inference-backend changes rebuild the
running pipeline when required. Factory reset stops conversion and restores the
shipped configuration without deleting voice models; the persistent virtual
microphone remains silent until a physical input is selected. Profiling and log
views poll the daemon only while their applet sections are visible.
