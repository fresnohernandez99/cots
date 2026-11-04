import AppKit
import CotsCore
import SwiftUI

struct NoteDetailView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(\.openWindow) private var openWindow
    let noteID: String
    /// Shown as a back button when the view is embedded in the menu bar popover.
    var onBack: (() -> Void)?

    @State private var editing = false
    @State private var draft = ""
    /// The body when editing started: saving is refused if the file changed since.
    @State private var draftBase = ""
    @State private var reviewComment = ""
    @State private var showAIContext = false
    @State private var pendingRun: NoteAction?
    @State private var runOutput: RunOutput?

    var body: some View {
        if let note = store.note(noteID) {
            content(note)
                .onAppear {
                    reviewComment = note.meta.review?.comment ?? ""
                    // Deferred: writing during the list's selection update re-enters the table view.
                    Task { @MainActor in store.markRead(note) }
                }
        } else {
            ContentUnavailableView("Nota no encontrada", systemImage: "questionmark.folder")
        }
    }

    private func content(_ note: Note) -> some View {
        let config = store.config(for: note)
        return VStack(alignment: .leading, spacing: 0) {
            actionBar(note)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            header(note, config: config)
                .padding([.horizontal, .top], 14)
                .padding(.bottom, 10)
            Divider()
            if editing {
                TextEditor(text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                ScrollView {
                    bodyView(note)
                        .padding(14)
                }
            }
            if note.style == .plan {
                Divider()
                reviewBar(note)
            }
        }
        .overlay(alignment: .top) {
            note.tint(folder: config).frame(height: 3)
        }
        .confirmationDialog("¿Ejecutar este comando?", isPresented: Binding(
            get: { pendingRun != nil }, set: { if !$0 { pendingRun = nil } }
        ), presenting: pendingRun) { action in
            Button("Ejecutar") { run(action) }
            Button("Cancelar", role: .cancel) {}
        } message: { action in
            Text(verbatim: action.command ?? "")
        }
        .sheet(item: $runOutput) { output in
            RunOutputView(output: output)
        }
    }

    private func header(_ note: Note, config: FolderConfig?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: note.icon(folder: config)).foregroundStyle(note.tint(folder: config))
                Text(verbatim: note.title).font(.title3.bold()).textSelection(.enabled)
            }
            HStack(spacing: 6) {
                if let topic = note.meta.topic { TopicChip(topic: topic) }
                Group {
                    if note.folder == Sessions.folder { Text("Sesión") } else { Text(verbatim: config?.title ?? note.folder) }
                    Text(verbatim: "·")
                    Text(note.date, format: .dateTime.day().month().hour().minute())
                    if let source = note.meta.source { Text(verbatim: "· \(source)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let tags = note.meta.tags, !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        Text(verbatim: "#\(tag)").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            if [.report, .plan].contains(note.style), let summary = note.meta.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(note.tint(folder: config).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if note.folder == Sessions.folder {
                SessionBanner(note: note)
            }
            if let error = note.parseError {
                Label("Frontmatter con errores: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
            if let actions = note.meta.actions, !actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                            Button {
                                perform(action, note: note)
                            } label: {
                                Label(LocalizedStringKey(action.displayLabel), systemImage: symbol(for: action))
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bodyView(_ note: Note) -> some View {
        let toggle: (Int) -> Void = { store.toggleTask(note, line: $0) }
        switch note.style {
        case .code:
            Text(verbatim: note.body)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .log:
            let (preamble, entries) = LogEntry.parse(note.body)
            VStack(alignment: .leading, spacing: 14) {
                if !preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownView(text: preamble, onToggleTask: toggle)
                }
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(note.tint(folder: store.config(for: note))).frame(width: 8, height: 8).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: entry.heading).font(.caption.bold()).foregroundStyle(.secondary)
                            MarkdownView(text: entry.text) { toggle(entry.lineOffset + $0) }
                        }
                    }
                }
            }
        case .document, .report, .checklist, .plan:
            MarkdownView(text: note.body, onToggleTask: toggle)
        }
    }

    /// Approve / request changes / reject. An agent blocked on `cots wait` resumes as soon as this is written.
    private func reviewBar(_ note: Note) -> some View {
        let status = note.reviewStatus ?? .pending
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ReviewBadge(status: status)
                if let at = note.meta.review?.at.flatMap(Timestamp.parse), status != .pending {
                    Text(at, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if status != .pending {
                    Button("Reabrir") { decide(note, .pending) }.controlSize(.small)
                }
            }
            TextField("Comentario para la IA (opcional)", text: $reviewComment, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            HStack {
                Button { decide(note, .rejected) } label: { Label("Rechazar", systemImage: "xmark") }
                    .tint(.red)
                Button { decide(note, .changes) } label: { Label("Pedir cambios", systemImage: "arrow.triangle.2.circlepath") }
                    .tint(Palette.amberFill)
                Spacer()
                Button { decide(note, .approved) } label: { Label("Aprobar", systemImage: "checkmark") }
                    .tint(.green)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(status.color.opacity(0.06))
    }

    private func decide(_ note: Note, _ status: ReviewStatus) {
        if editing {
            store.saveBody(note, draft, base: draftBase)
            editing = false
        }
        store.setReview(note, status, comment: reviewComment)
    }

    private func actionBar(_ note: Note) -> some View {
        HStack(spacing: 2) {
            if let onBack {
                Button(action: onBack) { Label("Atrás", systemImage: "chevron.left") }
            }
            Spacer()
            if editing {
                Button("Cancelar") { editing = false }
                Button("Guardar") {
                    store.saveBody(note, draft, base: draftBase)
                    editing = false
                }
                .keyboardShortcut("s")
            } else {
                if onBack != nil {
                    Button {
                        browser.windowSelection = note.id
                        activate { openWindow(id: "main") }
                    } label: { Label("Abrir expandida", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .help("Abrir expandida")
                }
                Button {
                    draft = note.body
                    draftBase = note.body
                    editing = true
                } label: { Label("Editar", systemImage: "pencil") }
                    .help("Editar")
                Button { store.togglePin(note) } label: {
                    Label(note.meta.isPinned ? "Desfijar" : "Fijar", systemImage: note.meta.isPinned ? "pin.slash" : "pin")
                }
                .help(note.meta.isPinned ? "Desfijar" : "Fijar")
                Menu { ColorMenuItems(note: note) } label: {
                    Label("Color", systemImage: "paintpalette")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Color")
                Button { showAIContext.toggle() } label: { Label("Contexto IA", systemImage: "sparkles") }
                    .help("Contexto IA")
                    .disabled(note.meta.ai == nil)
                    .popover(isPresented: $showAIContext) { AIContextView(context: note.meta.ai) }
                Menu { NoteMenuItems(note: note) } label: { Label("Más", systemImage: "ellipsis.circle") }
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .font(.system(size: 13))
        .controlSize(.large)
    }

    // MARK: Actions

    private func symbol(for action: NoteAction) -> String {
        switch action.resolvedType {
        case .copy: return "doc.on.doc"
        case .openURL: return "safari"
        case .openFile: return "arrow.up.forward.app"
        case .reveal: return "folder"
        case .run: return "terminal"
        case nil: return "questionmark"
        }
    }

    private func perform(_ action: NoteAction, note: Note) {
        switch action.resolvedType {
        case .copy:
            Clipboard.copy(action.text ?? note.body)
        case .openURL:
            guard let s = action.url, ActionPolicy.isWebURL(s), let url = URL(string: s) else {
                store.lastError = String(localized: "Solo se abren enlaces web (http, https, mailto).")
                return
            }
            NSWorkspace.shared.open(url)
        case .openFile:
            guard let p = action.path else { return }
            if let refusal = ActionPolicy.refusalToOpen(p) { store.lastError = refusal; return }
            NSWorkspace.shared.open(URL(fileURLWithPath: (p as NSString).expandingTildeInPath))
        case .reveal:
            if let p = action.path {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (p as NSString).expandingTildeInPath)])
            }
        case .run:
            if let refusal = ActionPolicy.refusalToRun(action.command ?? "") { store.lastError = refusal; return }
            pendingRun = action
        case nil:
            store.lastError = String(localized: "Acción desconocida: \(action.type)")
        }
    }

    private func run(_ action: NoteAction) {
        guard let command = action.command else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var output: String
            var status: Int32 = -1
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                output = String(decoding: data, as: UTF8.self)
                status = process.terminationStatus
            } catch {
                output = error.localizedDescription
            }
            let result = RunOutput(command: command, output: output, status: status)
            await MainActor.run { runOutput = result }
        }
    }

}

struct RunOutput: Identifiable {
    let id = UUID()
    let command: String
    let output: String
    let status: Int32
}

struct RunOutputView: View {
    @Environment(\.dismiss) private var dismiss
    let output: RunOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(verbatim: output.command) } icon: {
                Image(systemName: output.status == 0 ? "checkmark.circle" : "xmark.octagon")
            }
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(output.status == 0 ? .green : .red)
            ScrollView {
                Group {
                    if output.output.isEmpty { Text("(sin salida)") } else { Text(verbatim: output.output) }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Text("Código de salida: \(Int(output.status))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: 320)
    }
}
