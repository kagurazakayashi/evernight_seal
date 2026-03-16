cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 定義應用程式目標。若要變更其名稱，請修改頂層 CMakeLists.txt 中的
# BINARY_NAME，而非此處的值，否則 `flutter run` 將無法運作。
#
# 任何新增至應用程式的原始檔都應加入於此。
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# 套用標準建置設定組。若應用程式需要不同的建置設定，可移除此區塊。
apply_standard_settings(${BINARY_NAME})

# 為建置版本加入前置處理器定義。
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# 停用與 C++ 標準程式庫函式衝突的 Windows 巨集。
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# 加入相依程式庫與 include 目錄。任何應用程式特定的相依項目請加入於此。
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# 執行建置中的 Flutter 工具部分。此區塊不可移除。
add_dependencies(${BINARY_NAME} flutter_assemble)
