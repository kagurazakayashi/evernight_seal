# 專案層級設定。
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 應用程式產生的執行檔名稱。變更此值即可變更
# 磁碟上的應用程式名稱。
set(BINARY_NAME "evernight_seal")
# 此應用程式的唯一 GTK 應用程式識別碼。請參閱：
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "moe.yashi.evernight_seal")

# 明確選擇使用現代的 CMake 行為，以避免使用較新
# 版本的 CMake 時出現警告。
cmake_policy(SET CMP0063 NEW)

# 從相對於執行檔的 lib/ 目錄載入捆綁的函式庫。
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# 用於跨平台建置的根檔案系統。
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# 定義建置設定選項。
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# 應套用至大多數目標的編譯設定。
#
# 在此處新增選項時請謹慎，因為外掛預設會使用此函式。
# 在多數情況下，您應將新選項新增至特定目標，而非
# 修改此函式。
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter 函式庫與工具建置規則。
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# 系統層級相依性。
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# 應用程式建置；請參閱 runner/CMakeLists.txt。
add_subdirectory("runner")

# 執行建置中的 Flutter 工具部分。此處不可移除。
add_dependencies(${BINARY_NAME} flutter_assemble)

# 僅有安裝產生的捆綁包中的執行檔副本才能正確啟動，
# 因為資源必須位於正確的相對位置。為避免
# 使用者嘗試執行未捆綁的副本，將其放在子目錄中，
# 而非預設的頂層位置。
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# 產生的外掛建置規則，用於管理外掛的建置及
# 將外掛新增至應用程式。
include(flutter/generated_plugins.cmake)


# === Installation ===
# 預設情況下，「安裝」僅會在建置目錄中建立一個可重定位的捆綁包。
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# 每次都從乾淨的建置捆綁目錄開始。
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# 從所有套件複製由 build.dart 提供的原生資源。
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# 每次建置時完全重新複製資源目錄，以避免遺留前一次安裝的過時檔案。
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# 僅在非 Debug 建置時安裝 AOT 函式庫。
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
