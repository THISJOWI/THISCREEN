//
//  THISCREENApp.swift
//  THISCREEN
//

import SwiftUI
import AppKit

// MARK: - Window Manager
// Owns a single NSWindow for the lifetime of the app.
// Never destroys it — just shows/hides it — so it always reopens correctly.

class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var windowController: NSWindowController?
    private(set) var isVisible = false
    private var isApplyingFrameUpdate = false

    // Call once at startup to create the window (hidden)
    func createWindow(captureManager: CaptureManager) {
        guard windowController == nil else { return }

        let rootView = ContentView()
            .environmentObject(captureManager)

        let hosting = NSHostingController(rootView: rootView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "THISCREEN"
        window.minSize = NSSize(width: 640, height: 480)
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false   // ← KEY: window lives forever
        window.delegate = self
        window.center()

        configureOverlay(window)

        windowController = NSWindowController(window: window)
        // Start hidden — no "Ready for Capture" screen at launch
    }

    // MARK: Overlay configuration
    func configureOverlay(_ window: NSWindow) {
        // Above .floating and .statusBar — appears over full‑screen apps
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovable = true
        window.isMovableByWindowBackground = false // Fix: drawing shapes won't move window
        window.hidesOnDeactivate = false
    }

    // MARK: Show / Hide
    func show() {
        guard let window = windowController?.window else { return }
        configureOverlay(window)
        
        let hasActiveContent = (CaptureManager.shared.screenshot != nil) || (CaptureManager.shared.lastVideoUrl != nil)
        let isTooSmall = window.frame.width < 760 || window.frame.height < 520
        
        // If the editor has no active capture/video, always restore a comfortable default size.
        // Also recover from any collapsed/tiny window state.
        if !hasActiveContent || isTooSmall {
            window.setContentSize(NSSize(width: 900, height: 620))
            window.center()
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        isVisible = true
    }

    /// Show the window resized to fit the captured image plus toolbar chrome.
    func showFitting(image: NSImage) {
        guard let window = windowController?.window,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            show()
            return
        }
        
        if isApplyingFrameUpdate { return }

        let toolbarHeight: CGFloat = 110   // Reduced estimate for toolbar area
        let horizontalPadding: CGFloat = 40
        let verticalPadding: CGFloat = 40

        let minWidth:  CGFloat = 600
        let minHeight: CGFloat = 450

        // Allow up to 85% of the screen visible frame
        let maxW = screen.visibleFrame.width  * 0.85
        let maxH = screen.visibleFrame.height * 0.85

        let imgW = image.size.width
        let imgH = image.size.height

        // Calculate scale to fit image (and its future annotations) in screen
        let scaleW = maxW / (imgW + horizontalPadding)
        let scaleH = (maxH - toolbarHeight) / imgH
        let scale = min(scaleW, scaleH, 1.0) 

        var finalW = max(minWidth, (imgW * scale) + horizontalPadding)
        var finalH = max(minHeight, (imgH * scale) + toolbarHeight + verticalPadding)
        
        // Ensure aspect ratio isn't too extreme for the window
        if finalW > maxW { finalW = maxW }
        if finalH > maxH { finalH = maxH }

        let x = screen.visibleFrame.midX - finalW / 2
        let y = screen.visibleFrame.midY - finalH / 2
        let newFrame = NSRect(x: x, y: y, width: finalW, height: finalH)

        configureOverlay(window)
        isApplyingFrameUpdate = true
        window.setFrame(newFrame, display: true, animate: false)
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingFrameUpdate = false
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        windowController?.window?.orderOut(nil)
        isVisible = false
    }

    // MARK: NSWindowDelegate — intercept close button (keep alive)
    func windowWillClose(_ notification: Notification) {
        isVisible = false
        // Don't quit — just hide the window so it can reopen
    }
}

// MARK: - Status Bar

class StatusBarManager {
    static let shared = StatusBarManager()
    private var statusItem: NSStatusItem?
    private var captureManager: CaptureManager?

    func setup(captureManager: CaptureManager) {
        guard statusItem == nil else {
            self.captureManager = captureManager
            return
        }
        self.captureManager = captureManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "viewfinder.circle.fill",
                                   accessibilityDescription: "ThiScreen")
            button.image?.size = NSSize(width: 22, height: 22)
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setupMenu()
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else {
            WindowManager.shared.show()
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open ThiScreen Editor",
                                  action: #selector(openEditor),
                                  keyEquivalent: "e")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let captureItem = NSMenuItem(title: "Capture Area (⌘⇧S)",
                                     action: #selector(captureArea),
                                     keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        let recordMenu = NSMenu()
        let entireItem = NSMenuItem(title: "Entire Screen (⌘⇧A)",
                                    action: #selector(recordEntireScreen),
                                    keyEquivalent: "")
        entireItem.target = self
        recordMenu.addItem(entireItem)

        let areaItem = NSMenuItem(title: "Selected Area (⌘⇧R)",
                                  action: #selector(recordSelectedArea),
                                  keyEquivalent: "")
        areaItem.target = self
        recordMenu.addItem(areaItem)

        let recordItem = NSMenuItem(title: "Record...", action: nil, keyEquivalent: "")
        recordItem.submenu = recordMenu
        menu.addItem(recordItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ThiScreen",
                                  action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openEditor()           { WindowManager.shared.show() }
    @objc private func captureArea()          { captureManager?.takeScreenshot() }
    @objc private func recordEntireScreen()   { captureManager?.startRecording(mode: .entireScreen) }
    @objc private func recordSelectedArea()   { captureManager?.startRecording(mode: .selectedArea) }
    @objc private func quitApp()              { NSApp.terminate(nil) }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background-only agent — no Dock icon, no app switcher entry
        NSApp.setActivationPolicy(.accessory)
        checkScreenRecordingPermission()

        // Create the window (hidden) and status bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let cm = CaptureManager.shared
            WindowManager.shared.createWindow(captureManager: cm)
            StatusBarManager.shared.setup(captureManager: cm)
        }
    }

    private func checkScreenRecordingPermission() {
        let opts = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
        if opts == nil || opts?.isEmpty == true {
            CGRequestScreenCaptureAccess()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false   // Keep running when window closes
    }
}

// MARK: - App Entry Point

@main
struct THISCREENApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        GlobalHotkeyManager.shared.setupHotkeys()
    }

    // We don't use a SwiftUI Scene window at all — window is managed by WindowManager.
    // An empty Settings scene keeps the @main struct valid.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
