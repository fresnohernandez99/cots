import CotsCore
import SwiftUI

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
