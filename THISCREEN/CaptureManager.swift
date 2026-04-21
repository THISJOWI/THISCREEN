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
        guard !isInProgress else {
            print("[CaptureManager] Screenshot already in progress, ignoring request")
            return
        }
        isInProgress = true
        print("[CaptureManager] Starting screenshot capture")

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thiscreen_capture.png")
        try? FileManager.default.removeItem(at: tempUrl)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-r", "-t", "png", tempUrl.path]

        // Hide app before capture (preserves window) - wait for hide to complete
        DispatchQueue.main.async {
            print("[CaptureManager] Hiding app before capture")
            NSApp.hide(nil)

            // Small delay to ensure app is fully hidden before starting capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.executeScreenshot(process: process, tempUrl: tempUrl)
            }
        }
    }

    private func executeScreenshot(process: Process, tempUrl: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("[CaptureManager] Executing screencapture process")
                try process.run()
                process.waitUntilExit()

                let success = FileManager.default.fileExists(atPath: tempUrl.path)
                print("[CaptureManager] Screenshot completed, file exists: \(success)")

                DispatchQueue.main.async {
                    self.isInProgress = false
                    if success, let image = NSImage(contentsOf: tempUrl) {
                        self.screenshot = image
                        print("[CaptureManager] Screenshot loaded successfully")
                    } else {
                        print("[CaptureManager] Screenshot cancelled or failed")
                    }
                    // Always bring window back after capture (success or cancelled)
                    self.bringToFront()
                }
            } catch {
                print("[CaptureManager] Screenshot error: \(error)")
                DispatchQueue.main.async {
                    self.isInProgress = false
                    self.bringToFront()
                }
            }
        }
    }
    
    func startRecording(mode: RecordingMode = .selectedArea, includeMic: Bool = false, showClicks: Bool = true) {
        guard !isInProgress else {
            print("[CaptureManager] Recording already in progress, ignoring request")
            return
        }
        isInProgress = true
        print("[CaptureManager] Starting screen recording, mode: \(mode)")

        var args = ["-v"]

        switch mode {
        case .entireScreen:
            break
        case .selectedArea, .currentCrop:
            // Force the interactive UI to start directly in video mode.
            args.append(contentsOf: ["-J", "video", "-i"])
        }

        if showClicks { args.append("-k") }
        if includeMic { args.append("-g") }
        let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("THISCREEN_recording.mov")
        try? FileManager.default.removeItem(at: videoUrl)

        args.append(videoUrl.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args

        // Hide app before recording - wait for hide to complete
        DispatchQueue.main.async {
            print("[CaptureManager] Hiding app before recording")
            NSApp.hide(nil)

            // Small delay to ensure app is fully hidden before starting recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.executeRecording(process: process, videoUrl: videoUrl)
            }
        }
    }

    private func executeRecording(process: Process, videoUrl: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.activeRecordingProcess = process
                    print("[CaptureManager] Recording process started")
                }
                try process.run()
                process.waitUntilExit()

                let videoPath = videoUrl.path
                let videoExists = FileManager.default.fileExists(atPath: videoPath)
                print("[CaptureManager] Recording completed, file exists: \(videoExists)")

                DispatchQueue.main.async {
                    self.isRecording = false
                    self.isInProgress = false
                    self.activeRecordingProcess = nil

                    if videoExists {
                        self.screenshot = nil
                        self.lastVideoUrl = videoUrl
                        // Post notification to trigger save dialog automatically
                        NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSaveVideo"), object: nil)
                    }
                    self.bringToFront()
                }
            } catch {
                print("[CaptureManager] Recording error: \(error)")
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
            print("[CaptureManager] Bringing window to front")

            // Ensure app is activated first
            NSApp.activate(ignoringOtherApps: true)

            // Small delay to ensure activation completes before showing window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // WindowManager owns a permanent NSWindow — always works even after close
                WindowManager.shared.show()
            }
        }
    }
}
