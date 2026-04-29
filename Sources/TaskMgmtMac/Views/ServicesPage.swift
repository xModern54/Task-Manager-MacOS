@preconcurrency import AppKit
import SwiftUI

struct ServicesPage: View {
    @ObservedObject var viewModel: TaskManagerViewModel
    @EnvironmentObject private var settings: TaskManagerSettings
    @State private var services: [LaunchServiceItem] = []
    @State private var selectedServiceID: LaunchServiceItem.ID?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            ServicesCommandBar(serviceCount: services.count)

            GeometryReader { geometry in
                let detailWidth = max(270, geometry.size.width * 0.30)

                HStack(spacing: 0) {
                    ServicesTable(
                        services: services,
                        isLoading: isLoading,
                        selectedServiceID: selectedServiceID,
                        selectionColor: settings.effectiveAccentColor,
                        onSelect: { service in
                            selectedServiceID = service.id
                        },
                        onOpenProcess: { service in
                            guard let pid = service.pid else { return }
                            selectedServiceID = service.id
                            viewModel.focusProcess(Int(pid))
                        },
                        onCopyInfo: { service in
                            copyInfo(for: service)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(WindowsTaskManagerTheme.separator)
                        .frame(width: 1)

                    ServiceDetailsPane(service: selectedService)
                        .frame(width: detailWidth)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(WindowsTaskManagerTheme.content)
        .task {
            await loadServices()
        }
    }

    private var selectedService: LaunchServiceItem? {
        guard let selectedServiceID else { return services.first }
        return services.first { $0.id == selectedServiceID }
    }

    private func loadServices() async {
        isLoading = true
        let loadedServices = await LaunchctlServiceProvider().services()
        services = loadedServices

        if let selectedServiceID, !loadedServices.contains(where: { $0.id == selectedServiceID }) {
            self.selectedServiceID = nil
        }

        if selectedServiceID == nil {
            selectedServiceID = loadedServices.first?.id
        }

        isLoading = false
    }

    private func copyInfo(for service: LaunchServiceItem) {
        selectedServiceID = service.id

        let text = LaunchServiceClipboardInfoBuilder.text(
            for: service,
            processRow: processRow(for: service)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func processRow(for service: LaunchServiceItem) -> ProcessTableRow? {
        guard let pid = service.pid else {
            return nil
        }

        let processID = Int(pid)
        let metric = viewModel.snapshot.processes.first { $0.pid == processID } ?? fallbackProcessMetric(
            for: service,
            pid: processID
        )

        return ProcessTableRow(
            id: "process-\(processID)",
            kind: .process,
            metric: metric,
            children: [],
            isExpanded: false
        )
    }

    private func fallbackProcessMetric(for service: LaunchServiceItem, pid: Int) -> ProcessMetric {
        let processName = service.executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? service.label

        return ProcessMetric(
            name: processName,
            iconSystemName: "terminal",
            executablePath: service.executablePath,
            group: .backgroundProcesses,
            cpu: 0,
            memoryMB: 0,
            diskMBs: 0,
            networkMbps: 0,
            powerUsage: .veryLow,
            gpu: 0,
            pid: pid
        )
    }
}

private struct ServicesCommandBar: View {
    let serviceCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Text("Services")
                .taskManagerFont(16, weight: .semibold)
                .padding(.leading, 22)

            Text("\(serviceCount) items")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .padding(.leading, 12)

            Spacer()

            Image(systemName: "ellipsis")
                .taskManagerFont(18, weight: .bold)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .frame(width: 48, height: 50)
        }
        .frame(height: 61)
        .background(WindowsTaskManagerTheme.content)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct ServicesTable: View {
    let services: [LaunchServiceItem]
    let isLoading: Bool
    let selectedServiceID: LaunchServiceItem.ID?
    let selectionColor: Color
    let onSelect: (LaunchServiceItem) -> Void
    let onOpenProcess: (LaunchServiceItem) -> Void
    let onCopyInfo: (LaunchServiceItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ServicesTableHeader()

            if isLoading {
                ServicesLoadingView()
            } else if services.isEmpty {
                ServicesEmptyView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(services) { service in
                            ServiceRow(
                                service: service,
                                isSelected: service.id == selectedServiceID,
                                selectionColor: selectionColor
                            )
                            .onTapGesture {
                                onSelect(service)
                            }
                            .onTapGesture(count: 2) {
                                onOpenProcess(service)
                            }
                            .contextMenu {
                                Button("Copy info") {
                                    onCopyInfo(service)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(WindowsTaskManagerTheme.table)
    }
}

private struct ServicesLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Loading launchd services")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ServicesEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "switch.2")
                .taskManagerFont(28)
                .foregroundStyle(WindowsTaskManagerTheme.textMuted)

            Text("No services found")
                .taskManagerFont(15, weight: .semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ServicesTableHeader: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                ServiceHeaderCell(title: "Name", width: width * 0.50)
                ServiceHeaderCell(title: "PID", width: width * 0.12)
                ServiceHeaderCell(title: "Status", width: width * 0.18)
                ServiceHeaderCell(title: "Trigger", width: width * 0.20, showsSeparator: false)
            }
        }
        .frame(height: 58)
        .background(WindowsTaskManagerTheme.table)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct ServiceRow: View {
    let service: LaunchServiceItem
    let isSelected: Bool
    let selectionColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                ServiceNameCell(service: service, width: width * 0.50)
                ServiceTextCell(text: pidText, width: width * 0.12)
                ServiceStatusCell(status: service.status, width: width * 0.18)
                ServiceTextCell(text: service.trigger, width: width * 0.20, showsSeparator: false)
            }
        }
        .frame(height: 46)
        .background(isSelected ? selectionColor.opacity(0.18) : WindowsTaskManagerTheme.table)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }

    private var pidText: String {
        service.pid.map(String.init) ?? "-"
    }
}

private struct ServiceNameCell: View {
    let service: LaunchServiceItem
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.label)
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(service.domain)
                .taskManagerFont(11)
                .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.leading, 16)
        .frame(width: width, height: 46, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            ServiceCellSeparator(height: 30)
        }
    }
}

private struct ServiceStatusCell: View {
    let status: LaunchServiceStatus
    let width: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(status.rawValue)
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.leading, 16)
        .frame(width: width, height: 46, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            ServiceCellSeparator(height: 30)
        }
    }

