<img width="2727" height="978" alt="KinemiumFull" src="https://github.com/user-attachments/assets/1792beb7-d877-453d-ab3f-2d86cd434239" />

[<img width="50" height="50" alt="image" src="https://github.com/user-attachments/assets/83c3a863-d290-487f-b073-fed9caa6832f" />
](https://discord.gg/7byuxfYtAP)

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Qquaded/Kinemium-Engine)
## Introduction
Kinemium Engine is a performant game engine written in Odin with Luau scripting, a native editor, modern rendering, custom engine APIs, and support for building standalone multiplayer (or singleplayer) games.

## Getting Started
`NOTE: This repository is unstable, Expect bugs!`

You can download the engine using the [github artifacts](https://github.com/quadigen/canary-recode/actions), Simply download one of the ready artifacts (based on your OS) and run the executable.

## Previews
<img width="1535" height="813" alt="image" src="https://github.com/user-attachments/assets/11400841-a857-47c5-9ad5-9fa6e7884a3e" />
<img width="1535" height="813" alt="image" src="https://github.com/user-attachments/assets/39a27297-53cf-4523-a884-4575ada276b9" />
<img width="1535" height="813" alt="image" src="https://github.com/user-attachments/assets/bc714241-2260-4d7e-949e-04cb8581a581" />

## Compiling from source
### Prerequisites  
- [Odin compiler](https://odin-lang.org/) (latest release)  
- CMake + Ninja  
- A C/C++ toolchain (clang recommended on Linux/macOS, MSVC on Windows)  
- Vulkan SDK (1.4.304.1 or compatible)
- [Just](https://github.com/casey/just)
- Platform dev libraries (Linux: X11/Wayland/GTK/WebKit dev packages; macOS: `enet` via Homebrew)  
  
### 1. Clone with submodules  
```bash  
git clone --recurse-submodules https://github.com/quadigen/canary-recode.git
```

### 2. Build dependencies
```bash
just deps
```

### 3. Run Engine
```bash
just run
```

## Compilation flags
```bash
just client # Build a client
just server # Build a client
just editor # Build a editor
just build # Build the engine normally (editor included)
```

## Engine flags
```bash
./kinemium --client --port PORT --address ADDRESS --username USERNAME
./kinemium --server --port PORT --address ADDRESS --map MAP.KINE --window
./kinemium --editor
```
All of these flags are optional.

## GPU selection
The engine renders with Vulkan and picks a discrete GPU automatically when one is
available. On hybrid laptops (for example Intel + NVIDIA Optimus), it presents
frames through the display GPU while rendering on the discrete one.

To force a specific Vulkan device, set one of these environment variables:

```bash
KINE_VULKAN_GPU=NVIDIA   # substring of the Vulkan device name
KINE_VULKAN_GPU_INDEX=0  # index from vkEnumeratePhysicalDevices
```

`KINE_GPU` and `KINE_GPU_INDEX` are accepted as aliases. If no device matches,
the engine falls back to the automatic discrete-GPU preference. If the discrete
GPU is render-only, frames are still copied to the display GPU for presentation,
so expect some overhead compared with a display-attached GPU.

Presentation defaults to FIFO (vsync), which caps the frame rate to the display
refresh rate and prevents tearing. To change it, set `KINE_VULKAN_PRESENT`:

```bash
KINE_VULKAN_PRESENT=fifo       # vsync; also accepts "vsync" or "on"
KINE_VULKAN_PRESENT=mailbox    # triple buffering; also accepts "triple"
KINE_VULKAN_PRESENT=immediate  # no vsync/tearing; also accepts "off" or "nosync"
```

`mailbox` is not available on every driver; if it is unsupported the engine logs
a warning and falls back to FIFO. `immediate` can exceed the display refresh rate
but may tear.

## Notice
Kinemium is an independent project not affiliated with, endorsed by, or connected to Roblox Corporation. Roblox is a trademark of Roblox Corporation

API features such as Instances, data types and services are implemented solely for developer familiarity, platform portability, and software interoperability under applicable fair use law including but not limited to the Copyright Act of 1976, 17 U.S.C. § 107.