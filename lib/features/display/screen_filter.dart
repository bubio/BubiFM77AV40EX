/// ホスト側のRGBフィルター選択（VID-04）。
///
/// `Host > Screen > Filter`のラジオ項目に対応する
/// （design.md 12.2。走査線は別項目`Device > Display > Scanline`で扱い、
/// ここには含めない）。
enum HostScreenFilter {
  /// フィルターなし。
  none,

  /// RGBサブピクセルを強調するCRT風フィルター。
  rgb,
}
