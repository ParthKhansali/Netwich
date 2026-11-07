import AppKit
import MergeKit
import SwiftUI

// MARK: - Scope

enum DownloadScope {
    case active
    case completed
}

private enum DownloadSort: String, CaseIterable, Identifiable {
    case recent, oldest, name, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Newest first"
        case .oldest: return "Oldest first"
        case .name: return "Name"
        case .size: return "Size"
        }
    }
}

private enum StatusFilter: String, CaseIterable, Identifiable {
    case all, downloading, paused, failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .downloading: return "Active"
        case .paused: return "Paused"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Downloads page

struct DownloadsPage: View {
    @Bindable var state: AppState
    var scope: DownloadScope
    var onNewDownload: () -> Void

    @State private var search = ""
    @State private var filter: StatusFilter = .all
    @State private var sort: DownloadSort = .recent
    @State private var selectionMode = false
    @State private var selected: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.white.opacity(0.06))
            summary

            if items.isEmpty {
                EmptyDownloads(scope: scope, onNewDownload: onNewDownload)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 9) {
                        ForEach(items) { item in
                            DownloadCard(
                                state: state,
                                item: item,
                                selectionMode: selectionMode,
                                isSelected: selected.contains(item.id),
                                onToggle: {
                                    if selected.contains(item.id) {
                                        selected.remove(item.id)
                                    } else {
                                        selected.insert(item.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .confirmationDialog("Delete selected downloads?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove from list") {
                state.deleteDownloads(selected, removeFiles: false)
                finishSelection()
            }
            Button("Delete files too", role: .destructive) {
                state.deleteDownloads(selected, removeFiles: true)
                finishSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selected.count) item(s) selected.")
        }
        .confirmationDialog("Clear completed downloads?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Keep files, clear list") { state.clearCompletedDownloads() }
            Button("Delete files too", role: .destructive) { state.clearAllHistory(removeFiles: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can keep the downloaded files on disk.")
        }
    }

    // MARK: Toolbar

    @ViewBuilder
    private var toolbar: some View {
        if selectionMode {
            HStack(spacing: 10) {
                Button {
                    if selected.count == items.count {
                        selected.removeAll()
                    } else {
                        selected = Set(items.map(\.id))
                    }
                } label: {
                    Image(systemName: selected.count == items.count && !items.isEmpty ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selected.isEmpty ? Color.secondary : Palette.accent)
                }
                .buttonStyle(.plain)

                Text("\(selected.count) selected")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Resume") { state.resumeDownloads(selected) }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(selected.isEmpty)

                Button("Pause") { state.pauseDownloads(selected) }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(selected.isEmpty)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.rose))
                .disabled(selected.isEmpty)

                Button("Done") { finishSelection() }
                    .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        } else {
            HStack(spacing: 9) {
                SearchField(text: $search, placeholder: scope == .completed ? "Search history" : "Search downloads")

                if scope == .active {
                    StatusFilterBar(selection: $filter, counts: filterCounts)
                }

                Spacer(minLength: 6)

                Menu {
                    ForEach(DownloadSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if !items.isEmpty {
                    Button {
                        withAnimation(Motion.morph) {
                            selectionMode = true
                            selected.removeAll()
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .buttonStyle(IconActionStyle())
                    .help("Select multiple")
                }

                if scope == .active {
                    if state.pausedDownloadsCount > 0 || state.failedDownloadsCount > 0 {
                        Button {
                            state.resumeAllDownloads()
                        } label: {
                            Label("Resume all", systemImage: "play.fill")
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                    if state.activeDownloadsCount > 0 {
                        Button {
                            state.pauseAllDownloads()
                        } label: {
                            Label("Pause all", systemImage: "pause.fill")
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                } else {
                    Button {
                        state.openDefaultDownloadFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(IconActionStyle())
                    .help("Open downloads folder")

                    if state.completedDownloadsCount > 0 {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(IconActionStyle(tint: Palette.rose))
                        .help("Clear history")
                    }
                }

                Button {
                    onNewDownload()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if !items.isEmpty {
            let totalSpeed = items.reduce(0.0) { $0 + $1.speedBytesPerSec }
            let downloaded = items.reduce(Int64(0)) { $0 + max(0, $1.downloadedBytes) }
            let total = items.reduce(Int64(0)) { $0 + max($1.totalBytes, $1.downloadedBytes) }

            HStack(spacing: 8) {
                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                if scope == .active, total > 0 {
                    Text("·").foregroundStyle(.secondary.opacity(0.5))
                    Text("\(ByteFormat.size(downloaded)) of \(ByteFormat.size(total))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                if scope == .completed, total > 0 {
                    Text("·").foregroundStyle(.secondary.opacity(0.5))
                    Text(ByteFormat.size(total))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if totalSpeed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(ByteFormat.rate(totalSpeed))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    // MARK: Data

    private var filterCounts: [StatusFilter: Int] {
        var counts: [StatusFilter: Int] = [:]
        let active = state.downloads.filter { $0.status != .completed }
        counts[.all] = active.count
        counts[.downloading] = state.activeDownloadsCount
        counts[.paused] = state.pausedDownloadsCount
        counts[.failed] = state.failedDownloadsCount
        return counts
    }

    private var items: [DownloadItem] {
        var list = state.downloads

        switch scope {
        case .active:
            list = list.filter { $0.status != .completed }
            switch filter {
            case .all: break
            case .downloading: list = list.filter { $0.status == .downloading || $0.status == .probing || $0.status == .queued }
            case .paused: list = list.filter { $0.status == .paused }
            case .failed: list = list.filter { $0.status.isFailed }
            }
        case .completed:
            list = list.filter { $0.status == .completed }
        }

        let keyword = search.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            list = list.filter {
                $0.filename.localizedCaseInsensitiveContains(keyword)
                    || $0.url.absoluteString.localizedCaseInsensitiveContains(keyword)
            }
        }

        switch sort {
        case .recent: list.sort { $0.addedDate > $1.addedDate }
        case .oldest: list.sort { $0.addedDate < $1.addedDate }
        case .name: list.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        case .size: list.sort { $0.totalBytes > $1.totalBytes }
        }
        return list
    }

    private func finishSelection() {
        withAnimation(Motion.morph) {
            selectionMode = false
            selected.removeAll()
        }
    }
}

// MARK: - Download card

struct DownloadCard: View {
    @Bindable var state: AppState
    var item: DownloadItem
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onToggle: (() -> Void)? = nil

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if selectionMode {
                    Button {
                        onToggle?()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? Palette.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                FileGlyph(filename: item.filename)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(item.filename)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        StatusPill(text: shortStatus, color: Palette.forStatus(item.status))
                    }

                    Text(metaLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 5) {
                    primaryAction
                }
                .opacity(hover || selectionMode ? 1 : 0.55)
                .animation(Motion.fade, value: hover)

                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
            }

            if showsProgress {
                ProgressTrack(
                    progress: item.progress,
                    tint: Palette.forStatus(item.status),
                    animated: item.status == .downloading
                )

                if item.chunks.count > 1 {
                    ChunkStrip(chunks: item.chunks)
                }
            }

            if case .failed(let reason) = item.status {
                failureRow(reason: reason)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.07 : (hover ? 0.045 : 0.028)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Motion.fade) { hover = hovering }
        }
        .onTapGesture {
            if selectionMode { onToggle?() }
        }
        .contextMenu { menuItems }
    }

    private var showsProgress: Bool {
        switch item.status {
        case .downloading, .paused, .queued, .probing: return true
        default: return false
        }
    }

    private var shortStatus: String {
        switch item.status {
        case .completed: return "Done"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .probing: return "Preparing"
        case .queued: return "Queued"
        case .failed: return "Failed"
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if item.totalBytes > 0 {
            parts.append("\(ByteFormat.size(item.downloadedBytes)) of \(ByteFormat.size(item.totalBytes))")
        } else if item.downloadedBytes > 0 {
            parts.append(ByteFormat.size(item.downloadedBytes))
        }
        if item.speedBytesPerSec > 1024 {
            parts.append(ByteFormat.rate(item.speedBytesPerSec))
        }
        if let eta = item.etaSeconds, item.status == .downloading {
            parts.append("ETA \(ByteFormat.duration(eta))")
        }
        if item.chunks.count > 1 {
            parts.append("\(item.chunks.count) chunks")
        }
        if parts.isEmpty {
            parts.append(item.url.host ?? "Waiting")
        }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch item.status {
        case .downloading:
            Button {
                state.pauseDownload(item.id)
            } label: {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(IconActionStyle())
            .help("Pause")
        case .paused, .failed:
            Button {
                state.resumeDownload(item.id)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(IconActionStyle(tint: Palette.mint))
            .help("Resume")
        case .completed:
            Button {
                state.openDownloadedFile(item)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(IconActionStyle())
            .help("Open")
        case .queued, .probing:
            ProgressView().controlSize(.mini).scaleEffect(0.7)
        }
    }

    private func failureRow(reason: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.rose)
            Text(reason)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Retry") {
                state.resumeDownload(item.id)
            }
            .buttonStyle(GlassButtonStyle(tint: Palette.rose))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.rose.opacity(0.08)))
    }

    @ViewBuilder
    private var menuItems: some View {
        if item.status == .downloading {
            Button("Pause") { state.pauseDownload(item.id) }
        } else if item.status == .paused || item.status.isFailed {
            Button("Resume") { state.resumeDownload(item.id) }
        } else if item.status == .completed {
            Button("Open") { state.openDownloadedFile(item) }
        }

        Button("Show in Finder") { state.revealInFinder(item) }

        Button("Copy link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
        }

        if item.status == .completed || item.status.isFailed {
            Button("Restart") { state.restartDownload(item.id) }
        }

        Divider()

        Button("Remove from list", role: .destructive) {
            state.deleteDownload(item.id, removeFile: false)
        }
        Button("Delete file", role: .destructive) {
            state.deleteDownload(item.id, removeFile: true)
        }
    }
}

// MARK: - Progress visuals

struct ProgressTrack: View {
    var progress: Double
    var tint: Color
    var animated: Bool

    @State private var shimmer = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))

                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * min(1, max(0, progress))))
                    .overlay(alignment: .trailing) {
                        if animated {
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.55), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 46)
                            .offset(x: shimmer ? 6 : -52)
                            .clipShape(Capsule())
                        }
                    }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }
}

struct ChunkStrip: View {
    var chunks: [ChunkState]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(chunks) { chunk in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(color(for: chunk))
                        .scaleEffect(x: max(0.02, chunk.progress), y: 1, anchor: .leading)
                        .animation(Motion.gentle, value: chunk.progress)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 3)
                .help("Chunk \(chunk.id + 1) · \(chunk.assignedInterface ?? "auto") · \(Int(chunk.progress * 100))%")
            }
        }
    }

    private func color(for chunk: ChunkState) -> Color {
        if chunk.isCompleted { return Palette.mint }
        if let interface = chunk.assignedInterface, interface.hasPrefix("feth") { return Palette.amber }
        return Palette.accent
    }
}

// MARK: - File glyph

struct FileGlyph: View {
    var filename: String

    var body: some View {
        let style = Self.style(for: filename)
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.color.opacity(0.15))
                .frame(width: 36, height: 36)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style.color.opacity(0.22), lineWidth: 0.7)
                .frame(width: 36, height: 36)
            Image(systemName: style.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(style.color)
        }
    }

    static func style(for filename: String) -> (icon: String, color: Color) {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "zip", "tar", "gz", "7z", "rar", "bz2": return ("doc.zipper", Palette.amber)
        case "dmg", "iso", "pkg": return ("opticaldiscdrive", Palette.violet)
        case "mp4", "mov", "mkv", "avi", "webm": return ("film", Palette.violet)
        case "mp3", "wav", "m4a", "flac", "aac": return ("waveform", Palette.rose)
        case "png", "jpg", "jpeg", "webp", "gif", "heic": return ("photo", Palette.mint)
        case "pdf", "epub", "doc", "docx": return ("doc.richtext", Palette.rose)
        case "swift", "ts", "js", "py", "rs", "go", "json", "html": return ("curlybraces", Palette.cyan)
        case "app", "exe": return ("shippingbox", Palette.accent)
        default: return ("arrow.down.doc", Palette.accent)
        }
    }
}

// MARK: - Toolbar pieces

private struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7))
    }
}

private struct StatusFilterBar: View {
    @Binding var selection: StatusFilter
    var counts: [StatusFilter: Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatusFilter.allCases) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(Motion.snappy) { selection = option }
                } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                        let count = counts[option] ?? 0
                        if count > 0, option != .all {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.white.opacity(0.10))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.035)))
    }
}

