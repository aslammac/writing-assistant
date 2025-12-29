import Cocoa
import FlutterMacOS
import Accessibility

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationDidFinishLaunching(_ notification: Notification) {
        super.applicationDidFinishLaunching(notification)
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay alive for the system tray
    }
}

class AccessibilityPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var observer: AXObserver?
    private var currentFocusedElement: AXUIElement?
    private var currentAppElement: AXUIElement?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.example.writing_assistant/accessibility",
                                           binaryMessenger: registrar.messenger)
        let instance = AccessibilityPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        setupAccessibilityObserver()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("DEBUG: AccessibilityPlugin received call: \(call.method)")
        switch call.method {
        case "checkPermissions":
            result(AXIsProcessTrusted())
        case "openPrivacySettings":
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            result(nil)
        case "injectText":
            if let args = call.arguments as? [String: Any],
               let text = args["text"] as? String {
                self.injectText(text)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing text argument", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setupAccessibilityObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            self.renewObserver()
        }
        renewObserver()
    }

    private func renewObserver() {
        if !AXIsProcessTrusted() { return }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { 
            print("DEBUG: No frontmost application found")
            return 
        }
        let pid = frontmostApp.processIdentifier
        print("DEBUG: Renewing observer for: \(frontmostApp.localizedName ?? "unknown") (pid: \(pid))")
        let appElement = AXUIElementCreateApplication(pid)
        self.currentAppElement = appElement

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            let delegate = Unmanaged<AccessibilityPlugin>.fromOpaque(refcon!).takeUnretainedValue()
            delegate.handleAccessibilityNotification(element: element, notification: notification)
        }, &observer)

        if result == .success, let observer = observer {
            self.observer = observer
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            
            let v1 = AXObserverAddNotification(observer, appElement, kAXValueChangedNotification as CFString, selfPtr)
            let v2 = AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)
            
            print("DEBUG: Observer results: kAXValueChanged=\(v1.rawValue), kAXFocusedUIElementChanged=\(v2.rawValue)")
            
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        } else {
            print("DEBUG: Failed to create observer: \(result.rawValue)")
        }
    }

    private func handleAccessibilityNotification(element: AXUIElement, notification: CFString) {
        if notification == kAXFocusedUIElementChangedNotification as CFString {
            currentFocusedElement = element
        }
        
        if notification == kAXValueChangedNotification as CFString {
            notifyTextChange(element: element)
        }
    }

    private func logElementDetails(_ element: AXUIElement, prefix: String) {
        // Debug helper - removed for production
    }

    private func notifyTextChange(element: AXUIElement) {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard let text = value as? String else { return }

        var rangeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        
        var rect = CGRect.zero
        if let range = rangeValue {
            var boundsValue: AnyObject?
            AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue)
            if let bounds = boundsValue {
                AXValueGetValue(bounds as! AXValue, .cgRect, &rect)
            }
        }

        let data: [String: Any] = [
            "text": text,
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.size.width,
            "height": rect.size.height
        ]
        
        channel?.invokeMethod("onTextChange", arguments: data)
    }

    private func injectText(_ text: String) {
        print("DEBUG: Attempting to inject text: \(text)")
        guard let element = currentFocusedElement ?? getFocusedElement() else {
            print("DEBUG: No focused element found for injection")
            return
        }
        
        print("DEBUG: Injecting into element: \(element)")
        
        // Try setting kAXValueAttribute first
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        print("DEBUG: Injection result (kAXValueAttribute): \(result.rawValue)")
        
        if result != .success {
            print("DEBUG: Falling back to kAXSelectedTextAttribute")
            // Try setting kAXSelectedTextAttribute (common in many fields)
            let fallbackResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            print("DEBUG: Fallback result (kAXSelectedTextAttribute): \(fallbackResult.rawValue)")
            
            if fallbackResult != .success {
                print("DEBUG: Using accessibility keyboard simulation as last resort")
                self.simulateTyping(text)
            }
        }
    }

    private func getFocusedElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if result == .success {
            return (focusedElement as! AXUIElement)
        } else {
             print("DEBUG: System-wide focus failed: \(result.rawValue). Trying app-specific focus.")
            if let appElement = currentAppElement {
                let appResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                if appResult == .success {
                     print("DEBUG: App-specific focus SUCCESS")
                     return (focusedElement as! AXUIElement)
                } else {
                     print("DEBUG: App-specific focus failed: \(appResult.rawValue)")
                }
            } else {
                print("DEBUG: No currentAppElement to try fallback")
            }
        }
        return nil
    }

    private func simulateTyping(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text.utf16 {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            var codeUnit = char
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyDown?.post(tap: .cghidEventTap)
            
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
