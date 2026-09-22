#ifndef BUBIFM77AV40EX_CORE_BUBI_VIDEO_TEXTURE_H_
#define BUBIFM77AV40EX_CORE_BUBI_VIDEO_TEXTURE_H_

/*
 * コアの画面を Flutter の Texture へ渡す（design.md 16.1
 * 「映像の受け渡しとmacOS Texture方式」のLinux版）。
 *
 * macOS/Windowsと同じく「ブリッジが面を所有し、描画側が借りて複製する」。
 * 複製先は FlPixelBufferTexture（RGBA固定）であり、Windowsと同じく
 * ここでだけRとBを入れ替える。
 */

#include <flutter_linux/flutter_linux.h>

#include <cstdint>

#include "bubi_fm77av.h"

G_BEGIN_DECLS

G_DECLARE_FINAL_TYPE(BubiVideoTexture,
                     bubi_video_texture,
                     BUBI,
                     VIDEO_TEXTURE,
                     FlPixelBufferTexture)

// セッションは所有しない。bubi_video_texture_detach() より後には触れない。
BubiVideoTexture* bubi_video_texture_new(bfm_session* session);

// 公開されている最新の世代。0なら1枚もない（VID-07）。
// detach後は0を返す。platform threadから呼ぶ。
uint64_t bubi_video_texture_published_generation(BubiVideoTexture* self);

// 以後セッションへ一切触れないようにする。raster threadで複製中なら
// それが終わるまで待つ。戻った後はセッションを破棄してよい
// （design.md 5.1「Texture解放、セッション破棄」の順序）。
void bubi_video_texture_detach(BubiVideoTexture* self);

G_END_DECLS

#endif  // BUBIFM77AV40EX_CORE_BUBI_VIDEO_TEXTURE_H_
