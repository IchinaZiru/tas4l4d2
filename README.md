# TAS4L4D2

Toolset and plugins for Tool-Assisted Speedruns (TAS) in **Left 4 Dead 2**.

## Features (planned)
- Distance HUD (`tas_distance_hud.sp`)
- Replay Bridge for Movement Reader
- Setup Assistant (quick give/idle/bot/cfg)

## Requirements
- SourceMod 1.11+ (recommended 1.12)
- Left 4 DHooks Direct (latest)
- (Optional) Movement Reader, Speedrunner Tools, TAS-Kit (VScript)

## Directory
- `plugins/` : SourceMod plugin source files (.sp) and builds (.smx)
- `cfg/tas4l4d2/` : plugin configuration per map
- `data/movements/` : record/replay data examples
- `docs/` : documentation and AlliedModders release notes

## Integrations / Related Projects
- **Movement Reader** — Record/Replay engine used for TAS input sequences.  
  *tas4l4d2* can consume MR-format data (e.g., `run3.txt`, `gl3.txt`, `bile3.txt`) via the Replay Bridge module. Recommended when you need deterministic reproduction and frame stepping.
- **Speedrunner Tools** — QoL utilities for speedrun setup (ammo/idle/fake bot/strip/give/etc.).  
  Useful during testing; some helper commands in *tas4l4d2* assume these tools are present.
- **TAS-Kit (VScript)** — HUD/timer/debug utilities implemented in Squirrel.  
  *tas4l4d2* aims to expose simple hooks/forwards so TAS-Kit can render or control HUD elements driven by plugin events.
- **Left 4 DHooks Direct** — Native extension layer that unlocks many L4D2 internals.  
  Required by advanced features and recommended as the standard base extension.
- **Left4TAS (native plugin)** — Standalone TAS core (C++).  
  If you use Left4TAS, avoid overlapping control features with *tas4l4d2* in the same session (choose one approach per run).
- **Console Cmd As Host / Dev Cmds / SMLib** — Optional developer helpers; handy on listen servers or when issuing host-only commands.

> **Note**: Dependencies are not bundled. Please follow each project's license and installation guide.

## License
MIT License
