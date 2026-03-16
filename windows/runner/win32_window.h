#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// 一個高 DPI 感知 Win32 視窗的類別抽象。預期由需要自訂
// 渲染與輸入處理的類別來繼承
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

  // 建立一個 win32 視窗，以 |origin| 和 |size| 設定標題、位置與尺寸。
  // 新視窗建立於預設監視器上。視窗尺寸以實際像素指定給作業系統，
  // 因此為確保一致的尺寸，此函式會根據預設監視器適當地縮放傳入的
  // 寬度與高度。視窗在呼叫 |Show| 之前為不可見。
  // 若視窗建立成功則回傳 true。
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // 顯示目前視窗。若視窗成功顯示則回傳 true。
  bool Show();

  // 釋放與視窗相關的作業系統資源。
  void Destroy();

  // 將 |content| 插入視窗樹中。
  void SetChildContent(HWND content);

  // 回傳底層視窗控制代碼，以便用戶端設定圖示與其他視窗屬性。
  // 若視窗已被銷毀則回傳 nullptr。
  HWND GetHandle();

  // 若為 true，關閉此視窗將會結束應用程式。
  void SetQuitOnClose(bool quit_on_close);

  // 回傳一個 RECT，代表目前用戶端區域的邊界。
  RECT GetClientArea();

 protected:
  // 處理並路由滑鼠處理、尺寸變更和 DPI 等重要視窗訊息。
  // 將這些訊息的處理委派給可被繼承類別覆寫的成員函式。
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // 當呼叫 CreateAndShow 時被呼叫，允許子類別進行視窗相關設定。
  // 若設定失敗，子類別應回傳 false。
  virtual bool OnCreate();

  // 當呼叫 Destroy 時被呼叫。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // 由訊息泵呼叫的作業系統回呼。處理 WM_NCCREATE 訊息，
  // 該訊息在非用戶端區域建立時傳遞，並啟用自動非用戶端
  // DPI 縮放，使非用戶端區域能自動回應 DPI 的變更。
  // 所有其他訊息由 MessageHandler 處理。
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // 擷取 |window| 的類別實例指標
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // 更新視窗外框的主題以符合系統主題。
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // 頂層視窗的視窗控制代碼。
  HWND window_handle_ = nullptr;

  // 託管內容的視窗控制代碼。
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
