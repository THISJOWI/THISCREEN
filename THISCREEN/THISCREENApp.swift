//
//  THISCREENApp.swift
//  THISCREEN
//
//  Created by joel mendez cruz on 28/3/26.
//

import SwiftUI
import AppKit

class StatusBarManager {
    static let shared = StatusBarManager()
    private var statusItem: NSStatusItem?
    private var captureManager: CaptureManager?
    
    func setup(captureManager: CaptureManager) {
        // Avoid creating duplicate status items
        guard statusItem == nil else {
            self.captureManager = captureManager
            return
        }
        
        self.captureManager = captureManager
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "viewfinder.circle.fill", accessibilityDescription: "ThiScreen")
            button.image?.size = NSSize(width: 22, height: 22)
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        setupMenu()
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            // Right click shows menu
            statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else {
            // Left click opens window
            NSApp.activate(ignoringOtherApps: true)
            
            // Try to bring existing window to front, or trigger open
            if let window = NSApp.windows.first(where: { !String(describing: type(of: $0)).contains("StatusBar") }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NotificationCenter.default.post(name: NSNotification.Name("TriggerShowWindow"), object: nil)
            }
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open ThiScreen Editor", action: #selector(openEditor), keyEquivalent: "e")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let captureItem = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)
        
        let recordMenu = NSMenu()
        
        let entireRecordItem = NSMenuItem(title: "Entire Screen", action: #selector(recordEntireScreen), keyEquivalent: "a")
        entireRecordItem.keyEquivalentModifierMask = [.command, .shift]
        entireRecordItem.target = self
        recordMenu.addItem(entireRecordItem)
        
        let areaRecordItem = NSMenuItem(title: "Selected Area", action: #selector(recordSelectedArea), keyEquivalent: "r")
        areaRecordItem.keyEquivalentModifierMask = [.command, .shift]
        areaRecordItem.target = self
        recordMenu.addItem(areaRecordItem)
        
        let recordItem = NSMenuItem(title: "Record...", action: nil, keyEquivalent: "")
        recordItem.submenu = recordMenu
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit THISCREEN", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func openEditor() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Try to bring existing window to front, or trigger open
        if let window = NSApp.windows.first(where: { !String(describing: type(of: $0)).contains("StatusBar") }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("TriggerShowWindow"), object: nil)
        }
    }
    
    @objc private func captureArea() {
        captureManager?.takeScreenshot()
    }
    
    @objc private func recordEntireScreen() {
        captureManager?.startRecording(mode: .entireScreen)
    }
    
    @objc private func recordSelectedArea() {
        captureManager?.startRecording(mode: .selectedArea)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as a background accessory with no dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Hide the app on cold launch (preserves window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.hide(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running in the background/menu bar even if the window is closed
        return false
    }
}

@main
struct THISCREENApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var captureManager = CaptureManager.shared
    
    @Environment(\.openWindow) var openWindow
    
    private func setupOverlayWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where !String(describing: type(of: window)).contains("StatusBar") {
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(captureManager)
                .onAppear { setupOverlayWindow() }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerShowWindow"))) { _ in
                    openWindow(id: "main")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Drawing / Crop") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerUndo"), object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command])
            }
            
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Captured Image") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerCopy"), object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command])
                
                Button("Save Captured Image") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerSave"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
        .onChange(of: captureManager.isRecording) { _, _ in
            // Update menu when recording state changes
            StatusBarManager.shared.setup(captureManager: captureManager)
        }
    }
    
    init() {
        GlobalHotkeyManager.shared.setupHotkeys()
        
        // Setup status bar after a short delay to ensure captureManager is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            StatusBarManager.shared.setup(captureManager: CaptureManager.shared)
        }
    }
}
