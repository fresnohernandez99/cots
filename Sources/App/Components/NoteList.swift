import CotsCore
import SwiftUI

struct NoteList: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser
    @Binding var selection: String?
    var showFolder = true

    var body: some View {
        @Bindable var browser = browser
        let notes = browser.visibleNotes(in: store)
        let active = notes.filter { !$0.isFinishedPlan }
        let finished = notes.filter(\.isFinishedPlan)
        if notes.isEmpty {
            if browser.search.isEmpty {
                ContentUnavailableView("Sin notas", systemImage: "note.text",
                                       description: Text("Pídele a una IA «guarda en cots», o crea una nota."))
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: browser.search)
                    .frame(maxHeight: .infinity)
            }
        } else {
            List(selection: $selection) {
                ForEach(active) { row($0) }
                if !finished.isEmpty {
                    Button {
                        withAnimation(.snappy) { browser.showFinishedPlans.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(browser.showFinishedPlans ? 90 : 0))
                            Text("Planes terminados")
                            Text(verbatim: "\(finished.count)").foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 4, trailing: 12))
                    .selectionDisabled()
                    if browser.showFinishedPlans {
                        ForEach(finished) { row($0) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ note: Note) -> some View {
        NoteRow(note: note, showFolder: showFolder)
            .tag(note.id)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 10))
            .contextMenu { NoteMenuItems(note: note) }
    }
}
