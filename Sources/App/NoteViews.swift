import AppKit
import CotsCore
import SwiftUI

/// Named note colors. Topics without an explicit color get a stable one from this list.
enum Palette {
    static let names = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "mint", "brown", "gray"]

    static func color(_ name: String?) -> Color? {
        guard let name = name?.lowercased() else { return nil }
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "mint": return .mint
        case "brown": return .brown
        case "gray", "grey": return .gray
        default:
            let hex = name.hasPrefix("#") ? String(name.dropFirst()) : name
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }
    }

    static func label(_ name: String) -> LocalizedStringKey {
        switch name {
        case "blue": return "Azul"
        case "purple": return "Morado"
        case "pink": return "Rosa"
        case "red": return "Rojo"
        case "orange": return "Naranja"
        case "yellow": return "Amarillo"
        case "green": return "Verde"
        case "teal": return "Turquesa"
        case "indigo": return "Índigo"
        case "mint": return "Menta"
        case "brown": return "Marrón"
        default: return "Gris"
        }
    }

    /// Non-template dot, so menus show the actual color instead of a monochrome glyph.
    static func swatch(_ color: Color) -> Image {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }

    /// Deterministic across launches (unlike `hashValue`), so a project keeps its color.
    static func topicColor(_ topic: String) -> Color {
        let hash = topic.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ $1.value }
        return color(names[Int(hash % UInt32(names.count - 1))])! // gray stays reserved
    }
}

extension DisplayStyle {
    var label: LocalizedStringKey {
        switch self {
        case .document: return "Documento"
        case .report: return "Informe"
        case .checklist: return "Checklist"
        case .log: return "Registro"
        case .code: return "Código"
        case .plan: return "Plan"
        }
    }

    var symbol: String {
        switch self {
        case .document: return "doc.text"
        case .report: return "doc.richtext"
        case .checklist: return "checklist"
        case .log: return "list.bullet.rectangle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .plan: return "list.bullet.clipboard"
        }
    }
}

extension ReviewStatus {
    var label: LocalizedStringKey {
        switch self {
        case .pending: return "Por revisar"
        case .approved: return "Aprobado"
        case .changes: return "Cambios pedidos"
        case .rejected: return "Rechazado"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .changes: return .yellow
        case .rejected: return .red
        }
    }

    var symbol: String {
        switch self {
        case .pending: return "hourglass"
        case .approved: return "checkmark.circle.fill"
        case .changes: return "arrow.triangle.2.circlepath"
        case .rejected: return "xmark.circle.fill"
        }
    }
}

extension Note {
    func icon(folder: FolderConfig?) -> String {
        meta.display?.icon ?? (style == .document ? folder?.icon : nil) ?? style.symbol
    }

    /// Explicit color, then the topic's, then the folder's.
    func tint(folder: FolderConfig?) -> Color {
        Palette.color(meta.display?.color) ?? meta.topic.map(Palette.topicColor) ?? Palette.color(folder?.color) ?? .accentColor
    }

    var reviewStatus: ReviewStatus? { style == .plan ? meta.review?.resolvedStatus ?? .pending : nil }

    /// Approved or rejected: nothing left for the user to do, so it's grayed out and grouped apart.
    var isFinishedPlan: Bool { reviewStatus == .approved || reviewStatus == .rejected }
}

extension AppModel {
    func config(for note: Note) -> FolderConfig? { folders.first { $0.name == note.folder }?.config }
}

struct TopicChip: View {
    let topic: String
    var selected = false
    var muted = false

    var body: some View {
        let color = muted ? Color.gray : Palette.topicColor(topic)
        Text(topic)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(selected ? 0.3 : 0.14), in: Capsule())
    }
}

struct ReviewBadge: View {
    let status: ReviewStatus
    var muted = false

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(muted ? Color.gray : status.color)
    }
}

struct NoteRow: View {
    @Environment(AppModel.self) private var model
    let note: Note
    var showFolder = true

    var body: some View {
        let config = model.config(for: note)
        // Finished plans are drawn in gray explicitly: `.saturation` isn't honored inside List rows.
        let finished = note.isFinishedPlan
        let tint = finished ? Color.gray.opacity(0.6) : note.tint(folder: config)
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4)
            Image(systemName: note.icon(folder: config))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if note.meta.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                    Text(note.title)
                        .fontWeight(note.meta.resolvedStatus == .unread ? .semibold : .regular)
                        .foregroundStyle(finished ? .secondary : .primary)
                        .lineLimit(1)
                }
                if let summary = note.meta.summary, !summary.isEmpty {
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 5) {
                    if let topic = note.meta.topic { TopicChip(topic: topic, muted: finished) }
                    if let review = note.reviewStatus { ReviewBadge(status: review, muted: finished) }
                    Group {
                        if showFolder { Text(config?.title ?? note.folder) }
                        Text(note.date, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if note.meta.resolvedStatus == .unread {
                Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 6)
            }
        }
        .padding(.vertical, 5)
        .opacity(finished ? 0.75 : 1)
        .contentShape(Rectangle())
    }
}

/// Color choices for a note; shared by the detail toolbar, the row context menu and the menu bar.
struct ColorMenuItems: View {
    @Environment(AppModel.self) private var model
    let note: Note

    var body: some View {
        let current = note.meta.display?.color
        Button { model.setColor(note, nil) } label: {
            Label("Automático", systemImage: current == nil ? "checkmark" : "wand.and.stars")
        }
        Divider()
        ForEach(Palette.names, id: \.self) { name in
            Button { model.setColor(note, name) } label: {
                Label { Text(Palette.label(name)) + Text(current == name ? "  ✓" : "") } icon: { Palette.swatch(Palette.color(name)!) }
            }
        }
    }
}

