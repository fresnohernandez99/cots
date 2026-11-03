import AppKit
import CotsCore
import SwiftUI

/// `coTs --snapshot <dir>` renders the real views against the current notes root
/// (point `COTS_HOME` at fixtures) and writes PNGs, for visual QA without a screen.
@MainActor
enum Snapshots {
    static func run(to dir: URL) -> Never {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        let plan = model.notes.first { $0.style == .plan && $0.reviewStatus == .pending }
        let report = model.notes.first { $0.style == .report }

        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            render(MenuContentView(), model: model, size: CGSize(width: 400, height: 560), dark: dark, to: dir, name: "popover\(suffix)")
            if let report {
                render(NoteDetailView(noteID: report.id, onBack: {}), model: model, size: CGSize(width: 400, height: 560),
                       dark: dark, to: dir, name: "popover-report\(suffix)")
            }
            if let plan {
                render(NoteDetailView(noteID: plan.id, onBack: {}), model: model, size: CGSize(width: 400, height: 560),
                       dark: dark, to: dir, name: "popover-plan\(suffix)")
            }
            render(SidebarView(), model: model, size: CGSize(width: 240, height: 560), dark: dark, to: dir, name: "sidebar\(suffix)")
            model.windowSelection = (plan ?? report)?.id
            render(MainWindowView(), model: model, size: CGSize(width: 1100, height: 680), dark: dark, to: dir, name: "window\(suffix)")
            model.windowSelection = nil
        }
        model.selectedFolder = NoteStore.plansFolder
        render(MenuContentView(), model: model, size: CGSize(width: 400, height: 560), dark: false, to: dir, name: "popover-plans")
        model.showFinishedPlans = true
        render(MenuContentView(), model: model, size: CGSize(width: 400, height: 560), dark: false, to: dir, name: "popover-plans-expanded")
        model.showFinishedPlans = false
        model.selectedFolder = nil
        render(NewNoteView(initialFolder: nil) { _ in }, model: model, size: CGSize(width: 480, height: 560), dark: false, to: dir, name: "new-note")
        render(SettingsView(), model: model, size: CGSize(width: 600, height: 640), dark: false, to: dir, name: "settings")
        print(dir.path)
        exit(0)
    }

    private static func render<V: View>(_ view: V, model: AppModel, size: CGSize, dark: Bool, to dir: URL, name: String) {
        let root = view
            .environment(model)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
