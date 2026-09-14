/// ホスト側のRGBフィルター選択（VID-04）。
///
/// `Host > Screen > Filter`のラジオ項目に対応する
/// （design.md 12.2。走査線は別項目`Device > Display > Scanline`で扱い、
/// ここには含めない）。
enum HostScreenFilter {
  /// フィルターなし。
  none,

  /// 移植元の`apply_rgb_filter_to_screen_buffer`と同じRGBフィルター
  /// （ネイティブ側の`native/bridge/src/rgb_filter.cpp`が掛ける）。
  rgb,
}
