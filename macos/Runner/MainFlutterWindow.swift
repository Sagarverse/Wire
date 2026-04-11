import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
      appDelegate.setupChannels(with: flutterViewController)
    }

    self.delegate = self
    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    self.orderOut(nil)
    return false
  }
}
