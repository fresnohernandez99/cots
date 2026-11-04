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
        let store = NotesStore()
        let browser = Browser()
        store.reloadSynchronously()
        let plan = store.notes.first { $0.style == .plan && $0.reviewStatus == .pending }
        let report = store.notes.first { $0.style == .report && $0.meta.actions != nil } ?? store.notes.first { $0.style == .report }

        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            render(MenuContentView(), store: store, browser: browser, size: CGSize(width: 400, height: 560), dark: dark, to: dir, name: "popover\(suffix)")
            if let report {
                render(NoteDetailView(noteID: report.id, onBack: {}), store: store, browser: browser, size: CGSize(width: 400, height: 560),
                       dark: dark, to: dir, name: "popover-report\(suffix)")
            }
            if let plan {
                render(NoteDetailView(noteID: plan.id, onBack: {}), store: store, browser: browser, size: CGSize(width: 400, height: 560),
                       dark: dark, to: dir, name: "popover-plan\(suffix)")
            }
            render(SidebarView(), store: store, browser: browser, size: CGSize(width: 240, height: 560), dark: dark, to: dir, name: "sidebar\(suffix)")
            browser.windowSelection = (plan ?? report)?.id
            render(MainWindowView(), store: store, browser: browser, size: CGSize(width: 1100, height: 680), dark: dark, to: dir, name: "window\(suffix)")
            browser.windowSelection = nil
        }
        if let session = store.sessionNotes.first {
            render(NoteDetailView(noteID: session.id, onBack: {}), store: store, browser: browser, size: CGSize(width: 400, height: 560),
                   dark: false, to: dir, name: "popover-session")
        }
        browser.selectedFolder = NoteStore.plansFolder
        render(MenuContentView(), store: store, browser: browser, size: CGSize(width: 400, height: 560), dark: false, to: dir, name: "popover-plans")
        browser.showFinishedPlans = true
        render(MenuContentView(), store: store, browser: browser, size: CGSize(width: 400, height: 560), dark: false, to: dir, name: "popover-plans-expanded")
        browser.showFinishedPlans = false
        browser.selectedFolder = nil
        render(NewNoteView(initialFolder: nil) { _ in }, store: store, browser: browser, size: CGSize(width: 480, height: 560), dark: false, to: dir, name: "new-note")
        render(SettingsView(), store: store, browser: browser, size: CGSize(width: 600, height: 700), dark: false, to: dir, name: "settings")
        print(dir.path)
        exit(0)
    }

    private static func render<V: View>(_ view: V, store: NotesStore, browser: Browser, size: CGSize, dark: Bool, to dir: URL, name: String) {
        let root = view
            .environment(store).environment(browser)
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
