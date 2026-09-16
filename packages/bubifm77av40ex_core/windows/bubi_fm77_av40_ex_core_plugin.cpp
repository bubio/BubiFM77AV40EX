#include "bubi_fm77_av40_ex_core_plugin.h"

#include <utility>
#include <variant>
#include <vector>

namespace bubifm77av40ex_core {

namespace {

// 他のプラグインやランナーと衝突しにくい値にする。SetTimer の ID は
// ウィンドウごとの名前空間であり、トップレベルウィンドウを共有するため。
constexpr UINT_PTR kFrameTimerId = 0x4246'4D37;  // "BFM7"

// macOSの Timer(timeInterval: 1.0 / 60.0) に当たる。WM_TIMER は
// システムのタイマー分解能（既定で約15.6ms）へ丸められる。
constexpr UINT kFrameTimerIntervalMs = 16;

// Dart の int は大きさにより int32_t / int64_t のどちらでも届く。
std::optional<int64_t> ReadInteger(const flutter::EncodableValue* value) {
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* v32 = std::get_if<int32_t>(value)) {
    return static_cast<int64_t>(*v32);
  }
  if (const auto* v64 = std::get_if<int64_t>(value)) {
    return *v64;
  }
  return std::nullopt;
}

}  // namespace

void BubiFm77Av40ExCorePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "bubifm77av40ex/core_video",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<BubiFm77Av40ExCorePlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  // ハンドラーはmessengerへ登録済みのため、チャンネル自体はここで破棄してよい
  // （Flutterのプラグインテンプレートと同じ）。プラグインは registrar が所有する。
  registrar->AddPlugin(std::move(plugin));
}

BubiFm77Av40ExCorePlugin::BubiFm77Av40ExCorePlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar), textures_(registrar->texture_registrar()) {
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

BubiFm77Av40ExCorePlugin::~BubiFm77Av40ExCorePlugin() {
  if (window_proc_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
  if (timer_window_ != nullptr) {
    KillTimer(timer_window_, kFrameTimerId);
    timer_window_ = nullptr;
  }
  if (entries_.empty()) {
    return;
  }
  // Dartがdetachしないまま終了した場合（ウィンドウを閉じた等）。エンジンの
  // 停止処理の途中であり、UnregisterTexture の完了通知が届く保証がない。
  // raster threadが最後の描画でまだテクスチャを読む可能性があるため、
  // セッションとの縁だけを切り、テクスチャ自体は意図的に解放しない
  // （プロセス終了時の小さなリークと引き換えに解放後使用を防ぐ）。
  auto* leaked = new std::vector<std::shared_ptr<BubiVideoTexture>>();
  for (auto& [id, entry] : entries_) {
    entry.texture->Detach();
    leaked->push_back(std::move(entry.texture));
  }
  entries_.clear();
}

void BubiFm77Av40ExCorePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "attach") {
    const std::optional<int64_t> address = ReadInteger(call.arguments());
    if (!address.has_value() || *address == 0) {
      result->Error("invalidSession", "セッションのアドレスが不正です");
      return;
    }
    auto texture = std::make_shared<BubiVideoTexture>(
        reinterpret_cast<bfm_session*>(static_cast<intptr_t>(*address)));
    const int64_t id = textures_->RegisterTexture(texture->variant());
    if (id < 0) {
      result->Error("textureRegistrationFailed", "Textureを登録できませんでした");
      return;
    }
    entries_[id] = Entry{std::move(texture), 0};
    StartTimerIfNeeded();
    result->Success(flutter::EncodableValue(id));
    return;
  }

  if (call.method_name() == "detach") {
    const std::optional<int64_t> id = ReadInteger(call.arguments());
    if (!id.has_value()) {
      result->Error("invalidTextureId", "Texture IDが不正です");
      return;
    }
    auto found = entries_.find(*id);
    if (found != entries_.end()) {
      UnregisterEntry(found->first, found->second);
      entries_.erase(found);
    }
    StopTimerIfIdle();
    result->Success();
    return;
  }

  result->NotImplemented();
}

void BubiFm77Av40ExCorePlugin::UnregisterEntry(int64_t id, Entry& entry) {
  // 先にセッションとの縁を切る。Detach() は複製中なら終わるまで待つため、
  // 戻った時点で raster thread はもうセッションを読まない。Dart は
  // detach の完了を待ってからセッションを破棄する（design.md 5.1）。
  entry.texture->Detach();
  // 返した面は登録解除が終わるまで生かす必要がある。完了通知まで
  // テクスチャの所有を持たせる。
  std::shared_ptr<BubiVideoTexture> keep_alive = entry.texture;
  textures_->UnregisterTexture(id, [keep_alive]() {});
}

std::optional<LRESULT> BubiFm77Av40ExCorePlugin::HandleWindowProc(HWND hwnd, UINT message,
                                                                  WPARAM wparam,
                                                                  LPARAM /*lparam*/) {
  if (message == WM_TIMER && wparam == kFrameTimerId && hwnd == timer_window_) {
    NotifyChangedFrames();
    return 0;
  }
  return std::nullopt;
}

void BubiFm77Av40ExCorePlugin::StartTimerIfNeeded() {
  if (timer_window_ != nullptr) {
    return;
  }
  flutter::FlutterView* view = registrar_->GetView();
  if (view == nullptr) {
    return;
  }
  // WindowProc の委譲はトップレベルウィンドウのメッセージだけが届くため、
  // タイマーもトップレベルウィンドウに設定する。
  HWND root = GetAncestor(view->GetNativeWindow(), GA_ROOT);
  if (root == nullptr) {
    return;
  }
  if (SetTimer(root, kFrameTimerId, kFrameTimerIntervalMs, nullptr) != 0) {
    timer_window_ = root;
  }
}

void BubiFm77Av40ExCorePlugin::StopTimerIfIdle() {
  if (!entries_.empty() || timer_window_ == nullptr) {
    return;
  }
  KillTimer(timer_window_, kFrameTimerId);
  timer_window_ = nullptr;
}

/*
 * 世代が変わったときだけ通知する（VID-07）。
 * 通知しても CopyPixelBuffer が同じ回数呼ばれるとは限らない。
 * エンジンは間引くため、取りこぼす前提で書く。
 */
void BubiFm77Av40ExCorePlugin::NotifyChangedFrames() {
  for (auto& [id, entry] : entries_) {
    const uint64_t generation = entry.texture->PublishedGeneration();
    if (generation != 0 && generation != entry.last_notified) {
      entry.last_notified = generation;
      textures_->MarkTextureFrameAvailable(id);
    }
  }
}

}  // namespace bubifm77av40ex_core
