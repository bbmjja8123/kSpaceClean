import SwiftUI
import CoreData
import DesignSystem
import CommonUtils

struct AllFilesTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var sortColumn = "name"
    @State private var sortAscending = true
    @State private var selectedFiles: Set<UUID> = []
    let scanViewModel: ScanViewModel

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FileEntry.size, ascending: false)],
        animation: .default
    ) private var files: FetchedResults<FileEntry>

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.textSecondary)
                TextField("搜索文件...", text: $searchText)
                    .textFieldStyle(.plain).font(AppFont.callout)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.bgTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Table header
            HStack(spacing: 0) {
                CheckboxHeader(isAllSelected: selectedFiles.count == files.count && !files.isEmpty,
                               action: toggleSelectAll)
                    .frame(width: 24)
                SortableHeader("名称", column: "name", sortColumn: $sortColumn, sortAscending: $sortAscending)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SortableHeader("大小", column: "size", sortColumn: $sortColumn, sortAscending: $sortAscending)
                    .frame(width: 70, alignment: .trailing)
                Text("类型").font(AppFont.caption).foregroundColor(.textSecondary).frame(width: 50)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // File list
            let displayFiles = filteredFiles
            List(displayFiles, id: \.id) { file in
                FileRow(file: file, isSelected: selectedFiles.contains(file.id ?? UUID()))
                    .onTapGesture { toggleSelection(file.id ?? UUID()) }
            }
            .listStyle(.plain)

            // Footer
            HStack {
                Text("共 \(displayFiles.count) 个 · 已选 \(selectedFiles.count) 个")
                    .font(AppFont.caption).foregroundColor(.textSecondary)
                Spacer()
                Button("\u{1F5D1} \u{6E05}\u{7406}") { performCleanup() }
                    .buttonStyle(.borderedProminent).tint(.danger).disabled(selectedFiles.isEmpty)
            }
            .padding(8)
        }
    }

    private var filteredFiles: [FileEntry] {
        let sorted = sortColumn == "size"
            ? files.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
            : files.sorted { sortAscending ? ($0.path ?? "") < ($1.path ?? "") : ($0.path ?? "") > ($1.path ?? "") }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { ($0.path ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedFiles.contains(id) { selectedFiles.remove(id) }
        else { selectedFiles.insert(id) }
    }

    private func toggleSelectAll() {
        if selectedFiles.count == files.count {
            selectedFiles.removeAll()
        } else {
            selectedFiles = Set(files.compactMap { $0.id })
        }
    }

    private func performCleanup() {
        let paths = selectedFiles.compactMap { id in
            files.first(where: { $0.id == id })?.path
        }
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let engine = CleanupEngine()
        Task { @MainActor in
            for await progress in engine.cleanup(urls: urls) {
                if progress.state == .completed || progress.state == .failed {
                    selectedFiles.removeAll()
                }
            }
        }
    }
}

// MARK: - Table header components

struct SortableHeader: View {
    let label: String
    let column: String
    @Binding var sortColumn: String
    @Binding var sortAscending: Bool

    init(_ label: String, column: String, sortColumn: Binding<String>, sortAscending: Binding<Bool>) {
        self.label = label
        self.column = column
        _sortColumn = sortColumn
        _sortAscending = sortAscending
    }

    var body: some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 2) {
                Text(label).font(AppFont.caption).foregroundColor(.textSecondary)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8)).foregroundColor(.brandPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CheckboxHeader: View {
    let isAllSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isAllSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isAllSelected ? .brandPrimary : .textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct FileRow: View {
    let file: FileEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isSelected ? .brandPrimary : .textSecondary).frame(width: 24)
            Image(systemName: FileCategory(rawValue: file.category ?? "")?.icon ?? "questionmark")
                .foregroundColor(FileCategory(rawValue: file.category ?? "")?.color ?? .textSecondary)
                .frame(width: 18)
            Text(URL(fileURLWithPath: file.path ?? "").lastPathComponent)
                .font(AppFont.body).foregroundColor(.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(FileSizeFormatter.abbreviated(from: file.size))
                .font(AppFont.monoDigit).foregroundColor(.textSecondary).frame(width: 70, alignment: .trailing)
            CategoryBadge(category: FileCategory(rawValue: file.category ?? "") ?? .other).frame(width: 50)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }
}
