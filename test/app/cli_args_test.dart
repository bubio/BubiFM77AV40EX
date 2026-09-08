import 'package:bubi_fm77av40ex/app/cli_args.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('APP-05 parseCliArgs', () {
    test('引数なしは空のCliOptionsを返す', () {
      final result = parseCliArgs(const []);
      expect(result, isA<CliParsedOptions>());
      final options = (result as CliParsedOptions).options;
      expect(options.bootMode, isNull);
      expect(options.media, isEmpty);
      expect(options.hasRuntimeOverrides, isFalse);
    });

    test('-basic/-dos、-2mhz/-1.2mhzなどオプションの順序は問わない', () {
      final result = parseCliArgs(const ['-dos', '-2mhz', '-x4']);
      final options = (result as CliParsedOptions).options;
      expect(options.bootMode, BootMode.dos);
      expect(options.cpuType, CpuType.fast);
      expect(options.speedMultiplier, SpeedMultiplier.x4);
    });

    test('同じ排他設定は最後の指定を採用する', () {
      final result = parseCliArgs(const ['-basic', '-dos', '-x1', '-x8']);
      final options = (result as CliParsedOptions).options;
      expect(options.bootMode, BootMode.dos);
      expect(options.speedMultiplier, SpeedMultiplier.x8);
    });

    test('大文字小文字を区別しない', () {
      final result = parseCliArgs(const ['-DOS', '-X4', '-HSYNC']);
      final options = (result as CliParsedOptions).options;
      expect(options.bootMode, BootMode.dos);
      expect(options.speedMultiplier, SpeedMultiplier.x4);
      expect(options.syncToHsync, isTrue);
    });

    test('cycle_steal/extram/hsyncは独立したフラグとして扱う', () {
      final result = parseCliArgs(const [
        '-cycle_steal',
        '-no_extram',
        '-hsync',
      ]);
      final options = (result as CliParsedOptions).options;
      expect(options.cycleSteal, isTrue);
      expect(options.extendedRam, isFalse);
      expect(options.syncToHsync, isTrue);
      expect(options.hasRuntimeOverrides, isTrue);
    });

    test('-fullspeedはfullSpeedをtrueにする', () {
      final result = parseCliArgs(const ['-fullspeed']);
      final options = (result as CliParsedOptions).options;
      expect(options.fullSpeed, isTrue);
    });

    test('image-fileとimage-Noを1組読み取る（1始まり）', () {
      final result = parseCliArgs(const ['game.d88', '2']);
      final options = (result as CliParsedOptions).options;
      expect(options.media, [const CliMediaSpec(path: 'game.d88', bank: 2)]);
    });

    test('image-Noを省略できる', () {
      final result = parseCliArgs(const ['game.d88']);
      final options = (result as CliParsedOptions).options;
      expect(options.media, [const CliMediaSpec(path: 'game.d88')]);
    });

    test('最大2ドライブまで。3件目以降は無視する', () {
      final result = parseCliArgs(const [
        'fd1.d88',
        '1',
        'fd2.d88',
        '2',
        'fd3.d88',
        '3',
      ]);
      final options = (result as CliParsedOptions).options;
      expect(options.media, [
        const CliMediaSpec(path: 'fd1.d88', bank: 1),
        const CliMediaSpec(path: 'fd2.d88', bank: 2),
      ]);
    });

    test('オプションと媒体は任意の順序で混在できる', () {
      final result = parseCliArgs(const [
        '-dos',
        'fd1.d88',
        '1',
        '-x4',
        'fd2.d88',
      ]);
      final options = (result as CliParsedOptions).options;
      expect(options.bootMode, BootMode.dos);
      expect(options.speedMultiplier, SpeedMultiplier.x4);
      expect(options.media, [
        const CliMediaSpec(path: 'fd1.d88', bank: 1),
        const CliMediaSpec(path: 'fd2.d88'),
      ]);
    });

    test('-h/-help/--helpはヘルプを返す（他の引数より優先）', () {
      for (final help in ['-h', '-help', '--help', '-H']) {
        final result = parseCliArgs(['-dos', help, 'fd1.d88']);
        expect(result, isA<CliHelpRequested>());
      }
    });

    test('未知オプションは構文エラー', () {
      final result = parseCliArgs(const ['-unknown']);
      expect(result, isA<CliSyntaxError>());
    });

    test('空引数は構文エラー', () {
      final result = parseCliArgs(const ['']);
      expect(result, isA<CliSyntaxError>());
    });

    test('不正なバンク番号（0以下）は構文エラー', () {
      final result = parseCliArgs(const ['game.d88', '0']);
      expect(result, isA<CliSyntaxError>());
    });
  });

  group('APP-05 resolveCliPath', () {
    test('絶対パスはそのまま返す', () {
      expect(
        resolveCliPath('/abs/path.d88', workingDirectory: '/home/user/work'),
        '/abs/path.d88',
      );
    });

    test('相対パスは作業ディレクトリ基準で解決する', () {
      expect(
        resolveCliPath('game.d88', workingDirectory: '/home/user/work'),
        '/home/user/work/game.d88',
      );
    });

    test('~はホームディレクトリへ展開する', () {
      expect(
        resolveCliPath(
          '~/Disks/game.d88',
          workingDirectory: '/home/user/work',
          homeDirectory: '/home/user',
        ),
        '/home/user/Disks/game.d88',
      );
    });
  });
}
