import CotsCore
import SwiftUI

/// Shown on hidden session notes: what happened to that session and what to do with
/// its last message.
struct SessionBanner: View {
    @Environment(NotesStore.self) private var store
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
                Button { store.promoteSession(note) } label: { Label("Guardar como nota", systemImage: "square.and.arrow.down") }
                Spacer()
                if resume != .dismissed {
                    Button("Descartar") { store.dismissSession(note) }
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