/// Everything you can do to a note; used as the row context menu and the detail "More" menu.
struct NoteMenuItems: View {
    @Environment(AppModel.self) private var model
    let note: Note

    var body: some View {
        if note.meta.resolvedStatus == .unread {
            Button("Marcar como leída") { model.setStatus(note, .read) }
        } else if note.meta.resolvedStatus == .read {
            Button("Marcar como no leída") { model.setStatus(note, .unread) }
        }
        Button(note.meta.isPinned ? "Desfijar" : "Fijar") { model.togglePin(note) }
        Menu("Color") { ColorMenuItems(note: note) }
        Divider()
        Button("Copiar id para IAs") { Clipboard.copy(note.id) }
        Button("Copiar contenido") { Clipboard.copy(note.body) }
        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
        Button("Abrir en editor externo") { NSWorkspace.shared.open(note.url) }
        Divider()
        if note.meta.resolvedStatus == .archived {
            Button("Desarchivar") { model.setStatus(note, .read) }
        } else {
            Button("Archivar") { model.setStatus(note, .archived) }
        }
        Button("Mover a la papelera", role: .destructive) { model.trash(note) }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct NoteDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let noteID: String
    /// Shown as a back button when the view is embedded in the menu bar popover.
    var onBack: (() -> Void)?

    @State private var editing = false
    @State private var draft = ""
    @State private var reviewComment = ""
    @State private var showAIContext = false
    @State private var pendingRun: NoteAction?
    @State private var runOutput: RunOutput?

    var body: some View {
        if let note = model.note(noteID) {
            content(note)
                .onAppear {
                    reviewComment = note.meta.review?.comment ?? ""
                    // Deferred: writing during the list's selection update re-enters the table view.
                    Task { @MainActor in model.markRead(note) }
                }
        } else {
            ContentUnavailableView("Nota no encontrada", systemImage: "questionmark.folder")
        }
    }

    private func content(_ note: Note) -> some View {
        let config = model.config(for: note)
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
        let toggle: (Int) -> Void = { model.toggleTask(note, line: $0) }
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
                        Circle().fill(note.tint(folder: model.config(for: note))).frame(width: 8, height: 8).padding(.top, 5)
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
                    .tint(.orange)
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
            model.saveBody(note, draft)
            editing = false
        }
        model.setReview(note, status, comment: reviewComment)
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
                    model.saveBody(note, draft)
                    editing = false
                }
                .keyboardShortcut("s")
            } else {
                if onBack != nil {
                    Button {
                        model.windowSelection = note.id
                        activate { openWindow(id: "main") }
                    } label: { Label("Abrir expandida", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .help("Abrir expandida")
                }
                Button {
                    draft = note.body
                    editing = true
                } label: { Label("Editar", systemImage: "pencil") }
                    .help("Editar")
                Button { model.togglePin(note) } label: {
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
            if let s = action.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .openFile:
            if let p = action.path { NSWorkspace.shared.open(URL(fileURLWithPath: (p as NSString).expandingTildeInPath)) }
        case .reveal:
            if let p = action.path {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (p as NSString).expandingTildeInPath)])
            }
        case .run:
            pendingRun = action
        case nil:
            model.lastError = String(localized: "Acción desconocida: \(action.type)")
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

/// The hidden `ai` block, shown only on demand.
struct AIContextView: View {
    let context: AIContext?

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                if let c = context {
                    row("Agente", c.agent)
                    row("Modelo", c.model)
                    row("Sesión", c.session)
                    row("Proyecto", c.project)
                    row("Rama", c.branch)
                    row("Directorio", c.cwd)
                    row("Archivos", c.files?.joined(separator: "\n"))
                    row("Referencias", c.refs?.joined(separator: "\n"))
                    row("Siguiente", c.next?.map { "• \($0)" }.joined(separator: "\n"))
                    row("Contexto", c.context)
                }
            }
            .padding()
        }
        .frame(width: 380)
        .frame(maxHeight: 420)
    }

    @ViewBuilder
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                Text(verbatim: value).font(.caption).textSelection(.enabled)
            }
        }
    }
}

/// Shown on hidden session notes: what happened to that session and what to do with
/// its last message.
struct SessionBanner: View {
    @Environment(AppModel.self) private var model
    let note: Note

    var body: some View {
        let session = note.meta.session
        let interrupted = session?.ended == nil
        let resume = note.meta.resume?.resolvedStatus ?? .open
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: interrupted ? "bolt.horizontal.circle" : "checkmark.circle")
                    .foregroundStyle(interrupted ? .orange : .secondary)
                Text(interrupted ? "La sesión se interrumpió" : "La sesión se cerró")
                if let last = session?.last.flatMap(Timestamp.parse) {
                    Text(last, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                }
                Spacer()
                if resume == .dismissed { Text("Descartada").foregroundStyle(.tertiary) }
            }
            .font(.caption)
            HStack {
                Button {
                    Clipboard.copy(String(localized: "Retoma la sesión anterior de este proyecto: lee `cots read \(note.id)` y continúa donde lo dejamos."))
                } label: { Label("Retomar", systemImage: "arrow.uturn.forward") }
                    .help("Copia un prompt para que una IA retome esta sesión")
                Button { model.promoteSession(note) } label: { Label("Guardar como nota", systemImage: "square.and.arrow.down") }
                Spacer()
                if resume != .dismissed {
                    Button("Descartar") { model.dismissSession(note) }
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
