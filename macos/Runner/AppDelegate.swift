import Cocoa
import FlutterMacOS

// Điểm vào macOS và các chính sách vòng đời cửa sổ của ứng dụng Flutter.
@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Đóng cửa sổ cuối cùng sẽ thoát hẳn tiến trình theo hành vi ứng dụng desktop thông thường.
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    // Cho phép macOS khôi phục trạng thái cửa sổ bằng cơ chế mã hóa an toàn.
    return true
  }
}
