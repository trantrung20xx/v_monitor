import Flutter
import UIKit

// Điểm vào iOS: chuyển vòng đời cho Flutter và đăng ký các plugin đã sinh tự động.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Dùng registry của engine hiện tại để plugin native sẵn sàng trước khi Dart gọi.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
