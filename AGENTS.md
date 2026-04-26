# TaskMgmtMac Project Context

TaskMgmtMac is a native macOS application that visually and functionally follows the Windows Task Manager experience.

The app is written in Swift using SwiftUI and native Apple frameworks. The current package is a Swift Package executable, not an Xcode project.

The project should keep a modular architecture. UI components, system data providers, models, and support utilities should stay separated instead of growing into one large file.

The main window is intentionally fixed-size for now. Resize behavior is disabled or constrained while the UI is being recreated.

The UI currently has a Windows Task Manager inspired shell: custom title bar, sidebar, process table, performance/devices page, and a basic settings page.

The sidebar is currently reduced to Processes, Devices, and Settings. Other Task Manager sections are intentionally not implemented yet.

Settings is shown as a gear item pinned near the bottom of the sidebar.

The sidebar expansion behavior is temporarily disabled. The code path can remain, but the UI should not currently expand to show text labels.

The app has a root launch gate. On normal user launch, `RootLaunchGate` checks whether a local sudoers rule exists and can relaunch the exact current app executable as root without storing an administrator password.

The root launch rule is installed at `/etc/sudoers.d/taskmgmtmac-root-launch` and must only allow the exact TaskMgmtMac executable path with `NOPASSWD`. Do not broaden this into a generic root command wrapper or shell backdoor.

`RootLaunchManager` owns root probing, sudoers installation, and root relaunch. Keep privileged launch behavior centralized there.

The app may run as root after the launch gate succeeds. Code should still avoid mutating system settings unless the current task explicitly asks for it.

The Processes page uses real process data where available. The mock process list has been moved to a mock service and should only be used as a fallback or for isolated development.

Process data is collected through native macOS APIs. The current implementation uses `proc_listpids`, `proc_pidinfo`, `PROC_PIDTASKINFO`, and `proc_pidpath`.

Per-process memory is currently real and is based on resident memory from `proc_taskinfo.pti_resident_size`.

The top-level system memory percentage is real and is calculated through Mach VM statistics using `host_statistics64`.

The memory percentage should not count inactive memory as fully used because macOS often treats inactive pages as reusable cache.

The current system memory formula uses active, wired, and compressed pages against total physical memory.

Per-process CPU is real and sampled over time. It is calculated from deltas of accumulated CPU time between refresh ticks.

CPU time from `proc_taskinfo.pti_total_user + pti_total_system` must be converted from Mach absolute ticks into nanoseconds using `mach_timebase_info`.

`ProcessMonitor` is an actor because CPU sampling requires state between refreshes.

The app refreshes process and summary data every 0.5 seconds by default.

The process table uses stable process IDs as row identities. This is important so SwiftUI can diff rows when processes appear, disappear, or update.

The process table supports sorting by CPU, Memory, and Disk. Clicking a metric header switches to descending sort for that column; clicking it again toggles ascending/descending.

Disk and network per-process metrics are not real yet. They should be added later through separate provider modules.

Process row selection should highlight the full table row, including metric columns, using a soft Windows Task Manager style selection. Avoid filling large table rows with a fully opaque system accent color.

The Processes command bar has working actions. `Run new task` opens a small command dialog that runs commands through `/bin/zsh -lc`, captures stdout/stderr, and shows the exit code. `End task` is enabled only when a process is selected, confirms with the process name, and sends `SIGTERM` to the selected PID.

Real process icons are shown when possible. Icon lookup uses `NSRunningApplication` first, then `NSWorkspace.icon(forFile:)`, and then the standard Unix executable icon as fallback.

Icon lookup is cached so the 0.5 second refresh loop does not repeatedly ask macOS for the same images.

The Devices page visually follows the Windows Task Manager Performance tab and is gradually wired to real macOS providers.

The Devices page currently includes CPU, Memory, Disk 0, Wi-Fi/Network, GPU 0, Battery when present, and NPU 0.

Performance mini-graphs and detail graphs should be backed by live samples where providers exist. Keep the graph component reusable; it handles grid drawing, line drawing, and optional filled area rendering.

The performance device order should stay: CPU, Memory, Disk, Wi-Fi, GPU, Battery, NPU.

The Devices page uses a performance-conscious collection model. While Devices is open, collect lightweight data needed for the sidebar rows and mini-graphs. Collect heavier detailed data only for the currently selected performance device.

