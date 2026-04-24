import SwiftUI

struct TaskManagerSidebar: View {
    @Binding var selection: TaskManagerSection
    let isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TaskManagerSection.allCases) { section in
                SidebarRow(
                    section: section,
                    isSelected: selection == section,
                    isExpanded: isExpanded
                )
                .onTapGesture {
                    selection = section
                }
            }

            Spacer()
        }
        .padding(.top, 44)
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

    var body: some View {
        HStack(spacing: isExpanded ? 18 : 0) {
            ZStack(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WindowsTaskManagerTheme.accent)
                        .frame(width: 4, height: 22)
                        .offset(x: isExpanded ? -10 : -8)
                }

                Image(systemName: section.iconSystemName)
                    .taskManagerFont(18)
                    .frame(width: 22)
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
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? WindowsTaskManagerTheme.sidebarSelection : Color.clear)
        }
        .contentShape(Rectangle())
        .help(section.rawValue)
    }
}
