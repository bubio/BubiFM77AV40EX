#include "include/bubifm77av40ex_platform/bubi_fm77_av40_ex_platform_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>

/*
 * ウィンドウのクライアント領域（枠・タイトルバーを除いた中身）を直接
 * 指定・取得するチャンネル（design.md「x1ウィンドウの大きさの調査」）。
 *
 * `window_manager`の`setSize`/`getSize`はWindowsではタイトルバーに加えて
 * 左右下の（見た目には出ない）リサイズ枠を含むウィンドウ全体の外形を扱い、
 * その大きさを求める公開APIがない。Win32では`AdjustWindowRectExForDpi`へ
 * 望むクライアント領域・ウィンドウスタイル・DPIを渡すことで外形をOSに
 * 計算させるのが標準的な方法であり、これを`SetWindowPos`と組み合わせて
 * 「クライアント領域を指定すればウィンドウの大きさが決まる」体験を作る。
 * macOSは`NSWindow.setContentSize:`で同じことができるため、そちらは
 * 従来どおり`window_manager`のままでよい（このプラグインはWindows専用）。
 *
 * design.mdの「ウィンドウ操作は既製パッケージへ委譲し、自前のネイティブ
 * 実装を増やさない」という原則の例外だが、Win32にクライアント領域を
 * 直接指定する手段がないため、この一点だけ自前実装とする
 * （design.md「x1ウィンドウの大きさの調査」に理由を記録）。
 */

namespace {

constexpr double kBaseDpi = 96.0;

double DpiScale(HWND hwnd) {
  return static_cast<double>(GetDpiForWindow(hwnd)) / kBaseDpi;
}

// クライアント領域の論理px（DPIスケールを除いた、Flutter側の座標系と
// 同じ単位）サイズ。
std::pair<double, double> GetLogicalClientSize(HWND hwnd) {
  RECT client;
  GetClientRect(hwnd, &client);
  const double scale = DpiScale(hwnd);
  return {(client.right - client.left) / scale,
          (client.bottom - client.top) / scale};
}

// 望むクライアント領域（論理px）を得るために必要な、ウィンドウ全体の
// 外形（物理px）。スタイル・メニューの有無・DPIから`AdjustWindowRectExForDpi`
// でOSに計算させる（design.mdのとおり、Windowsにはクライアント領域を
// 直接指定するAPIがないため）。
SIZE ComputeOuterSize(HWND hwnd, double logicalWidth, double logicalHeight) {
  const UINT dpi = GetDpiForWindow(hwnd);
  const double scale = static_cast<double>(dpi) / kBaseDpi;
  RECT rect{0, 0, static_cast<LONG>(std::lround(logicalWidth * scale)),
            static_cast<LONG>(std::lround(logicalHeight * scale))};
  const auto style = static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_STYLE));
  const auto exStyle =
      static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_EXSTYLE));
  AdjustWindowRectExForDpi(&rect, style, GetMenu(hwnd) != nullptr, exStyle,
                           dpi);
  return {rect.right - rect.left, rect.bottom - rect.top};
}

std::optional<double> ReadDouble(const flutter::EncodableMap& map,
                                 const std::string& key) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) {
    return std::nullopt;
  }
  if (const auto* d = std::get_if<double>(&found->second)) {
    return *d;
  }
  if (const auto* i32 = std::get_if<int32_t>(&found->second)) {
    return static_cast<double>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&found->second)) {
    return static_cast<double>(*i64);
  }
  return std::nullopt;
}

flutter::EncodableValue EncodeSize(std::pair<double, double> size) {
  return flutter::EncodableValue(flutter::EncodableList{
      flutter::EncodableValue(size.first),
      flutter::EncodableValue(size.second)});
}

