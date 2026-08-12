<p align="center">
  <img src="Resources/AppIcon.png" alt="TaskMgmtMac Icon" width="128" height="128">
</p>

<h1 align="center">TaskMgmtMac</h1>

<p align="center">
  <strong>A high-fidelity, native macOS Task Manager inspired by the classic Windows Task Manager experience.</strong>
  <br>
  <em>Written in Swift & SwiftUI using native Apple frameworks, low-level APIs, and real-time macOS system data.</em>
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square" alt="Swift 6.0"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14.0%2B-blue.svg?style=flat-square" alt="macOS 14+"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI-blueviolet.svg?style=flat-square" alt="SwiftUI"></a>
  <a href="https://github.com/xModern54/Task-Manager-MacOS/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License MIT"></a>
  <a href="#"><img src="https://img.shields.io/badge/Build-Passing-brightgreen.svg?style=flat-square" alt="Build Passing"></a>
</p>

---

## 📖 Overview

**TaskMgmtMac** is a lightweight, highly-optimized macOS system monitor that recreates the familiar shape, responsiveness, and features of the Windows Task Manager. 

Unlike typical monitors that rely on heavy Electron wrappers or basic shell commands, TaskMgmtMac communicates directly with the macOS kernel, Mach microkernel, Metal, and IOKit. It features a modern modular architecture, optimized actors for background calculations, and an optional least-privilege helper for privileged tasks.

---

## ✨ Features

### 🖥️ 1. Processes & Diagnostics
* **Live Process Table**: Lists all active processes with stable PID-based row identity, preventing SwiftUI diff lag.
* **Smart Grouping**: Automatically groups parent and auxiliary processes (e.g., Safari WebKit helper apps, Electron subprocesses).
* **Precise Metric Sorting**: Sort dynamically by CPU, Memory, and Disk activity.
* **Process Termination**: Safely send `SIGTERM` to single processes or entire process groups with name confirmation.
* **Run New Task**: Small command dialog running execution pipelines via `/bin/zsh -lc` with stdout/stderr capturing.
* **Smart Icon Cache**: Instantly retrieves and caches high-fidelity application icons via `NSRunningApplication` and `NSWorkspace`.

### 📈 2. Performance & Devices
* **CPU & Memory**: Real-time graphs showing historical utilization, active VM pages, compressed memory, and hardware specs.
* **Extended Sensors**: Collects die temperatures (via `IOHID` temperature readers) and system package power (E-core/P-core frequencies, package power in Watts via `powermetrics`).
* **GPU & NPU**: Real-time GPU usage from `IORegistry` performance counters, Apple Silicon Unified Memory telemetry, and Apple Silicon NPU (ANE) activity.
* **Network & Disk**: Deep packet metrics, interface speed, and MacBook internal SSD read/write monitoring.
* **Battery**: Live status and power source tracking (visible only when an internal battery is present).

### 🚀 3. Startup Management
* **Startup Apps**: Manage launch configurations through Background Task Management APIs, LaunchAgent plists, and `SystemEvents` login items.

---

## 🛠️ Tech Stack & Low-Level APIs

To ensure low CPU overhead (refreshing every `0.5s`), TaskMgmtMac accesses native macOS interfaces:

| Telemetry | Low-Level System API |
| :--- | :--- |
| **Process PIDs** | `proc_listpids` & `proc_pidinfo` |
| **CPU Time Tracking** | `proc_taskinfo` & `mach_timebase_info` |
| **System Memory** | Mach VM statistics (`host_statistics64`) |
| **GPU Telemetry** | Metal API & `IORegistryEntry` |
| **Thermal Sensors** | `IOHIDEventSystemClient` (pACC / eACC / PMU sensors) |
| **Power Telemetry** | `/usr/bin/powermetrics` (background CPU/GPU/ANE telemetry) |
| **App Icons** | `NSRunningApplication` & `NSWorkspace.icon(forFile:)` |

---

## 📐 Architecture

The codebase is organized in a modular, clean, and testable directory structure:

```text
Sources
├── PrivilegedHelperIPC # Shared, typed XPC contract
├── TaskMgmtMac
│   ├── Models          # Data representation models (system metrics, processes)
│   ├── Services        # Low-level providers, helper client & monitor actors
│   ├── ViewModels      # Main view models holding charts and snapshots
│   ├── Support         # Settings and theme configurators
│   └── Views           # Native SwiftUI views and reusable graph modules
└── TaskMgmtMacPrivilegedHelper # On-demand root launch daemon
```

---

## 🛡️ Privileged Helper & Security

Some system telemetry (like `powermetrics` and ending processes owned by other users) requires `root` privileges. 

TaskMgmtMac itself always runs as the logged-in user. Privileged features are optional and use a dedicated launch daemon:
* The helper is embedded in the app and registered with `SMAppService.daemon`.
* macOS owns installation approval and displays the helper in Login Items settings.
* The app communicates with the daemon through a typed XPC interface.
* The daemon accepts only the signed TaskMgmtMac client and exposes a fixed allowlist: power telemetry, `SIGTERM`, system launch-item control, and removal of the legacy sudoers rule.
* `Run new task` always remains in the normal user context and is never forwarded to the helper.

Production distributions containing the launch daemon must be Developer ID signed and notarized. The app remains usable when the helper is not installed; only privileged features are unavailable.

---

## 🚀 Building & Running

### Prerequisites
* macOS 14.0 or newer
* Xcode 15+ / Swift 6.0 Toolchain

### 1. Build the Binary
```bash
swift build -c release
```

### 2. Package and Install
You can use the provided development scripts for fast builds:
```bash
# Build a debug executable and launch the macOS app bundle wrapper
./Scripts/run-debug-app.sh
```

### 3. Run Release Bundle
The fully optimized release package is compiled and available at the root of the project:
```bash
open TaskMgmtMac.app
```

---

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
