import CotsCore
import SwiftUI

struct NewNoteView: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser
    let initialFolder: String?
    let done: (Note?) -> Void

    @State private var folder = ""
    @State private var newFolder = ""
    @State private var title = ""
    @State private var topic = ""
    @State private var color: String?
    @State private var style: DisplayStyle = .document
    @State private var text = ""

    var body: some View {
        Form {
            TextField("Título", text: $title)
            Picker("Carpeta", selection: $folder) {
                ForEach(store.folders) { Text(verbatim: $0.title).tag($0.name) }
                Text("Nueva carpeta…").tag("")
            }
            if folder.isEmpty {
                TextField("Nombre de la carpeta", text: $newFolder)
            }
            HStack {
                TextField("Topic (proyecto)", text: $topic)
                if !store.topics.isEmpty {
                    Menu {
                        ForEach(store.topics, id: \.self) { t in Button(t) { topic = t } }
                    } label: { Image(systemName: "chevron.down") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
            }
            Picker("Estilo", selection: $style) {
                ForEach(DisplayStyle.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            LabeledContent("Color") {
                HStack(spacing: 5) {
                    swatch(nil)
                    ForEach(Palette.names, id: \.self) { swatch($0) }
                }
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancelar") { done(nil) }
                Spacer()
                Button("Crear") {
                    done(store.create(folder: folder.isEmpty ? newFolder : folder, title: title, style: style,
                                      topic: topic, color: color, body: text))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || (folder.isEmpty && newFolder.isEmpty))
            }
            .padding(10)
        }
        .onAppear {
            folder = initialFolder ?? store.folders.first?.name ?? ""
            topic = browser.selectedTopic ?? ""
        }
    }

    /// nil = automatic (topic or folder color).
    private func swatch(_ name: String?) -> some View {
        Button { color = name } label: {
            Circle()
                .fill(name.flatMap(Palette.color) ?? Color.secondary.opacity(0.25))
                .frame(width: 14, height: 14)
                .overlay { if name == nil { Image(systemName: "wand.and.stars").font(.system(size: 7)) } }
                .overlay(Circle().stroke(Color.primary, lineWidth: color == name ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help(name == nil ? Text("Automático") : Text(verbatim: name!))
    }
}