CPU and Memory mini-graphs should continue updating while the Devices page is open, even when another performance device is selected.

Disk currently tracks only the primary MacBook SSD. Do not reintroduce mock secondary disk devices.

Network details come from SystemConfiguration and interface counters. Per-process network is still not implemented.

GPU identity comes from Metal/IOKit where available, and GPU utilization is best-effort from IORegistry performance counters. Apple does not expose a complete public Task Manager style GPU API for all counters.

NPU details are best-effort through CoreML and IORegistry. The NPU page should be kept explicit about unavailable utilization when macOS does not expose it.

Battery details come from IOKit power source and AppleSmartBattery data. Show the Battery device only when an internal battery is present.

CPU extended sensors are collected only when the CPU performance device is selected. Frequency, thermal pressure, and SoC/package power come from `powermetrics`; CPU die temperature comes from IOHID temperature sensors.

`PowermetricsSystemCPUSensorProvider` runs `/usr/bin/powermetrics` with `cpu_power,gpu_power,ane_power,thermal` samplers and parses CPU/E-core/P-core frequency, thermal pressure, CPU power, GPU power, ANE power, and combined package power.

`IOHIDSystemCPUTemperatureReader` reads HID temperature services directly. Prefer `pACC`/`eACC` sensors when present; otherwise fall back to plausible `PMU tdie*` sensors and ignore calibration sensors such as `tcal`.

Do not call `powermetrics` unless CPU detail data is actually needed. It is comparatively expensive and should stay behind the selected CPU device path.

The app supports macOS light and dark mode through dynamic theme colors.

Accent color should follow the macOS system accent color via `NSColor.controlAccentColor`.

Avoid hard-coded dark-only UI colors unless they are deliberate semantic colors for graph series or icons.

The visual target is Windows Task Manager, but the implementation should remain native macOS SwiftUI.

The title bar search field is visual only for filtering processes right now. It filters by process name and PID.

The search field should not automatically focus when the app opens.

The command bars may include both wired and visual-only actions. Do not imply a command works unless it is actually connected.

Do not add unimplemented large features unless the current task explicitly asks for them.

Prefer small modules and provider protocols for system data collection.

Keep process, memory, CPU, disk, network, GPU, and icon logic separate enough that each can be replaced or improved independently.

Be careful with Swift concurrency. System collection should not block the main actor.

Use actors or explicit state objects when sampling logic needs previous values.

Do not rely on private macOS APIs unless the user explicitly accepts that tradeoff.

Network per-process and GPU per-process metrics are expected to be harder than CPU and memory.

The repo uses `Scripts/run-debug-app.sh` to build a debug executable, wrap it in a `.app`, kill the previous app instance, and open the new app.

The debug app wrapper is created under `.build/debug/TaskMgmtMac.app`.

Because the app may be running as root, restart scripts should first ask the app to quit through Apple Events and then fall back to killing remaining `TaskMgmtMac` processes.

The repo uses `Scripts/finish-task.sh` at the end of each completed task to run a quiet build, restart the debug app, stage changed files, create a commit, wait briefly, and push to the configured remote repository.

`Scripts/commit-and-push.sh` exists for git-only sync, but normal completed code tasks should use `Scripts/finish-task.sh` so the app is rebuilt and relaunched too.

Use `swift build` for quick compile checks.

Use `./Scripts/run-debug-app.sh` when the user asks to run the app or when visual verification is needed.

Use `./Scripts/finish-task.sh "Short commit message"` after completed code or documentation tasks unless the user explicitly asks not to build/restart/commit.

The project now has a git repository.

After completing every user task, always create a git commit.

Commit messages should be short and describe the completed task.

At the end of every completed user task, run `./Scripts/finish-task.sh "Short commit message"` so the app is recompiled, the old app process is stopped, the new app is launched, and the finished work is committed and pushed. If this script reports a build, launch, commit, or push error, surface the relevant log output to the user.

Do not commit `.build`, `.DS_Store`, DerivedData, or other local generated files.

Before committing, check `git status --short`.

If generated or unrelated files appear, ignore them unless they are part of the task.

If the worktree contains user changes unrelated to the current task, do not revert them.

When editing, keep the design consistent with the existing Windows Task Manager inspired layout.

When adding new UI, prefer real controls and reusable components instead of static screenshots.
