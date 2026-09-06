/// メインウィンドウのフルスクリーン状態の境界（VID-03、design.md 3.1）。
///
/// [AppDataPaths]/[ExternalFileAccess]と同じく、feature層はこの抽象だけを
/// 知り、実体（`bubi_fm77av40ex_platform`のOSチャンネル）は`app`が
/// 差し込む。
abstract interface class WindowChrome {
  /// このOSでフルスクリーン制御を扱えるか。
  Future<bool> get isSupported;

  /// 現在メインウィンドウがフルスクリーンかどうか。
  Future<bool> isFullScreen();

  /// フルスクリーンを切り替える。
  ///
  /// 実際の状態反映は[fullScreenChanges]の通知を待つ
  /// （design.md 12.3「チェック項目はコマンド完了後の実状態を表示する」）。
  Future<void> setFullScreen(bool value);

  /// フルスクリーン状態の変化（OS操作による変化を含む）。
  Stream<bool> get fullScreenChanges;
}
