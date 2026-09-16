#include "bubi_video_texture.h"

#include <cstring>

namespace bubifm77av40ex_core {

BubiVideoTexture::BubiVideoTexture(bfm_session* session)
    : session_(session),
      buffer_{},
      has_buffer_(false),
      variant_(flutter::PixelBufferTexture(
          [this](size_t width, size_t height) -> const FlutterDesktopPixelBuffer* {
            return CopyPixelBuffer(width, height);
          })) {}

uint64_t BubiVideoTexture::PublishedGeneration() {
  // Detach() と同じplatform threadから呼ばれるため、読んだ値がこの呼出しの
  // 途中で無効になることはない。bfm_video_generation はロックを取らない。
  bfm_session* session = session_.load();
  return session != nullptr ? bfm_video_generation(session) : 0;
}

void BubiVideoTexture::Detach() {
  std::lock_guard<std::mutex> lock(mutex_);
  session_.store(nullptr);
}

const FlutterDesktopPixelBuffer* BubiVideoTexture::CopyPixelBuffer(size_t /*width*/,
                                                                   size_t /*height*/) {
  std::lock_guard<std::mutex> lock(mutex_);
  bfm_session* session = session_.load();
  if (session == nullptr) {
    return has_buffer_ ? &buffer_ : nullptr;
  }

  bfm_video_frame frame = {};
  if (bfm_acquire_video_frame(session, &frame) != BFM_OK || frame.pixels == nullptr ||
      frame.width == 0 || frame.height == 0) {
    // まだ1枚もない。前に作った面があればそれを返す。
    return has_buffer_ ? &buffer_ : nullptr;
  }

  const size_t width = frame.width;
  const size_t height = frame.height;
  const size_t count = width * height;
  pixels_.resize(count * 4);

  // コアの面は uint32 の (a<<24)|(r<<16)|(g<<8)|b で、リトルエンディアンの
  // 記憶上の並びは B,G,R,A。FlutterDesktopPixelBuffer は R,G,B,A を
  // 求めるため、BとRを入れ替える。アルファはブリッジが0xffを埋めてある。
  const uint8_t* source = reinterpret_cast<const uint8_t*>(frame.pixels);
  uint8_t* destination = pixels_.data();
  for (size_t i = 0; i < count; ++i) {
    destination[0] = source[2];
    destination[1] = source[1];
    destination[2] = source[0];
    destination[3] = source[3];
    source += 4;
    destination += 4;
  }

  // 複製が済んだらすぐ返す。描画側の都合でコアの面の再利用を止めない。
  bfm_release_video_frame(session, frame.generation);

  buffer_.buffer = pixels_.data();
  buffer_.width = width;
  buffer_.height = height;
  buffer_.release_callback = nullptr;
  buffer_.release_context = nullptr;
  has_buffer_ = true;
  return &buffer_;
}

}  // namespace bubifm77av40ex_core
