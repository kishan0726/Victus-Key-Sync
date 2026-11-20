# VictusKeySync

**Music-reactive RGB keyboard lighting for HP Victus laptops on Linux.**

VictusKeySync is a Linux-based keyboard lighting application that synchronizes HP Victus RGB keyboard effects with system audio. It provides dynamic lighting effects that respond to music playback.

## Features

- Music-reactive RGB keyboard lighting
- Real-time system audio detection using PipeWire
- Dynamic colour effects
- Full-keyboard synchronized lighting
- Wired and Bluetooth audio device support
- Custom HP WMI keyboard LED control
- Desktop GUI for controlling lighting
- Linux and Hyprland integration

## Tech Stack

- Python
- C++
- Qt
- PipeWire
- Linux Kernel / HP WMI
- Fedora Linux

## Requirements

- HP Victus laptop with compatible RGB keyboard hardware
- Fedora Linux
- PipeWire audio system
- Required project build dependencies

## Installation & Usage

Clone the repository:

```bash
https://github.com/kishan0726/Victus-Key-Sync.git
cd Victus-Key-Sync
```

### 1. Build the project

```bash
./scripts/build.sh
```

### 2. Run the project

```bash
./scripts/run_dev.sh
```

The project can be built and launched using these two scripts from the project root directory.

If necessary, make the scripts executable:

```bash
chmod +x scripts/build.sh scripts/run_dev.sh
```

## How It Works

1. PipeWire captures system audio.
2. Audio processing detects changes in the music.
3. The lighting engine determines the keyboard colour.
4. The HP WMI LED interface applies the lighting effect.
5. The keyboard synchronizes its colours with the audio.

## Compatibility

| Component | Support |
|---|---|
| Laptop | HP Victus series |
| Operating System | Fedora Linux |
| Desktop Environment | Hyprland |
| Audio System | PipeWire |
| Keyboard | Compatible RGB keyboards |

Hardware compatibility may vary between laptop models.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
