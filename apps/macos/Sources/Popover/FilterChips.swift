import CotsCore
import SwiftUI

/// Folder chips, plus a second row of topic chips when notes have topics.
struct FilterChips: View {
    @Environment(NotesStore.self) private var store
    @Environment(Browser.self) private var browser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(Text("Todas"), icon: "tray.full", tint: .accentColor, count: store.unreadCount, selected: browser.selectedFolder == nil) {
                        browser.selectedFolder = nil
                    }
                    ForEach(store.folders) { folder in
                        // Plans show how many wait for a decision, which matters more than unread.
                        chip(Text(verbatim: folder.title), icon: folder.config.icon ?? "folder",
                             tint: Palette.color(folder.config.color) ?? .accentColor,
                             count: folder.name == NoteStore.plansFolder ? store.pendingPlans : store.unread(in: folder.name),
                             selected: browser.selectedFolder == folder.name) {
                            browser.selectedFolder = folder.name
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            if !store.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(store.topics, id: \.self) { topic in
                            Button {
                                browser.selectedTopic = browser.selectedTopic == topic ? nil : topic
                            } label: {
                                TopicChip(topic: topic, selected: browser.selectedTopic == topic)
                                    .overlay(Capsule().stroke(Palette.topicColor(topic), lineWidth: browser.selectedTopic == topic ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func chip(_ title: Text, icon: String, tint: Color, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint)
                title
                if count > 0 { Text(verbatim: "\(count)").fontWeight(.bold) }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? AnyShapeStyle(tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
