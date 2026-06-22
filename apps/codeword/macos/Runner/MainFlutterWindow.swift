import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The window itself is phone-shaped (430×860). Lock the min size so
    // the user can't shrink it into a useless sliver and keep the
    // phone aspect roughly.
    self.minSize = NSSize(width: 400, height: 720)

    super.awakeFromNib()
  }
}