class BubiFm77Av40ExPlatformPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  explicit BubiFm77Av40ExPlatformPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~BubiFm77Av40ExPlatformPlugin() override;

  BubiFm77Av40ExPlatformPlugin(const BubiFm77Av40ExPlatformPlugin&) = delete;
  BubiFm77Av40ExPlatformPlugin& operator=(const BubiFm77Av40ExPlatformPlugin&) =
      delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> size_sink_;
  // 論理px。未設定（nullopt）は最小サイズを課さない。
  std::optional<std::pair<double, double>> minimum_logical_size_;

 private:
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  HWND TopLevelWindow();

  flutter::PluginRegistrarWindows* registrar_;
  int window_proc_id_ = -1;
  std::pair<double, double> last_notified_size_{-1.0, -1.0};
};

void BubiFm77Av40ExPlatformPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "bubifm77av40ex/platform/window_scale",
          &flutter::StandardMethodCodec::GetInstance());
  auto event_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "bubifm77av40ex/platform/window_scale/changes",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<BubiFm77Av40ExPlatformPlugin>(registrar);
  auto* plugin_pointer = plugin.get();

  method_channel->SetMethodCallHandler(
      [plugin_pointer](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto stream_handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_pointer](
          const flutter::EncodableValue* /*arguments*/,
          std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
              events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_pointer->size_sink_ = std::move(events);
        return nullptr;
      },
      [plugin_pointer](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        plugin_pointer->size_sink_.reset();
        return nullptr;
      });
  event_channel->SetStreamHandler(std::move(stream_handler));

  // ハンドラーはmessengerへ登録済みのため、チャンネル自体はここで破棄してよい
  // （`bubi_fm77_av40_ex_core_plugin.cpp`と同じ）。プラグインはregistrarが
  // 所有する。
  registrar->AddPlugin(std::move(plugin));
}

BubiFm77Av40ExPlatformPlugin::BubiFm77Av40ExPlatformPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

BubiFm77Av40ExPlatformPlugin::~BubiFm77Av40ExPlatformPlugin() {
  if (window_proc_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

HWND BubiFm77Av40ExPlatformPlugin::TopLevelWindow() {
  flutter::FlutterView* view = registrar_->GetView();
  if (view == nullptr) {
    return nullptr;
  }
  return GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void BubiFm77Av40ExPlatformPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND hwnd = TopLevelWindow();
  if (hwnd == nullptr) {
    result->Error("noWindow", "ウィンドウがまだありません");
    return;
  }

  if (call.method_name() == "getContentSize") {
    result->Success(EncodeSize(GetLogicalClientSize(hwnd)));
    return;
  }

  if (call.method_name() == "setContentSize" ||
      call.method_name() == "setMinimumContentSize") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const auto width = args ? ReadDouble(*args, "width") : std::nullopt;
    const auto height = args ? ReadDouble(*args, "height") : std::nullopt;
    if (!width.has_value() || !height.has_value()) {
      result->Error("invalidSize", "widthとheightが必要です");
      return;
    }
    if (call.method_name() == "setMinimumContentSize") {
      minimum_logical_size_ = {*width, *height};
      result->Success();
      return;
    }
    const SIZE outer = ComputeOuterSize(hwnd, *width, *height);
    RECT current;
    GetWindowRect(hwnd, &current);
    SetWindowPos(hwnd, nullptr, current.left, current.top, outer.cx, outer.cy,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    result->Success();
    return;
  }

  result->NotImplemented();
}

std::optional<LRESULT> BubiFm77Av40ExPlatformPlugin::HandleWindowProc(
    HWND hwnd, UINT message, WPARAM /*wparam*/, LPARAM lparam) {
  if (message == WM_GETMINMAXINFO && minimum_logical_size_.has_value()) {
    const auto [width, height] = *minimum_logical_size_;
    const SIZE outer = ComputeOuterSize(hwnd, width, height);
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    info->ptMinTrackSize.x = outer.cx;
    info->ptMinTrackSize.y = outer.cy;
    return 0;
  }

  if (message == WM_SIZE) {
    const auto size = GetLogicalClientSize(hwnd);
    if (size_sink_ && size != last_notified_size_) {
      last_notified_size_ = size;
      size_sink_->Success(EncodeSize(size));
    }
    return std::nullopt;
  }

  return std::nullopt;
}

}  // namespace

void BubiFm77Av40ExPlatformPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  BubiFm77Av40ExPlatformPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
