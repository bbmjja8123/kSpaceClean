import AppKit
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "trash.circle", accessibilityDescription: "kUninstall")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 kUninstall", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "快速卸载...", action: #selector(quickUninstall), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quickUninstall() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
