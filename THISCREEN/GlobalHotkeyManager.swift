import Foundation
import Carbon
import AppKit

class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerInstalled = false
    
    func setupHotkeys() {
        print("[GlobalHotkeyManager] Setting up hotkeys")

        let cmdShift = UInt32(cmdKey | shiftKey)

    // Ensure the handler is installed once for all hotkeys
    installHandler()

        // Key codes: S = 1, A = 0, T = 17, R = 15
        // ⌘⇧S: Capture Area
        register(keyCode: 1, modifiers: cmdShift, id: 1, notification: "TriggerCapture")
        // ⌘⇧A: Record Screen (full screen)
        register(keyCode: 0, modifiers: cmdShift, id: 4, notification: "TriggerEntireRecord")
        // ⌘⇧R: Record Selected Area
        register(keyCode: 15, modifiers: cmdShift, id: 5, notification: "TriggerRecordSelectedArea")
        // ⌘⇧T: Stop Recording
        register(keyCode: 17, modifiers: cmdShift, id: 3, notification: "TriggerStopRecord")

        print("[GlobalHotkeyManager] Hotkeys setup complete")
    }
    
    private func installHandler() {
        guard !handlerInstalled else { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            hotKeyID.id = 0 // Explicit mutation to avoid warning
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if status == noErr {
                let noteName: String
                switch hotKeyID.id {
                case 1: noteName = "TriggerCapture"
                case 2: noteName = "TriggerRecord"
                case 3: noteName = "TriggerStopRecord"
                case 4: noteName = "TriggerEntireRecord"
                case 5: noteName = "TriggerRecordSelectedArea"
                default: return noErr
                }
                
                print("Hotkey triggered: \(noteName)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name(noteName), object: nil)
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
        
        if status == noErr {
            handlerInstalled = true
        } else {
            print("Error installing global hotkey handler: \(status)")
        }
    }
    
    private func register(keyCode: UInt32, modifiers: UInt32, id: Int, notification: String) {
        let signature = fourCharCode("THSC")
        let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
        var hotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("Error registering hotkey \(notification): \(status)")
        } else {
            print("Successfully registered hotkey \(notification)")
            hotKeyRefs.append(hotKeyRef)
        }
    }
    
    private func fourCharCode(_ string: String) -> OSType {
        var res: UInt32 = 0
        for char in string.utf8.prefix(4) {
            res = (res << 8) | UInt32(char)
        }
        return res
    }
}
