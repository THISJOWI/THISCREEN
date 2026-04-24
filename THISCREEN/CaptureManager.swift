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

  // MARK: - Default Save Directories
  static let defaultFolderName = "THISCREEN"

  /// Returns the default image save directory (~/Pictures/THISCREEN), creating it if needed
  static func getDefaultSaveDirectory() -> URL? {
    guard let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
      return nil
    }
    let thiscreenDir = picturesDir.appendingPathComponent(defaultFolderName, isDirectory: true)

    // Create directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: thiscreenDir.path) {
      do {
        try FileManager.default.createDirectory(at: thiscreenDir, withIntermediateDirectories: true, attributes: nil)
        print("[CaptureManager] Created default save directory: \(thiscreenDir.path)")
      } catch {
        print("[CaptureManager] Error creating directory: \(error)")
        return nil
      }
    }
    return thiscreenDir
  }

  /// Returns the default video save directory (~/Movies/THISCREEN), creating it if needed
  static func getDefaultVideoSaveDirectory() -> URL? {
    guard let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first else {
      return nil
    }
    let thiscreenDir = moviesDir.appendingPathComponent(defaultFolderName, isDirectory: true)

    // Create directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: thiscreenDir.path) {
      do {
        try FileManager.default.createDirectory(at: thiscreenDir, withIntermediateDirectories: true, attributes: nil)
        print("[CaptureManager] Created default video save directory: \(thiscreenDir.path)")
      } catch {
        print("[CaptureManager] Error creating video directory: \(error)")
        return nil
      }
    }
    return thiscreenDir
  }

    init() {
        // Ensure default directory exists on init
        _ = CaptureManager.getDefaultSaveDirectory()
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

        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerRecordSelectedArea"), object: nil, queue: .main) { [weak self] _ in
            self?.startRecording(mode: .selectedArea)
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
    // -i: interactive mode (area selection)
    // -r: don't add screen dpi metadata
    // -t: format
    // -C: capture the cursor
    process.arguments = ["-i", "-r", "-C", "-t", "png", tempUrl.path]

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

    // Check macOS version for native video recording support
    // screencapture -v requires macOS 14.0 or later
    if #available(macOS 14.0, *) {
      startNativeRecording(mode: mode, includeMic: includeMic, showClicks: showClicks)
    } else {
      // Show error for older macOS versions
      DispatchQueue.main.async {
        self.showRecordingError("Video recording requires macOS 14.0 or later. Please upgrade your macOS version to use screen recording.")
      }
    }
  }
  
    @available(macOS 14.0, *)
    private func startNativeRecording(mode: RecordingMode, includeMic: Bool, showClicks: Bool) {
        // For selected area mode, show the area selector first
        if mode == .selectedArea {
            DispatchQueue.main.async {
                AreaSelectorWindowController.shared.showAreaSelector(
                    includeMic: includeMic,
                    showClicks: showClicks
                ) { [weak self] selectedRect in
                    guard let self = self else { return }
                    if let rect = selectedRect {
                        self.startRecordingInRect(rect, includeMic: includeMic, showClicks: showClicks)
                    } else {
                        // User cancelled
                        self.isInProgress = false
                        self.bringToFront()
                    }
                }
            }
            return
        }

        // For full screen mode, proceed directly
        startFullScreenRecording(includeMic: includeMic, showClicks: showClicks)
    }

    @available(macOS 14.0, *)
    private func startFullScreenRecording(includeMic: Bool, showClicks: Bool) {
        isInProgress = true
        print("[CaptureManager] Starting native screen recording (full screen)")

        // Use -v (lowercase) for continuous video recording (macOS 14+)
        var args = ["-v"]

        if showClicks { args.append("-k") }
        if includeMic { args.append("-g") }

        let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("THISCREEN_recording.mov")
        try? FileManager.default.removeItem(at: videoUrl)

        args.append(videoUrl.path)

        print("[CaptureManager] screencapture arguments: \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args

        // Capture stderr for debugging
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        // Hide app before recording - wait for hide to complete
        DispatchQueue.main.async {
            print("[CaptureManager] Hiding app before recording")
            NSApp.hide(nil)

            // Small delay to ensure app is fully hidden before starting recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeRecording(process: process, videoUrl: videoUrl, stderrPipe: stderrPipe)
            }
        }
    }

    @available(macOS 14.0, *)
    private func startRecordingInRect(_ rect: CGRect, includeMic: Bool, showClicks: Bool) {
        isInProgress = true
        print("[CaptureManager] Starting native screen recording in rect: \(rect)")

        // Use -v (lowercase) for continuous video recording (macOS 14+)
        // -R flag specifies the capture rectangle: x,y,width,height
        var args = ["-v"]

        // Add the rectangle parameter
        let rectString = "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width)),\(Int(rect.size.height))"
        args.append("-R")
        args.append(rectString)

        if showClicks { args.append("-k") }
        if includeMic { args.append("-g") }

        let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("THISCREEN_recording.mov")
        try? FileManager.default.removeItem(at: videoUrl)

        args.append(videoUrl.path)

        print("[CaptureManager] screencapture arguments: \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args

        // Capture stderr for debugging
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        // Hide app before recording - wait for hide to complete
        DispatchQueue.main.async {
            print("[CaptureManager] Hiding app before recording")
            NSApp.hide(nil)

            // Small delay to ensure app is fully hidden before starting recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeRecording(process: process, videoUrl: videoUrl, stderrPipe: stderrPipe)
            }
        }
    }
  
  private func showRecordingError(_ message: String) {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "Recording Error"
      alert.informativeText = message
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  private func executeRecording(process: Process, videoUrl: URL, stderrPipe: Pipe? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        DispatchQueue.main.async {
          self.isRecording = true
          self.activeRecordingProcess = process
          print("[CaptureManager] Recording process started")
        }

        // Set up termination handler to capture exit code
        process.terminationHandler = { proc in
          print("[CaptureManager] Recording process terminated with exit code: \(proc.terminationStatus)")
        }

        try process.run()
        process.waitUntilExit()

        // Read stderr output for debugging
        var stderrOutput = ""
        if let stderrPipe = stderrPipe {
          let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
          stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
          if !stderrOutput.isEmpty {
            print("[CaptureManager] screencapture stderr: \(stderrOutput)")
          }
        }

        let videoPath = videoUrl.path
        let videoExists = FileManager.default.fileExists(atPath: videoPath)
        let exitCode = process.terminationStatus
        print("[CaptureManager] Recording completed, file exists: \(videoExists), exit code: \(exitCode)")

        DispatchQueue.main.async {
          self.isRecording = false
          self.isInProgress = false
          self.activeRecordingProcess = nil

          if videoExists && exitCode == 0 {
            // Auto-save to ~/Movies/THISCREEN/
            self.autoSaveVideo(from: videoUrl)
          } else {
            // Show error if recording failed with more details
            var errorMessage = "Screen recording failed"
            if exitCode != 0 {
              errorMessage = "Screen recording failed with exit code \(exitCode)."
              if !stderrOutput.isEmpty {
                errorMessage += "\n\nDetails: \(stderrOutput)"
              } else {
                errorMessage += "\n\nPlease check Screen Recording permissions in System Settings > Privacy & Security > Screen Recording."
              }
            } else {
              errorMessage = "Recording file was not created. Please try again."
            }
            self.showRecordingError(errorMessage)
          }
          self.bringToFront()
        }
      } catch {
        print("[CaptureManager] Recording error: \(error)")
        DispatchQueue.main.async {
          self.isRecording = false
          self.isInProgress = false
          self.activeRecordingProcess = nil
          self.showRecordingError("Failed to start recording: \(error.localizedDescription)")
          self.bringToFront()
        }
      }
    }
  }

  /// Automatically saves the recorded video to ~/Movies/THISCREEN/
  private func autoSaveVideo(from tempUrl: URL) {
    guard let videoDir = CaptureManager.getDefaultVideoSaveDirectory() else {
      // Fallback: show save dialog if we can't create/access the directory
      self.screenshot = nil
      self.lastVideoUrl = tempUrl
      NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSaveVideo"), object: nil)
      return
    }

    // Generate filename with timestamp
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = formatter.string(from: Date())
    let filename = "THISCREEN_Recording_\(timestamp).mov"
    let destUrl = videoDir.appendingPathComponent(filename)

    // Copy the video file
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try FileManager.default.copyItem(at: tempUrl, to: destUrl)
        print("[CaptureManager] Video auto-saved to: \(destUrl.path)")

        DispatchQueue.main.async {
          self.screenshot = nil
          self.lastVideoUrl = destUrl
          // Show the saved video in the UI
          NotificationCenter.default.post(name: NSNotification.Name("TriggerShowWindow"), object: nil)
          // Show notification to user
          self.showSaveNotification("Video guardado en Movies/THISCREEN/\(filename)")
        }
      } catch {
        print("[CaptureManager] Error auto-saving video: \(error)")
        DispatchQueue.main.async {
          // Fallback: show save dialog
          self.screenshot = nil
          self.lastVideoUrl = tempUrl
          NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSaveVideo"), object: nil)
        }
      }
    }
  }

  private func showSaveNotification(_ message: String) {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "Grabación Guardada"
      alert.informativeText = message
      alert.alertStyle = .informational
      alert.addButton(withTitle: "OK")
      alert.addButton(withTitle: "Abrir Carpeta")

      let response = alert.runModal()
      if response == .alertSecondButtonReturn {
        // Open the Movies/THISCREEN folder
        if let videoDir = CaptureManager.getDefaultVideoSaveDirectory() {
          NSWorkspace.shared.open(videoDir)
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
