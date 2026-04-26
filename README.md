# TaskMgmtMac

![Swift](https://img.shields.io/badge/Swift-6-orange)
![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)
![Status](https://img.shields.io/badge/status-in%20progress-lightgrey)

TaskMgmtMac is a native macOS app inspired by the Windows Task Manager experience.
It keeps the familiar task-manager shape, but uses SwiftUI, native Apple frameworks,
and real macOS system data where practical.

The project is intentionally small, modular, and direct: system providers collect
metrics, view models keep live history, and SwiftUI views focus on presentation.

## Preview

The app currently recreates the core Windows Task Manager shell:

- custom title bar and search field
- compact sidebar with Processes and Devices
- process table with live CPU and memory data
- performance-style Devices page
- live CPU, memory, and GPU summary graphs

Design references live in [`Refs/`](./Refs/).

## Current Features

### Processes

- Real process list from native macOS process APIs
- Stable PID-based row identity for smooth SwiftUI updates
- Real resident memory per process
- Real sampled CPU usage per process
- Process icon lookup with caching
- Filtering by process name or PID
- Sorting by CPU, Memory, and Disk columns

### Devices / Performance

- Live CPU utilization history
- Live memory usage based on Mach VM statistics
- Live GPU utilization from IORegistry performance counters
- Real GPU name and unified-memory status through Metal
- Windows Task Manager inspired graph styling
- Mock placeholders for disk, network, and some device details

## Architecture

```text
Sources/TaskMgmtMac
├── Models
├── Services
│   ├── Mocks
│   ├── SystemProcesses
│   └── SystemResources
├── Support
├── ViewModels
└── Views
```

The code separates UI, models, providers, and support utilities so individual
metrics can be replaced or improved without turning the app into one large file.

## System Data

TaskMgmtMac uses native macOS APIs where possible:

- `proc_listpids`, `proc_pidinfo`, `PROC_PIDTASKINFO`, and `proc_pidpath` for process data
- Mach VM statistics for system memory
- Mach absolute time conversion for process CPU sampling
- `NSRunningApplication` and `NSWorkspace` for process icons
- Metal for GPU identity
- IORegistry performance counters for live GPU utilization

GPU utilization is currently best-effort because Apple does not expose a complete
public Task Manager style GPU API for all live counters.

## Requirements

- macOS 14 or newer
- Swift toolchain with Swift Package Manager

## Build

```bash
swift build
```

## Run

For local development, use the debug app wrapper:

```bash
./Scripts/run-debug-app.sh
```

The script builds the Swift package, wraps the executable in a temporary `.app`,
closes the previous debug instance, and opens the new one.

## Development Workflow

Commit and push the current work with:

```bash
./Scripts/commit-and-push.sh "Short commit message"
```

The script stages changed files, creates a commit, waits briefly, and pushes the
current branch to the configured remote.

## Roadmap

- Real disk activity provider
- Real network activity provider
- More complete GPU memory reporting where available
- Better device-specific Performance page details
- Command bar actions such as Run new task and End task
- More Windows Task Manager sections when the core pages are solid

## Notes

This is not an Xcode project yet. It is a Swift Package executable, which keeps
the build simple while the interface and providers are being recreated.
