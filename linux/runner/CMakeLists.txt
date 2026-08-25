cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Target runner dùng BINARY_NAME từ CMake cấp trên; thêm source native mới vào đây.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Áp dụng bộ compiler option chuẩn của dự án.
apply_standard_settings(${BINARY_NAME})

# Truyền GTK application ID vào source dưới dạng macro.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Liên kết Flutter engine và GTK; dependency native riêng được thêm tại nhóm này.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
