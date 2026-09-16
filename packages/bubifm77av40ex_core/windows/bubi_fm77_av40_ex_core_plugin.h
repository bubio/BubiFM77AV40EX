#ifndef BUBIFM77AV40EX_CORE_BUBI_FM77_AV40_EX_CORE_PLUGIN_H_
#define BUBIFM77AV40EX_CORE_BUBI_FM77_AV40_EX_CORE_PLUGIN_H_

/*
 * 映像の受け渡しだけを担うプラグイン（macOSの BubiFm77Av40ExCorePlugin.swift
 * と同じ役割）。
 *
 * エミュレーターのライフサイクルは Dart 側の FFI が持つ。ここは
 * bfm_session* を受け取り、Texture として登録・解除するだけとする。
 * 破棄の順序は「Texture解放、セッション破棄」である（design.md 5.1）。
 */

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <optional>

#include "bubi_video_texture.h"

namespace bubifm77av40ex_core {

class BubiFm77Av40ExCorePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit BubiFm77Av40ExCorePlugin(flutter::PluginRegistrarWindows* registrar);
  ~BubiFm77Av40ExCorePlugin() override;

  BubiFm77Av40ExCorePlugin(const BubiFm77Av40ExCorePlugin&) = delete;
  BubiFm77Av40ExCorePlugin& operator=(const BubiFm77Av40ExCorePlugin&) = delete;

 private:
  struct Entry {
    std::shared_ptr<BubiVideoTexture> texture;
    uint64_t last_notified = 0;
  };

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                          LPARAM lparam);

  void StartTimerIfNeeded();
  void StopTimerIfIdle();
  void NotifyChangedFrames();
  void UnregisterEntry(int64_t id, Entry& entry);

  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* textures_;
  std::map<int64_t, Entry> entries_;
  int window_proc_id_ = -1;
  HWND timer_window_ = nullptr;
};

}  // namespace bubifm77av40ex_core

#endif  // BUBIFM77AV40EX_CORE_BUBI_FM77_AV40_EX_CORE_PLUGIN_H_
