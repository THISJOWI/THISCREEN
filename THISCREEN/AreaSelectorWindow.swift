import SwiftUI
import AppKit

// MARK: - Area Selector for Recording
// Shows an overlay window that allows the user to select a screen area for recording

class AreaSelectorWindowController: NSObject {
    static let shared = AreaSelectorWindowController()

    private var window: NSWindow?
    private var trackingView: AreaTrackingView?
    private var completionHandler: ((CGRect?) -> Void)?

    func showAreaSelector(includeMic: Bool = false, showClicks: Bool = true, completion: @escaping (CGRect?) -> Void) {
        // If already showing, dismiss first
        dismiss()

        self.completionHandler = completion

        // Get the screen with the mouse
        let mouseLocation = NSEvent.mouseLocation
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            completion(nil)
            return
        }

        let screenFrame = targetScreen.frame

        // Create the tracking view
        let trackingView = AreaTrackingView(frame: NSRect(origin: .zero, size: screenFrame.size))
        trackingView.onComplete = { [weak self] rect in
            guard let self = self else { return }
            
            // screencapture -R expects coordinates with origin at Top-Left of the primary screen
            // AppKit uses origin at Bottom-Left of the primary screen
            if let primaryScreen = NSScreen.screens.first {
                let globalRect = NSRect(
                    x: targetScreen.frame.origin.x + rect.origin.x,
                    y: primaryScreen.frame.height - (targetScreen.frame.origin.y + rect.origin.y + rect.size.height),
                    width: rect.size.width,
                    height: rect.size.height
                )
                self.dismiss()
                self.completionHandler?(globalRect)
            } else {
                self.dismiss()
                self.completionHandler?(rect)
            }
        }
        trackingView.onCancel = { [weak self] in
            self?.dismiss()
            self?.completionHandler?(nil)
        }

        self.trackingView = trackingView

        // Create the window
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = trackingView
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isMovableByWindowBackground = false

        self.window = window

        // Show the window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
        trackingView = nil
    }
}

// MARK: - Area Tracking View (AppKit)

class AreaTrackingView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectedRect: NSRect?
    private var isDragging = false

    // UI Elements
    private var instructionLabel: NSTextField?
    private var confirmPanel: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Instructions label
        let label = NSTextField(labelWithString: "Arrastra para seleccionar el área a grabar\nPresiona ESC para cancelar")
        label.alignment = .center
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = false
        addSubview(label)
        instructionLabel = label

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Make sure we can receive events
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        guard selectedRect == nil else { return }

        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        currentPoint = location
        isDragging = true

        // Hide instructions while dragging
        instructionLabel?.isHidden = true

        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, startPoint != nil else { return }

        let location = convert(event.locationInWindow, from: nil)
        currentPoint = location

        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let start = startPoint else { return }

        isDragging = false
        let end = convert(event.locationInWindow, from: nil)

        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )

        // Only confirm if the selection is large enough
        if rect.width > 50 && rect.height > 50 {
            selectedRect = rect
            showConfirmationPanel()
        } else {
            // Reset if too small
            startPoint = nil
            currentPoint = nil
            instructionLabel?.isHidden = false
        }

        setNeedsDisplay(bounds)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onCancel?()
        } else if event.keyCode == 36 || event.keyCode == 76 { // Return/Enter key
            if let rect = selectedRect {
                onComplete?(rect)
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill the entire view with semi-transparent black
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.fill(bounds)

        // If we have a selection, clear that area and draw border
        let rectToDraw = selectedRect ?? calculatedRect
        if let rect = rectToDraw {
            // Clear the selected area (make it transparent)
            context.clear(rect)

            // Draw white border
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2.0)
            context.stroke(rect)

            // Draw shadow around the selection
            context.setShadow(offset: .zero, blur: 4, color: NSColor.black.withAlphaComponent(0.5).cgColor)

            // Draw dimensions label
            let text = "\(Int(rect.width)) × \(Int(rect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: rect.midX - textSize.width / 2 - 4,
                y: rect.minY - textSize.height - 8,
                width: textSize.width + 8,
                height: textSize.height + 4
            )

            context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            context.fill(textRect.insetBy(dx: -4, dy: -2))
            context.restoreGState()

            text.draw(at: NSPoint(x: textRect.origin.x + 4, y: textRect.origin.y + 2), withAttributes: attributes)
        }
    }

    private var calculatedRect: NSRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    // MARK: - Confirmation Panel

    private func showConfirmationPanel() {
        // Remove existing panel
        confirmPanel?.removeFromSuperview()

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        panel.layer?.cornerRadius = 12
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "¿Grabar esta área?")
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancelar", target: self, action: #selector(cancelSelection))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let recordButton = NSButton(title: "Grabar", target: self, action: #selector(confirmSelection))
        recordButton.keyEquivalent = "\r" // Return key
        recordButton.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(titleLabel)
        panel.addSubview(cancelButton)
        panel.addSubview(recordButton)

        addSubview(panel)
        confirmPanel = panel

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            titleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),

            cancelButton.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
            cancelButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),

            recordButton.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
            recordButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            recordButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 8)
        ])
    }

    @objc private func cancelSelection() {
        onCancel?()
    }

    @objc private func confirmSelection() {
        if let rect = selectedRect {
            onComplete?(rect)
        }
    }
}
