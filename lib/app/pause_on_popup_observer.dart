import 'package:flutter/widgets.dart';

/// ダイアログやアラートなどの[PopupRoute]を表示している間、[acquirePause]で
/// エミュレーターを一時停止させる。
///
/// `showDialog`の呼出し元ごとに一時停止を書かず、Navigatorの出入りで
/// まとめて扱う。ダイアログから確認ダイアログを重ねても、表示中の
/// [PopupRoute]ごとに要求を持つため、最後の1つが閉じるまで再開しない。
class PauseOnPopupObserver extends NavigatorObserver {
  PauseOnPopupObserver({required this.acquirePause});

  /// 一時停止を求め、その要求を取り下げる関数を返す。
  final VoidCallback Function() acquirePause;

  final Map<Route<dynamic>, VoidCallback> _releases = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _untrack(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _untrack(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _untrack(oldRoute);
    }
    if (newRoute != null) {
      _track(newRoute);
    }
  }

  void _track(Route<dynamic> route) {
    if (route is! PopupRoute || _releases.containsKey(route)) {
      return;
    }
    _releases[route] = acquirePause();
  }

  void _untrack(Route<dynamic> route) {
    _releases.remove(route)?.call();
  }
}
