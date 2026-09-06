import 'package:bubi_fm77av40ex/features/display/fullscreen_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeWindowChrome windowChrome;
  late ProviderContainer container;

  setUp(() {
    windowChrome = FakeWindowChrome();
    container = ProviderContainer(
      overrides: [
        fullscreenControllerProvider.overrideWith(
          () => FullscreenController(windowChrome: windowChrome),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('未対応OSでは supported が false のまま', () async {
    windowChrome.supported = false;
    container.read(fullscreenControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(fullscreenControllerProvider);
    expect(state.supported, isFalse);
    expect(state.isFullscreen, isFalse);
  });

  test('対応OSでは起動時に現在値を読む', () async {
    windowChrome.currentFullScreen = true;
    container.read(fullscreenControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(fullscreenControllerProvider);
    expect(state.supported, isTrue);
    expect(state.isFullscreen, isTrue);
  });

  test('OS側の変化がイベントで反映される', () async {
    container.read(fullscreenControllerProvider);
    await Future<void>.delayed(Duration.zero);

    windowChrome.emit(true);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(fullscreenControllerProvider).isFullscreen, isTrue);
  });

  test('setFullscreenはコマンドを送るだけで、即座にstateを変えない', () async {
    container.read(fullscreenControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(fullscreenControllerProvider.notifier);
    await controller.setFullscreen(true);

    expect(windowChrome.setFullScreenCalls, [true]);
    expect(container.read(fullscreenControllerProvider).isFullscreen, isFalse);

    windowChrome.emit(true);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(fullscreenControllerProvider).isFullscreen, isTrue);
  });

  test('未対応OSではsetFullscreenは何もしない', () async {
    windowChrome.supported = false;
    container.read(fullscreenControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(fullscreenControllerProvider.notifier);
    await controller.setFullscreen(true);

    expect(windowChrome.setFullScreenCalls, isEmpty);
  });
}
