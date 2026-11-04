import CotsCore
import SwiftUI

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
    @Environment(NotesStore.self) private var store
    let note: Note
    var showFolder = true

    var body: some View {
        let config = store.config(for: note)
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
