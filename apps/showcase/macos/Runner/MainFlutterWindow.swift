import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // A calendar's window: room for the sidebar and a week.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1280, height: 820)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()
    self.minSize = NSSize(width: 480, height: 560)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
