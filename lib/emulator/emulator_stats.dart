/// コア境界の観測値。UIには出さず、テストと診断で使う。
class EmulatorStats {
  const EmulatorStats({
    required this.framesRun,
    required this.commandsAccepted,
    required this.commandsRejected,
    required this.eventsDropped,
    required this.vmAccessViolations,
    required this.framesPublished,
    required this.framesDropped,
    required this.audioFramesProduced,
    required this.audioUnderrunFrames,
    required this.audioOverrunFrames,
  });

  final int framesRun;
  final int commandsAccepted;

  /// キュー飽和で拒否したコマンド数。
  final int commandsRejected;

  /// UIの遅れで捨てた古いイベント数。
  final int eventsDropped;

  /// Core thread 以外から VM 操作境界へ入った回数。常に 0 でなければならない。
  final int vmAccessViolations;

  /// 描画側へ公開したフレーム数。画面が変わらないフレームは数えない（VID-07）。
  final int framesPublished;

  /// 書ける面が尽きて捨てたフレーム数。
  final int framesDropped;

  /// Core threadが取り出したPCMフレーム数の累計（design.md 7）。
  final int audioFramesProduced;

  /// 音声読出しが無音で埋めたフレーム数の累計。
  final int audioUnderrunFrames;

  /// 音声の読み手が追いつかず最古から捨てたフレーム数の累計。
  final int audioOverrunFrames;
}
