#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Gắn console của tiến trình cha khi chạy bằng Flutter; nếu đang debug thì tạo console mới.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Khởi tạo COM theo apartment thread để thư viện và plugin Windows có thể sử dụng.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Project đọc Flutter assets/AOT từ thư mục data đi kèm tệp thực thi.
  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Vị trí và kích thước ban đầu được Win32Window scale theo DPI màn hình.
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"v_monitor", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Message loop chuyển sự kiện bàn phím, chuột và cửa sổ cho Win32/Flutter xử lý.
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
