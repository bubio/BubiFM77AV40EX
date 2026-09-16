#ifndef BUBIFM77AV40EX_CORE_BUBI_VIDEO_TEXTURE_H_
#define BUBIFM77AV40EX_CORE_BUBI_VIDEO_TEXTURE_H_

/*
 * コアの画面を Flutter の Texture へ渡す（design.md 16.1
 * 「映像の受け渡しとmacOS Texture方式」のWindows版）。
 *
 * macOSの BubiVideoTexture.mm と同じく「ブリッジが面を所有し、描画側が
 * 借りて複製する」。複製先が CVPixelBuffer（32BGRA）ではなく
 * FlutterDesktopPixelBuffer（RGBA8888固定、形式の指定欄がない）である
 * ため、ここでだけRとBを入れ替える。
 */

#include <flutter/texture_registrar.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

#include "bubi_fm77av.h"

namespace bubifm77av40ex_core {

class BubiVideoTexture {
 public:
  // セッションは所有しない。Detach() より後には触れない。
  explicit BubiVideoTexture(bfm_session* session);

  BubiVideoTexture(const BubiVideoTexture&) = delete;
  BubiVideoTexture& operator=(const BubiVideoTexture&) = delete;

  flutter::TextureVariant* variant() { return &variant_; }

  // 公開されている最新の世代。0なら1枚もない（VID-07）。
  // Detach() 後は0を返す。platform threadから呼ぶ。
  uint64_t PublishedGeneration();

  // 以後セッションへ一切触れないようにする。raster threadで複製中なら
  // それが終わるまで待つ。戻った後はセッションを破棄してよい
  // （design.md 5.1「Texture解放、セッション破棄」の順序）。
  void Detach();

 private:
  // raster threadから同期で呼ばれる。Core threadを待たない
  // （bfm_acquire_video_frame は待たない作り）。
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);

  // session_ の書換え（Detach）と世代の読取り（PublishedGeneration）は
  // どちらもplatform threadで行う。raster threadの複製は mutex_ の下で
  // 読むため、Detach() は mutex_ を取って複製の終了を待つ。
  // PublishedGeneration() は mutex_ を取らない。取ると、複製の間（面全体の
  // 入れ替え）UIスレッドのWM_TIMER処理が待たされる。
  std::mutex mutex_;
  std::atomic<bfm_session*> session_;

  // 返した面は、テクスチャの登録解除が終わるまで解放しない
  // （flutter::PixelBufferTexture の契約）。エンジンは複製の直後に同じ
  // raster threadで転送を終えるため、次の CopyPixelBuffer までは
  // 書き換えない。
  std::vector<uint8_t> pixels_;
  FlutterDesktopPixelBuffer buffer_;
  bool has_buffer_;

  flutter::TextureVariant variant_;
};

}  // namespace bubifm77av40ex_core

#endif  // BUBIFM77AV40EX_CORE_BUBI_VIDEO_TEXTURE_H_
