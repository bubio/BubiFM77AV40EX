import 'package:bubi_fm77av40ex/emulator/emulator_error.dart';
import 'package:bubi_fm77av40ex/platform/core_ffi/ffi_emulator_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// ネイティブライブラリを開く前に弾ける入力の検査。
///
/// ライブラリを実際に読み込む検証は native/host/session_test.cpp と
/// scripts/run_native_checks.sh が担当する。ここでCIがdylibへ依存しないよう、
/// ライブラリ解決に到達しない経路だけを対象にする。
void main() {
  test('SYS-01 homeDir が空なら invalidArgument で拒否する', () {
    expect(
      () => FfiEmulatorSession.create(homeDir: ''),
      throwsA(
        isA<EmulatorException>().having(
          (error) => error.code,
          'code',
          EmulatorErrorCode.invalidArgument,
        ),
      ),
    );
  });
}
