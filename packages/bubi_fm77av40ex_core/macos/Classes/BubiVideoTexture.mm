#import "BubiVideoTexture.h"

#import <CoreVideo/CoreVideo.h>

#include "bubi_fm77av.h"

@implementation BubiVideoTexture {
  bfm_session* _session;
  CVPixelBufferRef _cached;
}

- (instancetype)initWithSessionAddress:(int64_t)address
{
  self = [super init];
  if (self != nil) {
    _session = reinterpret_cast<bfm_session*>(static_cast<intptr_t>(address));
    _cached = NULL;
  }
  return self;
}

- (void)dealloc
{
  if (_cached != NULL) {
    CVPixelBufferRelease(_cached);
    _cached = NULL;
  }
}

- (uint64_t)publishedGeneration
{
  return bfm_video_generation(_session);
}

/*
 * raster thread から同期で呼ばれる。ここで Core thread を待ってはならない。
 * bfm_acquire_video_frame は待たない作りになっている。
 */
- (CVPixelBufferRef _Nullable)copyPixelBuffer
{
  bfm_video_frame frame = {};
  if (bfm_acquire_video_frame(_session, &frame) != BFM_OK || frame.pixels == NULL ||
      frame.width == 0 || frame.height == 0) {
    // まだ1枚もない。前に作った面があればそれを返す。
    return (_cached != NULL) ? CVPixelBufferRetain(_cached) : NULL;
  }

  const size_t width = frame.width;
  const size_t height = frame.height;

  CVPixelBufferRef buffer = NULL;
  NSDictionary* attrs = @{(NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}};
  // コアの scrntype_t は _RGB888 の uint32（(r<<16)|(g<<8)|b）。
  // リトルエンディアンでは記憶上のバイト並びが B,G,R,A となり、
  // 32BGRA と一致する。入れ替えは要らない（design.md 16.1）。
  const CVReturn created =
      CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                          (__bridge CFDictionaryRef)attrs, &buffer);
  if (created != kCVReturnSuccess || buffer == NULL) {
    bfm_release_video_frame(_session, frame.generation);
    return NULL;
  }

  CVPixelBufferLockBaseAddress(buffer, 0);
  uint8_t* destination = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(buffer));
  if (destination != NULL) {
    const size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    const size_t row_bytes = width * sizeof(uint32_t);
    // CVPixelBuffer の行はこちらの幅より広いことがある。行ごとに写す。
    for (size_t y = 0; y < height; ++y) {
      memcpy(destination + y * stride, frame.pixels + y * width, row_bytes);
    }
  }
  CVPixelBufferUnlockBaseAddress(buffer, 0);

  bfm_release_video_frame(_session, frame.generation);

  if (_cached != NULL) {
    CVPixelBufferRelease(_cached);
  }
  _cached = CVPixelBufferRetain(buffer);
  return buffer;
}

@end
