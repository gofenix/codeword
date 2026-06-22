import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Cap how small the window can shrink — anything narrower than
    // 900px and the phone-shaped content starts looking broken.
    self.minSize = NSSize(width: 900, height: 640)

    super.awakeFromNib()
  }
}
