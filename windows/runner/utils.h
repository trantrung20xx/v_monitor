#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Tạo console và chuyển stdout/stderr của runner lẫn Flutter library vào đó.
void CreateAndAttachConsole();

// Đổi chuỗi wchar_t kết thúc null từ UTF-16 sang UTF-8; trả chuỗi rỗng khi lỗi.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Lấy đối số dòng lệnh và đổi sang UTF-8; trả vector rỗng khi lỗi.
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
