import 'session_state.dart';
import 'emulator_session.dart';

/// [EmulatorSession] の作り方。
///
/// featureはplatform実装を知らないため、生成そのものを`app`から差し込む
/// （design.md 3.1）。
typedef EmulatorSessionFactory = EmulatorSession Function({
  required String homeDir,
  String? romDir,
  BootMode bootMode,
});
