import SwiftUI
import AppKit
import Combine

class CaptureManager: ObservableObject {
    static let shared = CaptureManager()
    
    enum RecordingMode {
        case entireScreen, selectedArea, currentCrop
    }
    
    @Published var screenshot: NSImage? = nil
    @Published var lastVideoUrl: URL? = nil
    @Published var isInProgress: Bool = false
    @Published var isRecording: Bool = false
    @Published var activeRecordingProcess: Process? = nil
    
    private var observers: [NSObjectProtocol] = []
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerCapture"), object: nil, queue: .main) { [weak self] _ in
            self?.takeScreenshot()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerRecord"), object: nil, queue: .main) { [weak self] _ in
            if self?.isRecording == true { self?.stopRecording() }
            else { self?.startRecording(mode: .selectedArea) }
        })
        
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerStopRecord"), object: nil, queue: .main) { [weak self] _ in
            self?.stopRecording()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerEntireRecord"), object: nil, queue: .main) { [weak self] _ in
            self?.startRecording(mode: .entireScreen)
        })
    }
    
    func takeScreenshot() {
        guard !isInProgress else { return }
        isInProgress = true
        
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thiscreen_capture.png")
        try? FileManager.default.removeItem(at: tempUrl)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-r", "-t", "png", tempUrl.path]
        
        // Hide app before capture (preserves window)
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isInProgress = false
                    if FileManager.default.fileExists(atPath: tempUrl.path), 
                       let image = NSImage(contentsOf: tempUrl) {
                        self.screenshot = image
                    }
                    // Always bring window back after capture (success or cancelled)
                    self.bringToFront()
                }
            } catch {
                print("Screenshot error: \(error)")
                DispatchQueue.main.async { 
                    self.isInProgress = false 
                    self.bringToFront()
                }
            }
        }
    }
    
    func startRecording(mode: RecordingMode = .selectedArea, includeMic: Bool = false, showClicks: Bool = true) {
        guard !isInProgress else { return }
        isInProgress = true
        
        var args = ["-v"]
        
        switch mode {
        case .entireScreen: break
        case .selectedArea: args.append("-i")
        case .currentCrop: args.append("-i")
        }
        
        if showClicks { args.append("-k") }
        if includeMic { args.append("-g") }
        let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ThiScreen_recording.mov")
        try? FileManager.default.removeItem(at: videoUrl)
        
        args.append("-U")
        args.append(videoUrl.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        
        NSApp.hide(nil)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                DispatchQueue.main.async { 
                    self.isRecording = true
                    self.activeRecordingProcess = process
                }
                try process.run()
                process.waitUntilExit()
                
                let videoPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ThiScreen_recording.mov").path
                let videoExists = FileManager.default.fileExists(atPath: videoPath)
                
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.isInProgress = false
                    self.activeRecordingProcess = nil
                    
                    if videoExists {
                        self.screenshot = nil 
                        self.lastVideoUrl = URL(fileURLWithPath: videoPath)
                    }
                    self.bringToFront()
                }
            } catch {
                print("Recording error: \(error)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.isInProgress = false
                    self.activeRecordingProcess = nil
                    self.bringToFront()
                }
            }
        }
    }
    
    func stopRecording() {
        if let process = activeRecordingProcess, process.isRunning {
            process.terminate()
        }
    }
    
    private func bringToFront() {
        DispatchQueue.main.async {
            // Unhide the app first
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            // Find the main window (not status bar)
            let windows = NSApp.windows.filter { !String(describing: type(of: $0)).contains("StatusBar") }
            
            if let window = windows.first {
                // Window exists, make sure it's visible and front
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            } else {
                // No window found, trigger open via notification
                NotificationCenter.default.post(name: NSNotification.Name("TriggerShowWindow"), object: nil)
            }
        }
    }
}
