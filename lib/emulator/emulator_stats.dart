/// コア境界の観測値。UIには出さず、テストと診断で使う。
class EmulatorStats {
  const EmulatorStats({
    required this.framesRun,
    required this.commandsAccepted,
    required this.commandsRejected,
    required this.eventsDropped,
    required this.vmAccessViolations,
  });

  final int framesRun;
  final int commandsAccepted;

  /// キュー飽和で拒否したコマンド数。
  final int commandsRejected;

  /// UIの遅れで捨てた古いイベント数。
  final int eventsDropped;

  /// Core thread 以外から VM 操作境界へ入った回数。常に 0 でなければならない。
  final int vmAccessViolations;
}
