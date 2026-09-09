/*
 * コアの画面を Flutter の Texture へ渡す（design.md 16.1
 * 「映像の受け渡しとmacOS Texture方式」）。
 *
 * このヘッダーは pod の umbrella header に載るため、C ABI の
 * bubi_fm77av.h を取り込まない。取り込むと、pod を使う側（アプリ本体）の
 * モジュール解決でも探索パスが要ることになり、そこまでは届かない。
 * C ABI に触れるのは実装（.mm）だけとする。
 */
#import <FlutterMacOS/FlutterMacOS.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BubiVideoTexture : NSObject <FlutterTexture>

/// `bfm_session*` のアドレスを受け取る。所有はしない。
- (instancetype)initWithSessionAddress:(int64_t)address NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 公開されている最新の世代。0なら1枚もない。
/// 変化を見てから通知するために使う（VID-07）。
@property(nonatomic, readonly) uint64_t publishedGeneration;

@end

NS_ASSUME_NONNULL_END
