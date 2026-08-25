#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// Lớp nền cửa sổ Win32 nhận biết DPI, cho phép lớp con tùy biến render và input.
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Tạo cửa sổ theo title/origin/size trên màn hình mặc định, tự scale theo DPI.
  // Cửa sổ chỉ hiện sau Show và trả false nếu Win32 không tạo được handle.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Hiện cửa sổ hiện tại và trả kết quả từ Win32.
  bool Show();

  // Giải phóng tài nguyên hệ điều hành gắn với cửa sổ.
  void Destroy();

  // Gắn native handle content làm cửa sổ con và cho nó lấp đầy vùng client.
  void SetChildContent(HWND content);

  // Trả HWND để cấu hình thuộc tính native; trả nullptr sau khi cửa sổ bị hủy.
  HWND GetHandle();

  // Nếu true, đóng cửa sổ sẽ phát message thoát toàn ứng dụng.
  void SetQuitOnClose(bool quit_on_close);

  // Trả RECT giới hạn vùng nội dung hiện tại.
  RECT GetClientArea();

 protected:
  // Phân luồng message chuột, kích thước và DPI; lớp con có thể override để xử lý thêm.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Hook sau khi tạo HWND; lớp con trả false nếu khởi tạo nội dung thất bại.
  virtual bool OnCreate();

  // Hook dọn dẹp trước khi Destroy giải phóng HWND.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // Callback tĩnh của message loop: gắn instance ở WM_NCCREATE, bật scale DPI vùng
  // ngoài client và chuyển các message còn lại sang MessageHandler của instance.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Lấy lại con trỏ instance đã gắn vào HWND.
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Đồng bộ giao diện khung cửa sổ với theme ứng dụng của Windows.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // Handle của cửa sổ cấp cao nhất.
  HWND window_handle_ = nullptr;

  // Handle nội dung native được chứa bên trong.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
