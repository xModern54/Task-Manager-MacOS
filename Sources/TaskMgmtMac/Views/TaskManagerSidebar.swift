import SwiftUI

struct TaskManagerSidebar: View {
    @Binding var selection: TaskManagerSection
    let isExpanded: Bool

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            ForEach([TaskManagerSection.processes, .devices, .startupApps]) { section in
                SidebarRow(
                    section: section,
                    isSelected: selection == section,
                    isExpanded: isExpanded,
                    selectionNamespace: selectionNamespace
                )
                .onTapGesture {
                    withAnimation(.interpolatingSpring(stiffness: 320, damping: 30)) {
                        selection = section
                    }
                }
            }

            Spacer()

            SidebarRow(
                section: .settings,
                isSelected: selection == .settings,
                isExpanded: isExpanded,
                selectionNamespace: selectionNamespace
            )
            .onTapGesture {
                withAnimation(.interpolatingSpring(stiffness: 320, damping: 30)) {
                    selection = .settings
                }
            }
        }
        .padding(.top, 44)
        .padding(.bottom, 10)
        .padding(.horizontal, isExpanded ? 6 : 4)
        .frame(width: isExpanded ? 300 : 52)
        .background(WindowsTaskManagerTheme.sidebar)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }
}

private struct SidebarRow: View {
    let section: TaskManagerSection
    let isSelected: Bool
    let isExpanded: Bool
    let selectionNamespace: Namespace.ID
    @EnvironmentObject private var settings: TaskManagerSettings

    var body: some View {
        HStack(spacing: isExpanded ? 18 : 0) {
            ZStack(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(settings.effectiveAccentColor)
                        .frame(width: 4, height: 22)
                        .offset(x: isExpanded ? -10 : -8)
                        .matchedGeometryEffect(id: "sidebar-selection-indicator", in: selectionNamespace)
                }

                Image(systemName: section.iconSystemName)
                    .taskManagerFont(18)
                    .frame(width: 22)
                    .scaleEffect(isSelected ? 1.04 : 1)
            }

            if isExpanded {
                Text(section.rawValue)
                    .taskManagerFont(16)

                Spacer()
            }
        }
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
        .padding(.horizontal, isExpanded ? 18 : 11)
        .frame(height: 46)
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WindowsTaskManagerTheme.sidebarSelection)
                    .matchedGeometryEffect(id: "sidebar-selection-background", in: selectionNamespace)
            }
        }
        .contentShape(Rectangle())
        .help(section.rawValue)
    }
}