    private var statusColor: Color {
        switch status {
        case .running:
            Color(red: 0.18, green: 0.64, blue: 0.34)
        case .waiting:
            Color(red: 0.95, green: 0.52, blue: 0.12)
        case .offline:
            WindowsTaskManagerTheme.textMuted
        case .disabled:
            Color(red: 0.93, green: 0.20, blue: 0.22)
        case .unknown:
            WindowsTaskManagerTheme.textSecondary
        }
    }
}

private struct ServiceTextCell: View {
    let text: String
    let width: CGFloat
    var showsSeparator = true

    var body: some View {
        Text(text)
            .taskManagerFont(13)
            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 16)
            .frame(width: width, height: 46, alignment: .leading)
            .clipped()
            .overlay(alignment: .trailing) {
                if showsSeparator {
                    ServiceCellSeparator(height: 30)
                }
            }
    }
}

private struct ServiceHeaderCell: View {
    let title: String
    let width: CGFloat
    var showsSeparator = true

    var body: some View {
        Text(title)
            .taskManagerFont(13)
            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            .lineLimit(1)
            .padding(.leading, 16)
            .frame(width: width, height: 58, alignment: .leading)
            .overlay(alignment: .trailing) {
                if showsSeparator {
                    ServiceCellSeparator(height: 36)
                }
            }
    }
}

private struct ServiceDetailsPane: View {
    let service: LaunchServiceItem?

    var body: some View {
        VStack(spacing: 0) {
            if let service {
                ServiceDetailsHeader(service: service)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(service.properties) { property in
                            ServicePropertyRow(name: property.name, value: property.value)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Text("Select a service")
                    .taskManagerFont(13)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowsTaskManagerTheme.content)
    }
}

private struct ServiceDetailsHeader: View {
    let service: LaunchServiceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(service.status.rawValue)
                    .taskManagerFont(12, weight: .medium)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            }

            Text(service.label)
                .taskManagerFont(16, weight: .semibold)
                .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(service.executablePath ?? service.plistPath ?? service.domain)
                .taskManagerFont(11)
                .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(WindowsTaskManagerTheme.content)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }

    private var statusColor: Color {
        switch service.status {
        case .running:
            Color(red: 0.18, green: 0.64, blue: 0.34)
        case .waiting:
            Color(red: 0.95, green: 0.52, blue: 0.12)
        case .offline:
            WindowsTaskManagerTheme.textMuted
        case .disabled:
            Color(red: 0.93, green: 0.20, blue: 0.22)
        case .unknown:
            WindowsTaskManagerTheme.textSecondary
        }
    }
}

private struct ServicePropertyRow: View {
    let name: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .taskManagerFont(11, weight: .medium)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            Text(value)
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                .lineLimit(5)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
                .padding(.leading, 18)
        }
    }
}

private struct ServiceCellSeparator: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(WindowsTaskManagerTheme.separator)
            .frame(width: 1, height: height)
    }
}
