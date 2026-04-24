# TaskMgmtMac Project Context

TaskMgmtMac is a native macOS application that visually and functionally follows the Windows Task Manager experience.

The app is written in Swift using SwiftUI and native Apple frameworks. The current package is a Swift Package executable, not an Xcode project.

The project should keep a modular architecture. UI components, system data providers, models, and support utilities should stay separated instead of growing into one large file.

The main window is intentionally fixed-size for now. Resize behavior is disabled or constrained while the UI is being recreated.

The UI currently has a Windows Task Manager inspired shell: custom title bar, sidebar, process table, and a performance/devices page.

The sidebar is currently reduced to two sections only: Processes and Devices. Other Task Manager sections are intentionally not implemented yet.

The sidebar expansion behavior is temporarily disabled. The code path can remain, but the UI should not currently expand to show text labels.

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

Disk and network process metrics are not real yet. They should be added later through separate provider modules.

Real process icons are shown when possible. Icon lookup uses `NSRunningApplication` first, then `NSWorkspace.icon(forFile:)`, and then the standard Unix executable icon as fallback.

Icon lookup is cached so the 0.5 second refresh loop does not repeatedly ask macOS for the same images.

The Devices page is currently a mock Performance page. It visually follows the Windows Task Manager Performance tab.

The Devices page includes mock entries for CPU, Memory, multiple disks, Ethernet, and GPU.

Performance graphs are currently static mock samples. They should later be connected to real providers one device type at a time.

The performance graph component should stay reusable. It handles grid drawing, line drawing, and optional filled area rendering.

The app supports macOS light and dark mode through dynamic theme colors.

Accent color should follow the macOS system accent color via `NSColor.controlAccentColor`.

Avoid hard-coded dark-only UI colors unless they are deliberate semantic colors for graph series or icons.

The visual target is Windows Task Manager, but the implementation should remain native macOS SwiftUI.

The title bar search field is visual only for filtering processes right now. It filters by process name and PID.

The search field should not automatically focus when the app opens.

The command bars currently include visual actions such as Run new task and End task, but most command functionality is not wired yet.

Do not add unimplemented large features unless the current task explicitly asks for them.

Prefer small modules and provider protocols for system data collection.

Keep process, memory, CPU, disk, network, GPU, and icon logic separate enough that each can be replaced or improved independently.

Be careful with Swift concurrency. System collection should not block the main actor.

Use actors or explicit state objects when sampling logic needs previous values.

Do not rely on private macOS APIs unless the user explicitly accepts that tradeoff.

Network per-process and GPU per-process metrics are expected to be harder than CPU and memory.

The repo uses `Scripts/run-debug-app.sh` to build a debug executable, wrap it in a `.app`, kill the previous app instance, and open the new app.

Use `swift build` for quick compile checks.

Use `./Scripts/run-debug-app.sh` when the user asks to run the app or when visual verification is needed.

The project now has a git repository.

After completing every user task, always create a git commit.

Commit messages should be short and describe the completed task.

Do not commit `.build`, `.DS_Store`, DerivedData, or other local generated files.

Before committing, check `git status --short`.

If generated or unrelated files appear, ignore them unless they are part of the task.

If the worktree contains user changes unrelated to the current task, do not revert them.

When editing, keep the design consistent with the existing Windows Task Manager inspired layout.

When adding new UI, prefer real controls and reusable components instead of static screenshots.
