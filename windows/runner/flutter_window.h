#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// Cửa sổ native chỉ chịu trách nhiệm chứa một Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Tạo cửa sổ chạy DartProject được truyền vào.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Các hook vòng đời và message handler kế thừa từ Win32Window.
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Project chứa cấu hình và đối số entrypoint Dart cần chạy.
  flutter::DartProject project_;

  // Controller sở hữu Flutter engine và native view nằm trong cửa sổ.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