// MARK: - Empty state

private struct EmptyDownloads: View {
    var scope: DownloadScope
    var onNewDownload: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.10))
                    .frame(width: 74, height: 74)
                Image(systemName: scope == .completed ? "clock.arrow.circlepath" : "arrow.down.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Palette.accent.opacity(0.8))
            }

            VStack(spacing: 5) {
                Text(scope == .completed ? "No finished downloads yet" : "Nothing in the queue")
                    .font(.system(size: 14, weight: .semibold))
                Text(scope == .completed
                     ? "Completed transfers are kept here with their full history."
                     : "Add a link, drop one into the window, or send it from your browser.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }

            HStack(spacing: 8) {
                if scope == .active, let clipboard = clipboardURL {
                    Button {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .openNewDownloadSheet, object: nil)
                        }
                    } label: {
                        Label("Paste \(clipboard.host ?? "link")", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Palette.accent))
                }

                Button {
                    onNewDownload()
                } label: {
                    Label("New Download", systemImage: "plus")
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var clipboardURL: URL? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

// MARK: - New download sheet

struct NewDownloadSheet: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool

    @State private var urlString = ""
    @State private var filename = ""
    @State private var folder: URL
    @State private var concurrency: Int
    @State private var errorText: String?

    init(state: AppState, isPresented: Binding<Bool>) {
        self.state = state
        self._isPresented = isPresented
        self._folder = State(initialValue: state.defaultDestinationFolder)
        self._concurrency = State(initialValue: state.defaultConcurrency)
    }

    var body: some View {
        ZStack {
            AuroraBackdrop(isActive: true)
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 14) {
                    field(title: "Link") {
                        TextField("https://example.com/file.zip", text: $urlString)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit(start)
                    }

                    field(title: "Save as (optional)") {
                        TextField("Detected from the server", text: $filename)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }

                    field(title: "Folder") {
                        HStack(spacing: 8) {
                            Text(folder.path)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Choose…") { chooseFolder() }
                                .buttonStyle(GlassButtonStyle())
                        }
                    }

                    field(title: "Parallel streams") {
                        HStack(spacing: 10) {
                            Slider(value: Binding(
                                get: { Double(concurrency) },
                                set: { concurrency = Int($0 / 2) * 2 }
                            ), in: 2...32, step: 2)
                            .tint(Palette.accent)
                            Text("\(concurrency)")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .frame(width: 22, alignment: .trailing)
                        }
                    }

                    if let errorText {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.amber)
                            Text(errorText).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)

                Spacer(minLength: 0)

                Divider().overlay(Color.white.opacity(0.07))

                HStack {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(GlassButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Start Download", action: start)
                        .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
            }
            .frame(width: 470)
            .glassSurface(cornerRadius: 20)
            .padding(18)
        }
        .frame(width: 510, height: 430)
        .onAppear(perform: prefillFromClipboard)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.accent.opacity(0.14)).frame(width: 30, height: 30)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("New download").font(.system(size: 14, weight: .semibold))
                Text("Split into chunks across your connections")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconActionStyle())
        }
        .padding(16)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).microLabel()
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7))
        }
    }

    private func prefillFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        urlString = text
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let selected = panel.url {
            folder = selected
        }
    }

    private func start() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorText = "Enter a valid http or https link."
            return
        }

        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        state.downloadManager.addDownload(
            url: url,
            destinationFolder: folder,
            customFilename: name.isEmpty ? nil : name,
            concurrency: concurrency
        )
        isPresented = false
    }
}
