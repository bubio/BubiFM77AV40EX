// macOSのplatform実装を実機で確かめる手動検査。
//
// GUI操作を伴わない範囲だけを見る。
//   - 保存領域が design.md 11.3 の位置に解決されること
//   - roms/ を用意できること
//   - ExternalFileAccess がアクセス権を扱えること（サンドボックス外では
//     正規化パスへ退避する）
//
// 実行:
//   fvm flutter build macos --release -t tool/macos_platform_check.dart
//   ./build/macos/Build/Products/Release/BubiFM77AV40EX.app/Contents/MacOS/BubiFM77AV40EX
//
// 結果を出力して自分で終了する。CIでは実行しない。
import 'dart:io';

import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/platform/persistence/os_app_data_paths.dart';
import 'package:bubi_fm77av40ex/platform/core_ffi/ffi_emulator_session.dart';
import 'package:bubi_fm77av40ex_platform/bubi_fm77av40ex_platform.dart';
import 'package:flutter/widgets.dart';

int failures = 0;

void check(bool condition, String what) {
  stdout.writeln('[${condition ? ' ok ' : 'FAIL'}] $what');
  if (!condition) {
    failures++;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  stdout.writeln('== 保存領域（design.md 11.3）');
  final paths = OsAppDataPaths();
  final root = await paths.root();
  final roms = await paths.romsDirectory();
  final cache = await paths.cacheRoot();

  final home = Platform.environment['HOME'] ?? '';
  // 表示は $HOME を伏せる。利用者名を残さない（NFR-07）。
  String short(String path) =>
      home.isEmpty ? path : path.replaceFirst(home, '~');

  stdout.writeln('  root : ${short(root.path)}');
  stdout.writeln('  roms : ${short(roms.path)}');
  stdout.writeln('  cache: ${short(cache.path)}');

  check(
    short(root.path) == '~/Library/Application Support/BubiFM77AV40EX',
    'Application Support が仕様どおりの位置になる',
  );
  check(
    short(cache.path) == '~/Library/Caches/BubiFM77AV40EX',
    'Caches が仕様どおりの位置になる',
  );
  check(short(roms.path).endsWith('/BubiFM77AV40EX/roms'), 'roms/ が直下にある');
  check(roms.existsSync(), 'roms/ を作成できる');
  check(
    !root.path.contains('/Library/Containers/'),
    'App Sandbox のコンテナ内へ入っていない',
  );

  stdout.writeln('== 外部ファイルのアクセス権');
  const bookmarks = SecurityScopedBookmarks();
  check(await bookmarks.isSupported, 'プラグインが応答する');

  // サンドボックス外では .withSecurityScope のブックマークを作れない。
  // 作れても作れなくても、呼び出し側が落ちないことだけを要求する。
  final temporary = Directory.systemTemp.createTempSync('bubi_platform');
  String? token;
  try {
    token = await bookmarks.create(temporary.path);
    stdout.writeln('  ブックマークを作成できた（サンドボックス相当の環境）');
  } on Object {
    token = null;
    stdout.writeln('  ブックマークは作成できない（サンドボックス外）');
  }
  if (token != null) {
    final resolved = await bookmarks.resolve(token);
    // 解決結果は正規化される（macOSは /var を /private/var へ解く）。
    // 比較する側もシンボリックリンクを解いてから突き合わせる。
    check(
      resolved != null &&
          Directory(resolved.path).resolveSymbolicLinksSync() ==
              temporary.resolveSymbolicLinksSync(),
      '解決結果が元のパスと一致する',
    );
    await bookmarks.stopAccess(token);
  }
  check(await bookmarks.resolve('not-base64') == null, '壊れたトークンはnullになる');
  temporary.deleteSync(recursive: true);

  await _checkRomWiring(paths);

  stdout.writeln(failures == 0 ? 'すべて合格' : '失敗あり');
  exit(failures == 0 ? 0 : 1);
}

/// roms/ に置いたファイルがコアの読込み位置まで届くことを確かめる。
///
/// 本物のROMは使わない。ROMの名前も使わず、検査専用の名前で結線だけを見る。
/// 利用者が本物のROMを置いていても影響しない。
Future<void> _checkRomWiring(OsAppDataPaths paths) async {
  stdout.writeln('== roms/ からコアへの結線');

  final roms = await paths.romsDirectory();
  final root = await paths.root();
  final marker = File('${roms.path}/zz_bubi_wiring_check.bin');
  marker.writeAsBytesSync(List<int>.filled(16, 0));

  FfiEmulatorSession? session;
  try {
    session = FfiEmulatorSession.create(
      homeDir: root.path,
      romDir: roms.path,
      bootMode: BootMode.dos,
    );
    final coreDirectory = session.readCoreDirectory();
    check(coreDirectory.startsWith(root.path), 'コアの読込み位置がアプリケーションデータ領域の下にある');

    await session.start();
    var running = false;
    for (var waited = 0; waited < 500; waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (session.state == SessionState.running) {
        running = true;
        break;
      }
    }
    check(running, 'roms/ を渡してコアを起動できる');
    check(
      Link('${coreDirectory}zz_bubi_wiring_check.bin').existsSync(),
      'roms/ のファイルへリンクが張られる',
    );

    await session.stop();
  } on Object catch (error) {
    check(false, '結線の確認中に失敗した: $error');
  } finally {
    await session?.dispose();
    if (marker.existsSync()) {
      marker.deleteSync();
    }
  }
}
