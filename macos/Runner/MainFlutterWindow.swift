import Cocoa
import FlutterMacOS

// Cửa sổ native chứa FlutterViewController và đăng ký plugin macOS.
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Giữ nguyên kích thước do storyboard cấu hình khi thay content bằng Flutter.
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
