import 'dart:ui';

/// メインウィンドウの表示倍率制御の境界（design.md 12.2 `Host > Screen >
/// Window x1 / x2 / …`）。
///
/// [WindowChrome]と同じく、feature層はこの抽象だけを知り、実体
/// （window_manager/screen_retrieverパッケージ）は`app`が差し込む
/// （design.md 3.1）。
abstract interface class WindowScale {
  /// このOSでウィンドウサイズ変更を扱えるか（デスクトップのみ）。
  Future<bool> get isSupported;

  /// 現在のウィンドウ内容領域（タイトルバーを除く、映像＋ステータスバー）
  /// のサイズ（論理px）。
  Future<Size> getContentSize();

  /// ウィンドウ内容領域（タイトルバーを除く）のサイズを変える（論理px）。
  Future<void> setContentSize(Size size);

  /// 主ディスプレイの作業領域サイズ（論理px）。倍率の上限決定に使う。
  Future<Size> getAvailableDisplaySize();

  /// ウィンドウサイズの変化（OS操作によるドラッグリサイズを含む）。
  Stream<Size> get contentSizeChanges;

  /// ウィンドウを表示する。
  ///
  /// ネイティブ側は起動直後のxib既定フレームのままの一瞬を見せないよう
  /// ウィンドウを隠して起動する（`macos/Runner/MainFlutterWindow.swift`）。
  /// [WindowScaleController.applyInitialMultiplierIfNeeded]がゲスト画面に
  /// 合わせてリサイズした直後にこれを呼び、初めて表示する
  /// （design.md「Window x1/x2/…の実装方式」）。
  Future<void> show();
}
