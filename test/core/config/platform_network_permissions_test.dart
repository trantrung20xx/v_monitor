// Xác nhận manifest/entitlement production cho phép REST, WebSocket và tile bản đồ ra ngoài.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release declares Internet access', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason: 'Quyền mạng phải nằm trong main manifest để có ở bản release.',
    );
  });

  for (final fileName in const [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    test('$fileName allows outbound network connections', () async {
      final entitlements = await File(fileName).readAsString();

      expect(
        entitlements,
        contains('com.apple.security.network.client'),
        reason: 'Ứng dụng macOS sandbox cần quyền kết nối mạng ra bên ngoài.',
      );
    });
  }
}
