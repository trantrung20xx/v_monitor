cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Target runner dùng BINARY_NAME từ CMake cấp trên; thêm source native mới vào danh sách này.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Áp dụng bộ compiler option chuẩn của dự án.
apply_standard_settings(${BINARY_NAME})

# Truyền phiên bản Flutter/pubspec thành macro để tài nguyên Windows đọc được.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Tắt macro min/max của Windows để không xung đột thư viện chuẩn C++.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Liên kết Flutter wrapper, DWM theme API và thư mục header của dự án.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Buộc Flutter assemble hoàn tất trước runner; không xóa dependency này.
add_dependencies(${BINARY_NAME} flutter_assemble)
