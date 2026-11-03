import AppKit
import ServiceManagement
import SwiftUI

/// Right-click (or ⌃-click) on the menu bar icon shows a native menu with the general
/// options; left-click keeps opening the popover. `MenuBarExtra` has no hook for
/// this, so a local event monitor catches clicks on our status bar window.
@MainActor
final class StatusMenu: NSObject {
    static let shared = StatusMenu()

    private weak var model: AppModel?
    private var openWindow: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var monitor: Any?

    func install(model: AppModel, openWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openWindow = openWindow
        self.openSettings = openSettings
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = event.window, window.className == "NSStatusBarWindow",
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            self.menu().popUp(positioning: nil, at: .zero, in: window.contentView)
            return nil
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Nueva nota", symbol: "square.and.pencil") { [weak self] in
            self?.model?.showingNewNote = true
            self?.showWindow()
        })
        menu.addItem(item("Abrir expandida", symbol: "arrow.up.left.and.arrow.down.right") { [weak self] in self?.showWindow() })
        menu.addItem(item("Abrir carpeta de notas", symbol: "folder") { [weak self] in
            if let root = self?.model?.store.root { NSWorkspace.shared.open(root) }
        })
        menu.addItem(.separator())
        menu.addItem(item("Ver archivadas", checked: model?.showArchived == true) { [weak self] in
            self?.model?.showArchived.toggle()
        })
        menu.addItem(item("Mostrar planes terminados", checked: model?.showFinishedPlans == true) { [weak self] in
            self?.model?.showFinishedPlans.toggle()
        })
        menu.addItem(item("Abrir al iniciar sesión", checked: SMAppService.mainApp.status == .enabled) {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            } else {
                try? SMAppService.mainApp.register()
            }
        })
        menu.addItem(.separator())
        let settings = item("Ajustes…", symbol: "gearshape") { [weak self] in activate { self?.openSettings?() } }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = item("Salir de coTs") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    func showWindow() {
        activate { openWindow?() }
    }

    private func item(_ title: String.LocalizationValue, symbol: String? = nil, checked: Bool = false,
                      action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: String(localized: title), action: action)
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        item.state = checked ? .on : .off
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

/// The menu bar icon. It's the one view that exists for the app's whole lifetime, so it
/// hands the scene's `openWindow` / `openSettings` actions to the right-click menu.
struct StatusLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Same Image + Text shape as before: the status item renders a flat label best.
        let unread = model.unreadCount
        Image(systemName: unread > 0 ? "book.closed.fill" : "book.closed")
            .task { register() }
        if unread > 0 { Text(verbatim: "\(unread)") }
    }

    func register() {
        StatusMenu.shared.install(model: model,
                                 openWindow: { openWindow(id: "main") },
                                 openSettings: { openSettings() })
        let model = model
        Notifier.shared.onOpen = { id in
            model.showSessions = model.sessionNotes.contains { $0.id == id }
            model.windowSelection = id
            StatusMenu.shared.showWindow()
        }
    }
}
