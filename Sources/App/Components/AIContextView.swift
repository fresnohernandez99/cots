import CotsCore
import SwiftUI

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
