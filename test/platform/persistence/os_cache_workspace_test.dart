import 'dart:io';

import 'package:bubifm77av40ex/platform/persistence/os_cache_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CacheWorkspace`は消えてよい前提の一時領域である（design.md 11.2、16.1）。
/// ここでは`path_provider`のプラットフォームチャンネルを経由せず、
/// [Directory.systemTemp]の下へ向けて次を確認する。
///
/// - 消失: `dispose()`で作業ディレクトリそのものが消える。
/// - 起動時清掃: 前回異常終了の残骸があっても、次回起動の
///   `purgeAbandonedWorkspaces()`で必ず空になる。
/// - 途中失敗からの回復: `exportAtomic`が原本側へ残す一時ファイルは
///   `fdd-sessions/`の外にあるため、キャッシュの起動時清掃で原本を
///   壊さない。清掃後も新しい作業領域を作り直せる。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bubi-cache-workspace-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  OsCacheWorkspace workspace() =>
      OsCacheWorkspace.withCacheRoot(() async => root);

  test('消失: dispose()で作業ディレクトリが消える', () async {
    final handle = await workspace().createSessionWorkspace();
    final sourceFile = File('${root.path}/source.d88')
      ..writeAsStringSync('data');
    final workspacePath = await handle.importCopy(
      sourceFile.path,
      fileName: 'fd0.d88',
    );
    expect(await File(workspacePath).exists(), isTrue);

    await handle.dispose();

    expect(await File(workspacePath).exists(), isFalse);
    expect(await Directory(handle.nativePath).exists(), isFalse);
  });

  test('起動時清掃: 前回異常終了の残骸を必ず空にする', () async {
    // 異常終了で`dispose()`が呼ばれなかった場合を模す。作業ディレクトリを
    // 手で残し、他のファイルもそこへ置く。
    final leftover = await workspace().createSessionWorkspace();
    await leftover.importCopy(
      (File('${root.path}/leftover-source.d88')..writeAsStringSync('x')).path,
      fileName: 'fd0.d88',
    );
    final sessionsRoot = Directory('${root.path}/fdd-sessions');
    expect(await sessionsRoot.list().toList(), isNotEmpty);

    await workspace().purgeAbandonedWorkspaces();

    expect(await sessionsRoot.list().toList(), isEmpty);
  });

  test('途中失敗からの回復: 起動時清掃の後も新しい作業領域を作れる', () async {
    await workspace().createSessionWorkspace();
    await workspace().purgeAbandonedWorkspaces();

    final handle = await workspace().createSessionWorkspace();
    final sourceFile = File('${root.path}/source2.d88')
      ..writeAsStringSync('data2');
    final workspacePath = await handle.importCopy(
      sourceFile.path,
      fileName: 'fd0.d88',
    );

    expect(await File(workspacePath).exists(), isTrue);
    expect(await Directory(handle.nativePath).exists(), isTrue);
  });

  test('途中失敗からの回復: exportAtomicの一時ファイルは原本ディレクトリに残っても'
      'キャッシュの起動時清掃で消えない（原本を壊さない）', () async {
    final destinationDir = await Directory.systemTemp.createTemp(
      'bubi-original-media-',
    );
    addTearDown(() => destinationDir.delete(recursive: true));
    final destination = File('${destinationDir.path}/GAME.D88');
    await destination.writeAsString('original');

    final handle = await workspace().createSessionWorkspace();
    await handle.importCopy(
      (File('${root.path}/copy-source.d88')..writeAsStringSync('updated')).path,
      fileName: 'fd0.d88',
    );
    await handle.exportAtomic('fd0.d88', destination.path);

    // 書き戻しはコアが排出を終えたことを確認してから行うため
    // （design.md 16.1）、ここでは正常経路の書き戻し結果を確かめる。
    expect(await destination.readAsString(), 'updated');
    expect(await File('${destination.path}.tmp').exists(), isFalse);

    // その後の起動時清掃はキャッシュ側だけに閉じ、原本には触れない。
    await workspace().purgeAbandonedWorkspaces();
    expect(await destination.readAsString(), 'updated');
  });

  test('exists/delete: 作業領域内のファイルの有無を調べ、消せる', () async {
    final handle = await workspace().createSessionWorkspace();
    await handle.importCopy(
      (File('${root.path}/game.td0')..writeAsStringSync('td0')).path,
      fileName: 'fd0-GAME.TD0',
    );
    // コアが変換読込した媒体の変更を書き出す別ファイルを模す。
    File('${handle.nativePath}/fd0-GAME.TD0.D88').writeAsStringSync('d88');

    expect(await handle.exists('fd0-GAME.TD0'), isTrue);
    expect(await handle.exists('fd0-GAME.TD0.D88'), isTrue);
    expect(await handle.exists('fd0-GAME.TD0.D8E'), isFalse);

    await handle.delete('fd0-GAME.TD0.D88');
    // 無いファイルを消しても失敗しない。
    await handle.delete('fd0-GAME.TD0.D8E');

    expect(await handle.exists('fd0-GAME.TD0.D88'), isFalse);
    expect(await handle.exists('fd0-GAME.TD0'), isTrue);
  });

  test('contentEquals: 作業コピーと原本の中身が同じかを比べる', () async {
    final handle = await workspace().createSessionWorkspace();
    final original = File('${root.path}/GAME.D88')..writeAsStringSync('abc');
    await handle.importCopy(original.path, fileName: 'fd0-GAME.D88');

    expect(await handle.contentEquals('fd0-GAME.D88', original.path), isTrue);

    // 長さが同じで中身だけ違う場合（コアがセクタを書き換えた場合）。
    File('${handle.nativePath}/fd0-GAME.D88').writeAsStringSync('abd');
    expect(await handle.contentEquals('fd0-GAME.D88', original.path), isFalse);

    File('${handle.nativePath}/fd0-GAME.D88').writeAsStringSync('abcd');
    expect(await handle.contentEquals('fd0-GAME.D88', original.path), isFalse);

    // 原本が消えていれば「同じではない」とする。
    await original.delete();
    expect(await handle.contentEquals('fd0-GAME.D88', original.path), isFalse);
  });

  test('reopenSessionWorkspace: 消えた作業領域を同じ場所に作り直す', () async {
    final first = await workspace().createSessionWorkspace();
    final path = first.nativePath;
    await first.dispose();
    expect(await Directory(path).exists(), isFalse);

    final reopened = await workspace().reopenSessionWorkspace(path);

    expect(reopened, isNotNull);
    expect(reopened!.nativePath, path);
    expect(await Directory(path).exists(), isTrue);
    final source = File('${root.path}/GAME.D88')..writeAsStringSync('d88');
    await reopened.importCopy(source.path, fileName: 'fd0-GAME.D88');
    expect(await reopened.exists('fd0-GAME.D88'), isTrue);
  });

  test('reopenSessionWorkspace: セッション用の領域の直下以外は受け付けない', () async {
    final sessions = '${root.path}/fdd-sessions';
    for (final path in [
      root.path,
      sessions,
      '$sessions/..',
      '$sessions/.',
      '$sessions/a/b',
      '${root.path}/elsewhere',
    ]) {
      expect(
        await workspace().reopenSessionWorkspace(path),
        isNull,
        reason: path,
      );
    }
    expect(await Directory('$sessions/a').exists(), isFalse);
    expect(await Directory('${root.path}/elsewhere').exists(), isFalse);
  });
}
