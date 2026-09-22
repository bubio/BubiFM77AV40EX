#include "bubi_video_texture.h"

#include <atomic>
#include <mutex>
#include <vector>

namespace {

// GObjectのインスタンス構造体はゼロ埋めで確保され、C++のコンストラクタは
// 走らない。C++のメンバーはここへまとめ、init/finalizeで明示的に
// 構築・破棄する。
struct TextureState {
  // session の書換え（detach）と世代の読取り（published_generation）は
  // どちらもplatform threadで行う。raster threadの複製は mutex の下で
  // 読むため、detach は mutex を取って複製の終了を待つ。
  // published_generation は mutex を取らない。取ると、複製の間（面全体の
  // 入れ替え）GTKのメインループが待たされる。
  std::mutex mutex;
  std::atomic<bfm_session*> session{nullptr};

  // 返した面は、テクスチャの登録解除が終わるまで解放しない
  // （FlPixelBufferTexture::copy_pixels の契約）。エンジンは複製の直後に
  // 同じraster threadで転送を終えるため、次の copy_pixels までは
  // 書き換えない。
  std::vector<uint8_t> pixels;
  uint32_t width = 0;
  uint32_t height = 0;
};

}  // namespace

struct _BubiVideoTexture {
  FlPixelBufferTexture parent_instance;
  TextureState* state;
};

G_DEFINE_TYPE(BubiVideoTexture,
              bubi_video_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean bubi_video_texture_copy_pixels(FlPixelBufferTexture* texture,
                                               const uint8_t** out_buffer,
                                               uint32_t* out_width,
                                               uint32_t* out_height,
                                               GError** error) {
  TextureState* state = BUBI_VIDEO_TEXTURE(texture)->state;
  std::lock_guard<std::mutex> lock(state->mutex);

  bfm_session* session = state->session.load();
  bfm_video_frame frame = {};
  if (session != nullptr &&
      bfm_acquire_video_frame(session, &frame) == BFM_OK &&
      frame.pixels != nullptr && frame.width != 0 && frame.height != 0) {
    const size_t count = static_cast<size_t>(frame.width) * frame.height;
    state->pixels.resize(count * 4);

    // コアの面は uint32 の (a<<24)|(r<<16)|(g<<8)|b で、リトルエンディアンの
    // 記憶上の並びは B,G,R,A。FlPixelBufferTexture は R,G,B,A を求める
    // ため、BとRを入れ替える。アルファはブリッジが0xffを埋めてある。
    const uint8_t* source = reinterpret_cast<const uint8_t*>(frame.pixels);
    uint8_t* destination = state->pixels.data();
    for (size_t i = 0; i < count; ++i) {
      destination[0] = source[2];
      destination[1] = source[1];
      destination[2] = source[0];
      destination[3] = source[3];
      source += 4;
      destination += 4;
    }
    state->width = frame.width;
    state->height = frame.height;

    // 複製が済んだらすぐ返す。描画側の都合でコアの面の再利用を止めない。
    bfm_release_video_frame(session, frame.generation);
  }

  if (state->pixels.empty()) {
    // まだ1枚もない。
    g_set_error_literal(error, g_quark_from_static_string("bubi_video_texture"),
                        0, "no video frame yet");
    return FALSE;
  }

  // 新しい面が取れなかった場合（未更新、detach後）は前の面を返す。
  *out_buffer = state->pixels.data();
  *out_width = state->width;
  *out_height = state->height;
  return TRUE;
}

static void bubi_video_texture_finalize(GObject* object) {
  BubiVideoTexture* self = BUBI_VIDEO_TEXTURE(object);
  delete self->state;
  self->state = nullptr;
  G_OBJECT_CLASS(bubi_video_texture_parent_class)->finalize(object);
}

static void bubi_video_texture_class_init(BubiVideoTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      bubi_video_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = bubi_video_texture_finalize;
}

static void bubi_video_texture_init(BubiVideoTexture* self) {
  self->state = new TextureState();
}

BubiVideoTexture* bubi_video_texture_new(bfm_session* session) {
  auto* self = BUBI_VIDEO_TEXTURE(
      g_object_new(bubi_video_texture_get_type(), nullptr));
  self->state->session.store(session);
  return self;
}

uint64_t bubi_video_texture_published_generation(BubiVideoTexture* self) {
  // detach と同じplatform threadから呼ばれるため、読んだ値がこの呼出しの
  // 途中で無効になることはない。bfm_video_generation はロックを取らない。
  bfm_session* session = self->state->session.load();
  return session != nullptr ? bfm_video_generation(session) : 0;
}

void bubi_video_texture_detach(BubiVideoTexture* self) {
  std::lock_guard<std::mutex> lock(self->state->mutex);
  self->state->session.store(nullptr);
}
