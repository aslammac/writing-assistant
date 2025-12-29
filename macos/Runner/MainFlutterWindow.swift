import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AccessibilityPlugin.register(with: flutterViewController.registrar(forPlugin: "AccessibilityPlugin"))
    
    super.awakeFromNib()
  }

  override var canBecomeKey: Bool {
    return false
  }

  override var canBecomeMain: Bool {
    return false
  }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    super.orderFront(sender)
  }

  override func makeKey() {
    return
  }
}
