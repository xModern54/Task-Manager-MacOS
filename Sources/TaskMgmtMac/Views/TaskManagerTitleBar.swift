import SwiftUI

struct TaskManagerTitleBar: View {
    @ObservedObject var viewModel: TaskManagerViewModel

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 12, height: 44)

            Button {} label: {
                Image(systemName: "line.3.horizontal")
                    .taskManagerFont(16, weight: .medium)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true)

            HStack(spacing: 0) {
                Text("Task Manager")
                    .taskManagerFont(16, weight: .semibold)
                    .lineLimit(1)
            }
            .frame(width: 205, alignment: .leading)

            SearchField(text: $viewModel.searchText)
                .frame(width: 390, height: 40)
                .padding(.leading, 10)

            Spacer()
        }
        .frame(height: 44)
        .background(WindowsTaskManagerTheme.titleBar)
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .taskManagerFont(17)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Type a name, publisher, or PID to search")
                        .taskManagerFont(15)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                }

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .taskManagerFont(15)
                    .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                    .tint(WindowsTaskManagerTheme.accent)
                    .focused($isFocused)
            }
        }
        .padding(.horizontal, 18)
        .background(isFocused ? WindowsTaskManagerTheme.searchBackgroundFocused : WindowsTaskManagerTheme.searchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isFocused ? WindowsTaskManagerTheme.searchBorderFocused : WindowsTaskManagerTheme.searchBorder, lineWidth: 1)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = false
            }
        }
    }
}
