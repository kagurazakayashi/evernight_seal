#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// 為處理程序建立主控台，並將 stdout 和 stderr 重新導向至該主控台，
// 供 runner 和 Flutter 程式庫兩者使用。
void CreateAndAttachConsole();

// 接收一個以 null 結尾、UTF-16 編碼的 wchar_t*，並回傳一個 UTF-8 編碼的
// std::string。失敗時回傳空的 std::string。
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// 取得以 std::vector<std::string> 傳入、UTF-8 編碼的命令列引數。
// 失敗時回傳空的 std::vector<std::string>。
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
