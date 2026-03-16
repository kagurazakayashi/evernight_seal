cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 定義應用程式目標。如需變更其名稱，請在頂層
# CMakeLists.txt 中變更 BINARY_NAME，而非此處的值，
# 否則 `flutter run` 將不再能正常運作。
#
# 任何您新增至應用程式的新原始碼檔案都應在此處加入。
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# 套用標準的建置設定。對於需要不同建置設定的應用程式，
# 可以移除此段。
apply_standard_settings(${BINARY_NAME})

# 新增應用程式 ID 的前置處理器定義。
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# 新增相依函式庫。在此處新增任何應用程式特定的相依性。
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
