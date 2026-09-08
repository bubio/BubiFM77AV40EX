import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/emulator_error.dart';
import '../../emulator/emulator_event.dart';
import '../../emulator/emulator_session.dart';
import '../../emulator/emulator_session_factory.dart';
import '../../emulator/emulator_stats.dart';
import '../../emulator/session_state.dart';
import '../../emulator/state_slot_info.dart';
import '../../platform/persistence/app_data_paths.dart';
import '../../platform/persistence/cache_workspace.dart';
import '../../platform/persistence/external_file_access.dart';
import '../../platform/persistence/preferences_store.dart';
import '../display/screen_filter.dart';
import '../display/screen_fit.dart';
import 'emulator_state.dart';
import 'input/auto_key_engine.dart';
import 'input/keyboard_key_map.dart';
import 'input/romaji_to_kana.dart';

/// native container（D88/D77/D8E/1DD）。同一コンテナへ書き戻せる
/// （design.md 9.1）。
const fddNativeContainerExtensions = ['d88', 'd77', 'd8e', '1dd'];

/// コアが変換読込する形式（TD0/IMD/DSK/NFD/FDI、FDD-03）。原本は変更せず
/// 作業用D88として扱う（design.md 9.1、FDD-09）。
const fddConvertedExtensions = ['td0', 'imd', 'dsk', 'nfd', 'fdi'];

/// FD1/FD2ごとの最近使ったファイルの上限件数（FDD-07）。
const fddRecentFilesLimit = 5;

DiskSourceKind _sourceKindOfPath(String path) {
  final lower = path.toLowerCase();
  for (final ext in fddNativeContainerExtensions) {
    if (lower.endsWith('.$ext')) {
      return DiskSourceKind.nativeContainer;
    }
  }
  for (final ext in fddConvertedExtensions) {
    if (lower.endsWith('.$ext')) {
      return DiskSourceKind.converted;
    }
  }
  return DiskSourceKind.raw;
}

/// エミュレーターの起動と画面の受け取りを持つController。
///
/// 高頻度データは通さない。画素はネイティブ側がTextureへ直接渡し、
/// ここが持つのはTexture IDと解像度だけである（design.md 16.1）。
class EmulatorController extends Notifier<EmulatorViewState> {
  EmulatorController({
    required this.appDataPaths,
    required this.createSession,
    required this.externalFileAccess,
    required this.cacheWorkspace,
    required this.preferences,
  });

  final AppDataPaths appDataPaths;
  final EmulatorSessionFactory createSession;

  /// FDDの原本を選ばせ、アクセス権を確保する（design.md 11.2、16.1）。
  final ExternalFileAccess externalFileAccess;

  /// 挿入中の原本の複製を置くセッション作業領域（design.md 11.2、16.1）。
  final CacheWorkspace cacheWorkspace;

  /// FD1/FD2ごとの最近使ったファイル（FDD-07）を保存する先。
  final PreferencesStore preferences;

  EmulatorSession? _session;
  StreamSubscription<EmulatorEvent>? _events;

  /// 直近に指定されたマスター音量。次回[launch]時にも適用する
  /// （design.md 12.4）。
  double _masterVolume = 1.0;

  /// 直近に指定された実行設定（SYS-03、SYS-05、SYS-06）。
  /// 停止中に変更されても次回[launch]時に適用できるよう覚えておく。
  int _speedMultiplier = SpeedMultiplier.x1;
  bool _fullSpeed = false;
  CpuType _cpuType = CpuType.fast;
  RunOptionSwitches _optionSwitches = const RunOptionSwitches();

  /// 直近に指定された標準音声チャンネル音量（AUD-03）。停止中に
  /// 変更されても次回[launch]時に適用できるよう覚えておく。
  SoundChannelVolumes _soundVolumes = const SoundChannelVolumes();

  /// FDD内部機構音（ホスト側合成、readWriteのみ、AUD-04）の有効・無効。
  /// 停止中に変更されても次回[launch]時に適用できるよう覚えておく。
  bool _fddMechanicalSoundEnabled = true;

  /// 録音中かどうか（AUD-06）。`_teardown()`はdispose経路
  /// （`ref.onDispose`）からも呼ばれ、そこでは`state`の読み書きが
  /// Riverpodにより禁止されているため、`state.isRecording`ではなく
  /// この独立フィールドで判定する。
  bool _isRecording = false;

  /// ローマ字かな変換（INP-03）の有効・無効。既定OFF、永続化しない
  /// （`fddMechanicalSoundEnabled`と同じセッション限りの設定）。
  bool _romajiToKana = false;

  /// 自動キー入力中かどうか（INP-03）。`_isRecording`と同じ理由で
  /// `state`ではなくこの独立フィールドで判定する。
  bool _isAutoKeying = false;
  final AutoKeyEngine _autoKeyEngine = AutoKeyEngine();

  /// ローマ字かな変換（INP-03）のライブ入力（通常のキー入力自体を
  /// リアルタイムに変換する側）が使う、未確定ローマ字断片のバッファ。
  ///
  /// `_romajiToKana`ON中、ASCII英字キーだけをこのバッファへ横取りする
  /// （`handleKeyDown`参照）。数字・記号・矢印等は変換ON中でも常に通常
  /// 経路のまま（KANAロックは`kana_key`/`kana_shift_key`経由で数字・記号
  /// 行の出力も変えてしまうため、対象を英字キーだけに絞ることで、この
  /// ハザードに触れる経路を作らない）。
  final LiveRomajiBuffer _liveRomajiBuffer = LiveRomajiBuffer();

  /// ライブ変換で確定した断片を、実際にkey_down/upへ変換して送るエンジン。
  /// `_autoKeyEngine`（Paste専用）とは独立させ、同時に動いても競合しない
  /// ようにする（優先順位ルールにより通常キー入力はPasteを中断するが、
  /// ライブ変換自体は通常キー入力そのものであり中断対象ではない）。
  final AutoKeyEngine _liveTypeEngine = AutoKeyEngine();
  final List<String> _liveTypeQueue = [];
  bool _liveTypeDraining = false;

  /// ライブ変換のため横取りした物理キー（英字）の集合。対応する
  /// `keyUp`をここで判定し、通常経路（`session.keyUp`）へ回さない
  /// （合成した打鍵の上げ下げは`_liveTypeEngine`が独自のタイミングで
  /// 行うため、物理キーの上げ下げとは対応しない）。
  final Set<PhysicalKeyboardKey> _liveInterceptedKeys = {};

  /// FD1/FD2ごとの書込み保護・タイミング補正・CRCエラー無視（FDD-06）。
  /// 停止中に変更されても次回[launch]時に適用できるよう覚えておく。
  final Map<int, FddDriveSettings> _fddDriveSettings = {};

  WorkspaceHandle? _workspace;
  final Map<int, _FddSlot> _fddSlots = {};
  final Map<int, Completer<EmulatorErrorCode?>> _pendingCommands = {};

  /// ステータスバーのView/Core FPS（design.md 12.4）を出すための定期観測。
  ///
  /// `EmulatorStats`は累積カウンターのため、ここで前回値との差分を
  /// 一定間隔で取ってレートへ変換する。高頻度データではないので
  /// Riverpodのstateへ載せてよい（design.md 4.3）。
  static const _statsPollInterval = Duration(seconds: 1);
  Timer? _statsTimer;
  EmulatorStats? _lastStats;

  /// 現在押下中のキー（INP-01）。
  ///
  /// 高頻度なキー入力そのものはRiverpodのstateへ載せず、ここに保つ。
  /// OSのキーリピートによる二重押下の除去と、フォーカス喪失時の
  /// 全解放（design.md 8）に使う。
  final Set<PhysicalKeyboardKey> _pressedKeys = {};

  @override
  EmulatorViewState build() {
    ref.onDispose(_teardown);
    return EmulatorViewState(
      fddRecentFiles: {
        for (var drive = 0; drive < 2; drive++) drive: _readRecentFiles(drive),
      },
    );
  }

  String _recentFilesKey(int drive) => 'fdd.recent.fd$drive';

  List<Map<String, String>> _readRecentEntries(int drive) {
    final raw = preferences.getString(_recentFilesKey(drive));
    if (raw == null) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return [
        for (final entry in decoded)
          if (entry is Map<String, Object?> &&
              entry['token'] is String &&
              entry['displayName'] is String)
            {
              'token': entry['token']! as String,
              'displayName': entry['displayName']! as String,
            },
      ];
    } on FormatException {
      return [];
    }
  }

  List<FddRecentFile> _readRecentFiles(int drive) => [
    for (final entry in _readRecentEntries(drive))
      (token: entry['token']!, displayName: entry['displayName']!),
  ];

  Future<void> _recordRecentFile(int drive, ExternalResource resource) async {
    final entries = _readRecentEntries(drive)
      ..removeWhere((entry) => entry['token'] == resource.token);
    entries.insert(0, {
      'token': resource.token,
      'displayName': resource.displayName,
    });
    if (entries.length > fddRecentFilesLimit) {
      entries.removeRange(fddRecentFilesLimit, entries.length);
    }
    await preferences.setString(_recentFilesKey(drive), jsonEncode(entries));
    state = state.copyWith(
      fddRecentFiles: {
        ...state.fddRecentFiles,
        drive: [
          for (final entry in entries)
            (token: entry['token']!, displayName: entry['displayName']!),
        ],
      },
    );
  }

  Future<void> _forgetRecentFile(int drive, String token) async {
    final entries = _readRecentEntries(drive)
      ..removeWhere((entry) => entry['token'] == token);
    await preferences.setString(_recentFilesKey(drive), jsonEncode(entries));
    state = state.copyWith(
      fddRecentFiles: {
        ...state.fddRecentFiles,
        drive: [
          for (final entry in entries)
            (token: entry['token']!, displayName: entry['displayName']!),
        ],
      },
    );
  }

  /// FD1/FD2の最近使ったファイルの履歴を消す（FDD-07）。
  Future<void> clearRecentFiles(int drive) async {
    await preferences.setString(_recentFilesKey(drive), jsonEncode(const []));
    state = state.copyWith(
      fddRecentFiles: {...state.fddRecentFiles, drive: const []},
    );
  }

  /// コアを起動して画面をつなぐ。すでに動いていれば何もしない。
  Future<void> launch({BootMode bootMode = BootMode.basic}) async {
    if (_session != null) {
      return;
    }
    state = state.copyWith(
      session: SessionState.starting,
      clearFailure: true,
      bootMode: bootMode,
    );
    try {
      final homeDir = await appDataPaths.coreHomeDirectoryPath();
      final romDir = await appDataPaths.romsDirectoryPath();
      final session = createSession(
        homeDir: homeDir,
        romDir: romDir,
        bootMode: bootMode,
      );
      _session = session;
      _events = session.events.listen(_onEvent);
      await session.start();
      final textureId = await session.attachVideoTexture();
      session.setVolume(_masterVolume);
      state = state.copyWith(session: session.state, textureId: textureId);
      _lastStats = null;
      _statsTimer = Timer.periodic(_statsPollInterval, (_) => _pollStats());
      // 実行設定は起動が終わってから覚えている値を再適用する。既定値
      // どおりなら何も送らない（新しいコアの初期値と同じであり、
      // 無駄な往復を避ける）。ここで失敗しても、すでに動き出した
      // セッションをfailedへ巻き戻さない（SYS-03、SYS-05、SYS-06は
      // 起動そのものに必須ではないため、外側のtry/catchへ伝えない）。
      try {
        if (_speedMultiplier != SpeedMultiplier.x1) {
          await session.setSpeedMultiplier(_speedMultiplier);
        }
        if (_fullSpeed) {
          await session.setFullSpeed(_fullSpeed);
        }
        if (_cpuType != CpuType.fast) {
          await session.setCpuType(_cpuType);
        }
        if (_optionSwitches != const RunOptionSwitches()) {
          await session.setRunOptionSwitches(_optionSwitches);
        }
        if (_soundVolumes != const SoundChannelVolumes()) {
          const defaults = SoundChannelVolumes();
          for (final channel in SoundChannel.values) {
            if (_soundVolumes[channel] != defaults[channel]) {
              if (channel == SoundChannel.fddMechanism) {
                // AUD-04: このチャンネルはコアのch9ではなく、ホスト側
                // 合成器（FddMechanicalAudioSink）の音量へ配線されている
                // （design.md 7.1）。
                session.setFddMechanicalSoundVolume(_soundVolumes[channel]);
              } else {
                await session.setSoundChannelVolume(
                  channel,
                  _soundVolumes[channel],
                );
              }
            }
          }
        }
        if (!_fddMechanicalSoundEnabled) {
          session.setFddMechanicalSoundEnabled(_fddMechanicalSoundEnabled);
        }
        // 書込み保護はドライブではなく、マウントされた媒体自身が持つ
        // 状態（コアはDISK::open()のたびにファイル自身のヘッダから
        // 決め直す）。起動直後は何も挿入されていないため、ここでは
        // タイミング補正・CRC無視というドライブ側の設定だけを
        // 再適用する。書込み保護は挿入のたびに実際値を読み直す
        // （_insertResource/_refreshFddDriveSettings参照）。
        for (final entry in _fddDriveSettings.entries) {
          final drive = entry.key;
          final settings = entry.value;
          if (settings.correctTiming) {
            await session.setFddTiming(drive, true);
          }
          if (settings.ignoreCrc) {
            await session.setFddCrcCheck(drive, true);
          }
        }
        state = state.copyWith(
          speedMultiplier: _speedMultiplier,
          fullSpeed: _fullSpeed,
          cpuType: _cpuType,
          optionSwitches: _optionSwitches,
          soundVolumes: _soundVolumes,
          fddMechanicalSoundEnabled: _fddMechanicalSoundEnabled,
          fddDriveSettings: {..._fddDriveSettings},
        );
      } on Object {
        // 起動自体は成功しているため、実行設定の再適用失敗は
        // failureMessageへ出さず、選択値をstateへ反映しないだけにする。
      }
    } on Object catch (error) {
      state = state.copyWith(
        session: SessionState.failed,
        failureMessage: '$error',
      );
      await _teardown();
    }
  }

  /// コアを止めて画面を外す。
  ///
  /// 挿入中のFDDがあれば、書き戻しを終えてから止める。停止後は
  /// `CacheWorkspace`の内容が失われるため（design.md 11.2）、ここで
  /// 排出しない限り未反映のまま消える。
  Future<void> shutdown() async {
    for (final drive in _fddSlots.keys.toList()) {
      await ejectFdd(drive);
    }
    await _teardown();
    // 実行設定（SYS-03、SYS-05、SYS-06）とマスター音量は次回launch時に
    // 再適用するため覚えたままにする。表示もそれに合わせ、既定値へ
    // 戻さない（メニューの選択表示が実際に覚えている値と食い違うのを
    // 防ぐ）。
    state = EmulatorViewState(
      speedMultiplier: _speedMultiplier,
      fullSpeed: _fullSpeed,
      cpuType: _cpuType,
      optionSwitches: _optionSwitches,
      soundVolumes: _soundVolumes,
      fddMechanicalSoundEnabled: _fddMechanicalSoundEnabled,
      fddDriveSettings: {..._fddDriveSettings},
      fddRecentFiles: state.fddRecentFiles,
    );
  }

  /// リセットを投入する。
  ///
  /// [bootMode]を渡すと、コアがリセット時に読む`config.boot_mode`
  /// （native/bridge/src/bubi_fm77av.cpp、SYS-04「再起動後に反映できる」）
  /// をリセットの直前に書き換える。`Control > Boot mode`の選択はリセット
  /// までセッションへ伝わらないため、ここで渡さない限り選択が無視される。
  Future<void> reset(ResetKind kind, {BootMode? bootMode}) async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (bootMode != null) {
      await session.setBootMode(bootMode);
    }
    await session.reset(kind);
    if (bootMode != null) {
      state = state.copyWith(bootMode: bootMode);
    }
  }

  /// 表示領域への合わせ方を変える（VID-02）。
  void setFit(ScreenFit fit) {
    state = state.copyWith(fit: fit);
  }

  /// ホスト側の走査線効果を切り替える（VID-04）。コアへは送らない。
  void setScanlineEnabled(bool enabled) {
    state = state.copyWith(scanlineEnabled: enabled);
  }

  /// ホスト側のRGBフィルターを変える（VID-04）。コアへは送らない。
  void setHostFilter(HostScreenFilter filter) {
    state = state.copyWith(hostFilter: filter);
  }

  /// マスター音量を変える（0.0〜1.0、design.md 12.4）。
  ///
  /// 起動中なら即座に反映し、停止中でも次回[launch]時に使う値として
  /// 覚えておく。
  void setVolume(double volume) {
    _masterVolume = volume;
    _session?.setVolume(volume);
  }

  /// ジョイスティック[index]（0=JS1、1=JS2）の直接入力を更新する
  /// （方向・ボタンのビット定義は`JoystickBit`、M3 INP-04）。セッションが
  /// 無ければ何もしない（割当を覚え直す機構は持たない。物理コントローラー
  /// の状態はエミュレーター停止中は意味を持たないため）。
  void setJoystickState(int index, int bits) {
    _session?.setJoystickState(index, bits);
  }

  /// CPU速度倍率を変える（SYS-03）。
  ///
  /// コアの`update_config()`経由で即時反映されるため、起動中なら
  /// すぐに切り替わる。停止中は選択を覚えておくだけで、コアには
  /// 送らない（送る宛先セッションがない）。
  Future<void> setSpeedMultiplier(int multiplier) async {
    _speedMultiplier = multiplier;
    state = state.copyWith(speedMultiplier: multiplier);
    await _session?.setSpeedMultiplier(multiplier);
  }

  /// 無制限速度（Full Speed）の有効・無効を変える（SYS-03の「無制限」）。
  ///
  /// 起動中なら即座にCore threadの壁時計待機を止める／再開する。
  Future<void> setFullSpeed(bool enabled) async {
    _fullSpeed = enabled;
    state = state.copyWith(fullSpeed: enabled);
    await _session?.setFullSpeed(enabled);
  }

  /// CPU種別を変える（SYS-05）。起動中ならコアの`update_config()`経由で
  /// 即時反映される。
  Future<void> setCpuType(CpuType type) async {
    _cpuType = type;
    state = state.copyWith(cpuType: type);
    await _session?.setCpuType(type);
  }

  /// サイクルスチール・拡張RAM・HSYNC同期を変える（SYS-06）。
  ///
  /// サイクルスチールとHSYNC同期は起動中なら即時反映される。拡張RAMは
  /// コアがリセット時にしか読まないため、次のリセットまで実際の挙動には
  /// 反映されない（[state]の表示上はここで即座に更新する）。
  Future<void> setRunOptionSwitches(RunOptionSwitches switches) async {
    _optionSwitches = switches;
    state = state.copyWith(optionSwitches: switches);
    await _session?.setRunOptionSwitches(switches);
  }

  /// 標準OPNのFM・PSG、Beep、キーボード音、FDD機構音のうち[channel]の
  /// 音量を変える（AUD-03）。起動中なら即時反映される。
  ///
  /// [SoundChannel.fddMechanism]だけはコアのブリッジコマンドではなく、
  /// ホスト側合成器（`FddMechanicalAudioSink`、AUD-04）の音量へ送る
  /// （design.md 7.1「配線し直す」の実施）。
  Future<void> setSoundChannelVolume(
    SoundChannel channel,
    double volume,
  ) async {
    _soundVolumes = _soundVolumes.withVolume(channel, volume);
    state = state.copyWith(soundVolumes: _soundVolumes);
    if (channel == SoundChannel.fddMechanism) {
      _session?.setFddMechanicalSoundVolume(volume);
      return;
    }
    await _session?.setSoundChannelVolume(channel, volume);
  }

  /// FDD内部機構音（ホスト側合成、readWriteのみ、AUD-04）の有効・無効を
  /// 変える。起動中なら即座に反映され、停止中でも次回[launch]時に使う
  /// 値として覚えておく。
  void setFddMechanicalSoundEnabled(bool enabled) {
    _fddMechanicalSoundEnabled = enabled;
    state = state.copyWith(fddMechanicalSoundEnabled: enabled);
    _session?.setFddMechanicalSoundEnabled(enabled);
  }

  /// 最終ミキサー直後のPCMをWAVへ録音開始する（AUD-06、design.md 7.2）。
  ///
  /// 未起動、既に録音中、保存先が取得できない、またはセッション側で
  /// ファイルを開けない場合は何もしない（`_captureScreen`と同じく、単発
  /// 便利機能の失敗に利用者向けエラーダイアログは出さない）。
  Future<void> startRecording() async {
    final session = _session;
    if (session == null || _isRecording) {
      return;
    }
    final path = await appDataPaths.musicFilePath(
      'BubiFM77AV40EX-${_recordingTimestamp()}.wav',
    );
    if (path == null) {
      return;
    }
    final started = await session.startRecording(path);
    if (started) {
      _isRecording = true;
      state = state.copyWith(isRecording: true);
    }
  }

  /// 録音を止める（AUD-06）。録音中でなければ何もしない。
  Future<void> stopRecording() async {
    if (!_isRecording) {
      return;
    }
    await _session?.stopRecording();
    _isRecording = false;
    state = state.copyWith(isRecording: false);
  }

  String _recordingTimestamp() {
    final now = DateTime.now();
    String pad(int value, [int width = 2]) =>
        value.toString().padLeft(width, '0');
    return '${now.year}${pad(now.month)}${pad(now.day)}-'
        '${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
  }

  /// ローマ字かな変換（INP-03）の有効・無効を変える。
  ///
  /// このチェックボックスは、通常のキー入力自体をリアルタイムに変換する
  /// 「ライブ入力」（`handleKeyDown`参照）と、Pasteがクリップボード文字列を
  /// 変換するかどうかの両方を1つのフラグで兼ねる（片方だけを別に切り替える
  /// 要望は出ていない）。OFFへ切り替えた時点でライブ変換の未確定断片が
  /// 残っていれば、待たずにASCII文字として確定させる。
  void setRomajiToKana(bool value) {
    _romajiToKana = value;
    state = state.copyWith(romajiToKana: value);
    if (!value && !_liveRomajiBuffer.isEmpty) {
      _enqueueLiveType(_liveRomajiBuffer.flush());
    }
  }

  bool _isAsciiLetterChar(String? ch) {
    if (ch == null || ch.length != 1) {
      return false;
    }
    final code = ch.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
  }

  void _enqueueLiveType(String text) {
    if (text.isEmpty) {
      return;
    }
    _liveTypeQueue.add(text);
    unawaited(_drainLiveTypeQueue());
  }

  /// キューに積んだ確定済み断片を、`_liveTypeEngine`が空くたび1つずつ
  /// 打鍵させる。ライブ入力は物理キーの速さで断片を作れるため、
  /// `_liveTypeEngine`が前の断片をまだ打っている間に次が確定することが
  /// あり、単純に`run()`し直すと後着ちが無視される（`isRunning`中は
  /// 何もしないため）。ここでキュー化して直列に流す。
  Future<void> _drainLiveTypeQueue() async {
    if (_liveTypeDraining) {
      return;
    }
    _liveTypeDraining = true;
    try {
      while (_liveTypeQueue.isNotEmpty) {
        final session = _session;
        if (session == null) {
          _liveTypeQueue.clear();
          break;
        }
        final next = _liveTypeQueue.removeAt(0);
        // `romajiToKana: false`で渡す。断片はすでにローマ字→カタカナ変換
        // 済み（`LiveRomajiBuffer`）か、素通しASCIIのどちらかであり、
        // ここで`convertRomajiToKana`をもう一度通すべきではない
        // （`normalizeKanaText`は既に分解済みのカタカナ・ASCIIをそのまま
        // 通す恒等変換になるため、この経路として正しい）。
        await _liveTypeEngine.run(
          session,
          next,
          romajiToKana: false,
          initialKanaLock: state.ledState.kana,
          initialCapsLock: state.ledState.caps,
        );
      }
    } finally {
      _liveTypeDraining = false;
    }
  }

  /// クリップボードの文字列を自動キー入力する（INP-03）。
  ///
  /// 未起動、既に自動キー入力中、クリップボードが空／取得できない、
  /// 打てる文字が1つもない場合は何もしない（`_captureScreen`と同じく、
  /// 単発便利機能の失敗に利用者向けエラーダイアログは出さない）。
  Future<void> startAutoKey() async {
    final session = _session;
    if (session == null || _isAutoKeying) {
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final future = _autoKeyEngine.run(
      session,
      text,
      romajiToKana: _romajiToKana,
      initialKanaLock: state.ledState.kana,
      initialCapsLock: state.ledState.caps,
    );
    // `run()`はTimerを作るまで（打てる文字がなければ即return）を同期的に
    // 実行してからFutureを返すため、ここで`isRunning`を見れば
    // 実際に始まったかどうかを待たずに判定できる。打てる文字が1つも
    // なければここで抜け、状態を変えない。
    if (!_autoKeyEngine.isRunning) {
      return;
    }
    _isAutoKeying = true;
    state = state.copyWith(isAutoKeying: true);
    unawaited(future);
    // 完了（自然終了）はここでは待たず、`_isRecording`と同じく
    // `_pollStats()`の定期ポーリングが`_autoKeyEngine.isRunning`を見て
    // 状態を同期する。`stopAutoKey`（利用者操作・物理キー入力による中断）
    // は即座にここで状態を更新する。
  }

  /// 自動キー入力を止める（INP-03）。実行中でなければ何もしない。
  ///
  /// **優先順位ルール（design.md 8）**: 通常のキー入力は常に自動キー入力を
  /// 中断させる。この関数自体はメニューの`Stop Paste`からも呼ばれる。
  Future<void> stopAutoKey() async {
    if (!_isAutoKeying) {
      return;
    }
    await _autoKeyEngine.cancel();
    _isAutoKeying = false;
    state = state.copyWith(isAutoKeying: false);
  }

  /// 状態スロットの数（0〜9、STA-01）。
  static const int stateSlotCount = 10;

  /// 現在の実行状態を[slot]（0〜9）へ保存する（STA-01）。実行中でなければ
  /// 何もしない（`_captureScreen`と同じ、単発便利機能の既存方針）。
  ///
  /// [thumbnailBytes]はUI（widget木にアクセスできる`app`層）が
  /// `ScreenshotService.captureBytes`で取得したPNGを渡す。取得に失敗した
  /// 呼び出し側は省略してよく、その場合サムネイル無しで保存を続ける。
  ///
  /// 書込み順序はthumbnail → state.bin（ネイティブが直接書く）→
  /// metadata.jsonの順で、metadata.jsonの存在を「スロットが有効」の
  /// 判定基準にする（途中で失敗しても読めるが壊れたスロットを残さない）。
  Future<void> saveState(int slot, {Uint8List? thumbnailBytes}) async {
    final session = _session;
    if (session == null) {
      return;
    }
    final location = await appDataPaths.stateSlot(slot);
    if (thumbnailBytes != null) {
      try {
        await location.thumbnail.writeAtomic(thumbnailBytes);
      } on Object {
        // サムネイルは単発の便利機能。書けなくても保存自体は続ける。
      }
    }
    final commandId = await session.saveState(location.state.nativePath);
    final error = await _awaitCommand(commandId);
    if (error != null) {
      state = state.copyWith(failureMessage: '$error');
      return;
    }
    final metadata = <String, Object?>{
      'schemaVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'diskNames': [
        for (var drive = 0; drive < 2; drive++) state.fddMedia[drive],
      ],
    };
    await location.metadata.writeAtomic(utf8.encode(jsonEncode(metadata)));
  }

  /// [slot]（0〜9）から状態を読み込む（STA-02）。成功なら`true`。
  ///
  /// ロード前に自動キー入力の中断・押下中のキーの解放・ローマ字ライブ
  /// バッファのflushを行う（design.md 8、INP-03）。ホストが「押しっぱなし」
  /// と思っているキーが復元後のVMに残らないようにするためである。
  ///
  /// 非互換・破損状態は[EmulatorErrorCode.stateIncompatible]で拒否され、
  /// 現在のセッションは変更されない（コアが内部でロールバックする、
  /// design.md「状態保存（M3、STA-01/STA-02）の実装方式」）。
  Future<bool> loadState(int slot) async {
    final session = _session;
    if (session == null) {
      return false;
    }
    await stopAutoKey();
    releaseAllKeys();
    final location = await appDataPaths.stateSlot(slot);
    List<String?> diskNames = const [null, null];
    try {
      final metadata = jsonDecode(
        utf8.decode(await location.metadata.read()),
      ) as Map<String, dynamic>;
      final names = metadata['diskNames'] as List<dynamic>?;
      if (names != null) {
        diskNames = [for (final name in names) name as String?];
      }
    } on Object {
      // メタデータが読めなくても状態そのものは読み込みを試みる
      // （ディスク表示名が復元できないだけ）。
    }
    final commandId = await session.loadState(location.state.nativePath);
    final error = await _awaitCommand(commandId);
    if (error != null) {
      state = state.copyWith(failureMessage: '$error');
      return false;
    }
    // MEDIA_CHANGEDネイティブイベントはドライブ番号と挿抜だけを運び、
    // ファイル名を持たない（コアはホストが挿入したファイルパスを覚える
    // 概念を持たないため）。挿入有無自体は挿入直後に更新済みの
    // bank情報（`_refreshMountedDiskState`）から読み直し、表示名は
    // このアプリ自身が保存時に書いたmetadata.jsonから復元する。
    final updatedMedia = {...state.fddMedia};
    for (var drive = 0; drive < 2; drive++) {
      _refreshMountedDiskState(session, drive);
      final inserted = session.getFddBankInfo(drive).bankNum > 0;
      if (!inserted) {
        updatedMedia.remove(drive);
        continue;
      }
      final name = drive < diskNames.length ? diskNames[drive] : null;
      if (name != null && name.isNotEmpty) {
        updatedMedia[drive] = name;
      } else if (!updatedMedia.containsKey(drive)) {
        updatedMedia[drive] = '';
      }
    }
    state = state.copyWith(fddMedia: updatedMedia);
    return true;
  }

  /// スロット0〜9の一覧をUI表示用に読み出す（STA-01）。ダイアログを開く
  /// 直前に呼ぶ（design.md 12.3「メニューを開く前に更新する」と同じ方針）。
  Future<List<StateSlotInfo>> listStateSlots() async {
    final infos = <StateSlotInfo>[];
    for (var slot = 0; slot < stateSlotCount; slot++) {
      final location = await appDataPaths.stateSlot(slot);
      if (!await location.metadata.exists()) {
        infos.add(StateSlotInfo(slot: slot, hasData: false));
        continue;
      }
      DateTime? savedAt;
      var diskNames = const <String>[];
      try {
        final metadata = jsonDecode(
          utf8.decode(await location.metadata.read()),
        ) as Map<String, dynamic>;
        final createdAt = metadata['createdAt'] as String?;
        if (createdAt != null) {
          savedAt = DateTime.tryParse(createdAt);
        }
        final names = metadata['diskNames'] as List<dynamic>?;
        if (names != null) {
          diskNames = [
            for (final name in names)
              if (name is String && name.isNotEmpty) name,
          ];
        }
      } on Object {
        // 壊れたmetadata.jsonは「データなし」として扱う。
        infos.add(StateSlotInfo(slot: slot, hasData: false));
        continue;
      }
      Uint8List? thumbnailBytes;
      if (await location.thumbnail.exists()) {
        try {
          thumbnailBytes = Uint8List.fromList(await location.thumbnail.read());
        } on Object {
          thumbnailBytes = null;
        }
      }
      infos.add(
        StateSlotInfo(
          slot: slot,
          hasData: true,
          savedAt: savedAt,
          diskNames: diskNames,
          thumbnailBytes: thumbnailBytes,
        ),
      );
    }
    return infos;
  }

  FddDriveSettings _driveSettingsOf(int drive) =>
      _fddDriveSettings[drive] ?? const FddDriveSettings();

  Future<void> _updateFddDriveSettings(
    int drive,
    FddDriveSettings settings,
  ) async {
    _fddDriveSettings[drive] = settings;
    state = state.copyWith(
      fddDriveSettings: {...state.fddDriveSettings, drive: settings},
    );
  }

  /// マウント中の媒体の書込み保護を変える（FDD-06）。媒体自身が持つ
  /// 状態であり、次に別の媒体を挿入すればその媒体自身のヘッダから
  /// 値が決め直される（`_refreshMountedDiskState`参照）。
  Future<void> setFddWriteProtect(int drive, bool enabled) async {
    await _updateFddDriveSettings(
      drive,
      _driveSettingsOf(drive).copyWith(writeProtected: enabled),
    );
    await _session?.setFddWriteProtect(drive, enabled);
  }

  /// ドライブごとのタイミング補正を変える（FDD-06）。起動中は即時反映。
  Future<void> setFddTiming(int drive, bool enabled) async {
    await _updateFddDriveSettings(
      drive,
      _driveSettingsOf(drive).copyWith(correctTiming: enabled),
    );
    await _session?.setFddTiming(drive, enabled);
  }

  /// ドライブごとのCRCエラー無視を変える（FDD-06）。起動中は即時反映。
  Future<void> setFddCrcCheck(int drive, bool ignore) async {
    await _updateFddDriveSettings(
      drive,
      _driveSettingsOf(drive).copyWith(ignoreCrc: ignore),
    );
    await _session?.setFddCrcCheck(drive, ignore);
  }

  /// キーが押された（INP-01）。
  ///
  /// OSのキーリピートは同じ[physicalKey]を離さないまま繰り返し通知するため、
  /// 押下集合にすでにあれば境界で捨てる。コアの`key_down`へ二重に送らない。
  void handleKeyDown(
    PhysicalKeyboardKey physicalKey, {
    LogicalKeyboardKey? logicalKey,
    String? character,
  }) {
    final session = _session;
    if (session == null || !_pressedKeys.add(physicalKey)) {
      return;
    }
    // 通常のキー入力は常に自動キー入力を中断させる（design.md 8、INP-03）。
    if (_isAutoKeying) {
      unawaited(stopAutoKey());
    }
    // ローマ字かな変換（INP-03）のライブ入力: 変換ON中はASCII英字キーだけを
    // 横取りしてローマ字断片としてバッファへ積む。確定した出力（かな断片、
    // またはどの規則にも当たらない孤立文字のASCII素通し）があれば、通常の
    // `session.keyDown`ではなく`_liveTypeEngine`経由で打鍵する。英字以外の
    // キーは変換ON中でも常に通常経路のまま（KANAロックは`kana_key`/
    // `kana_shift_key`経由で数字・記号行の出力も変えてしまうため、対象を
    // 英字キーだけに絞り、このハザードに触れる経路自体を作らない）。
    if (_romajiToKana && _isAsciiLetterChar(character)) {
      _liveInterceptedKeys.add(physicalKey);
      _enqueueLiveType(_liveRomajiBuffer.push(character!));
      return;
    }
    if (!_liveRomajiBuffer.isEmpty) {
      // 変換途中の断片が残ったまま英字以外のキーが来た＝そこで確定させる。
      _enqueueLiveType(_liveRomajiBuffer.flush());
    }
    final vk = vkFromKeyEvent(physicalKey: physicalKey, logicalKey: logicalKey);
    if (vk != null) {
      unawaited(session.keyDown(vk));
    }
  }

  /// キーが離された（INP-01）。
  void handleKeyUp(
    PhysicalKeyboardKey physicalKey, {
    LogicalKeyboardKey? logicalKey,
  }) {
    final session = _session;
    if (session == null || !_pressedKeys.remove(physicalKey)) {
      return;
    }
    if (_liveInterceptedKeys.remove(physicalKey)) {
      // ローマ字ライブ変換へ横取りしたキーの物理up。合成した打鍵は
      // `_liveTypeEngine`が独自のタイミングで下げ上げするため、ここでは
      // 何もしない（対応するkey_downを送っていないため、対応するkey_upも
      // 送ってはならない）。
      return;
    }
    final vk = vkFromKeyEvent(physicalKey: physicalKey, logicalKey: logicalKey);
    if (vk != null) {
      unawaited(session.keyUp(vk));
    }
  }

  /// 押下中のキーをすべて解放する。
  ///
  /// フォーカス喪失時に呼ぶ（design.md 8）。離す操作を見せないままウィンドウ
  /// を切り替えると、コア側でキーが押されっぱなしになる。
  void releaseAllKeys() {
    final session = _session;
    final keys = _pressedKeys.toList();
    _pressedKeys.clear();
    final interceptedKeys = _liveInterceptedKeys.toSet();
    _liveInterceptedKeys.clear();
    if (!_liveRomajiBuffer.isEmpty) {
      _enqueueLiveType(_liveRomajiBuffer.flush());
    }
    if (session == null) {
      return;
    }
    for (final key in keys) {
      if (interceptedKeys.contains(key)) {
        // 横取りしたキー（対応するkey_downを送っていない）にはkey_upも
        // 送らない。
        continue;
      }
      final vk = vkFromKeyEvent(physicalKey: key);
      if (vk != null) {
        unawaited(session.keyUp(vk));
      }
    }
  }

  /// FD1(0)/FD2(1)へ利用者が選んだ媒体を挿入する（FDD-01、FDD-03）。
  ///
  /// 原本は`CacheWorkspace`のセッション作業領域へ複製し、コアには
  /// 複製先のパスだけを渡す（design.md 9.1、16.1）。対象ドライブへ
  /// すでに挿入済みでも入れ替えとして扱う。ファイル選択が済んだ後
  /// （＝利用者が入れ替えを確定した後）に、既存の媒体を先に排出
  /// （原本への書き戻しを含む）してから新しい媒体を挿入する。
  Future<void> insertFdd(int drive) async {
    if (_session == null) {
      return;
    }
    final resource = await externalFileAccess.pickFile(
      allowedExtensions: [
        ...fddNativeContainerExtensions,
        ...fddConvertedExtensions,
      ],
    );
    if (resource == null) {
      return;
    }
    await _insertResource(drive, resource);
  }

  /// FD1(0)/FD2(1)へ最近使ったファイル（FDD-07）を再挿入する。
  ///
  /// [token]が指す原本が既に無い・アクセスできない場合は履歴から外す。
  Future<void> insertFddFromRecent(int drive, String token) async {
    if (_session == null) {
      return;
    }
    final resource = await externalFileAccess.resolve(token);
    if (resource == null) {
      await _forgetRecentFile(drive, token);
      return;
    }
    await _insertResource(drive, resource);
  }

  /// 空の2D/2DDディスクを[destinationPath]の選択先へ作成し、FD1(0)/FD2(1)
  /// へ挿入する（FDD-05）。
  Future<void> insertBlankFdd(int drive, FddMediaType mediaType) async {
    final session = _session;
    if (session == null) {
      return;
    }
    final resource = await externalFileAccess.pickSaveLocation(
      suggestedFileName: mediaType == FddMediaType.d2
          ? 'blank-2d.d88'
          : 'blank-2dd.d88',
    );
    if (resource == null) {
      return;
    }
    try {
      final createId = await resource.withAccess(
        (nativePath) => session.createBlankFdd(mediaType, nativePath),
      );
      final createError = await _awaitCommand(createId);
      if (createError != null) {
        await resource.release();
        state = state.copyWith(failureMessage: '$createError');
        return;
      }
    } on Object catch (error) {
      await resource.release();
      state = state.copyWith(failureMessage: '$error');
      return;
    }
    await _insertResource(drive, resource);
  }

  /// 挿入済みのD88内でバンクを切り替える（FDD-04）。
  ///
  /// 排出して他バンクを含む全体を原本へ書き戻してから、同じ作業コピーを
  /// 新しいバンクで再挿入する（design.md 9.1「選択バンクの更新時に他
  /// バンクを保持して同じコンテナへ書き戻す」）。原本の再選択は行わない。
  Future<void> insertFddBank(int drive, int bank) async {
    final session = _session;
    final slot = _fddSlots[drive];
    final workspace = _workspace;
    if (session == null || slot == null || workspace == null) {
      return;
    }
    final ejectId = await session.ejectFdd(drive);
    final ejectError = await _awaitCommand(ejectId);
    if (ejectError != null) {
      state = state.copyWith(failureMessage: '$ejectError');
      return;
    }
    await slot.resource.withAccess(
      (nativePath) =>
          workspace.exportAtomic(slot.workspaceFileName, nativePath),
    );
    final workspacePath = '${workspace.nativePath}/${slot.workspaceFileName}';
    final insertId = await session.insertFdd(drive, workspacePath, bank: bank);
    final insertError = await _awaitCommand(insertId);
    if (insertError != null) {
      state = state.copyWith(failureMessage: '$insertError');
      return;
    }
    _refreshMountedDiskState(session, drive);
  }

  /// workspace内の最新D88を利用者が選ぶ保存先へ保存する（FDD-09
  /// `Save As D88…`）。元形式への逆変換は行わず、原本にも触れない。
  Future<void> saveFddAs(int drive) async {
    final session = _session;
    final slot = _fddSlots[drive];
    final workspace = _workspace;
    if (session == null || slot == null || workspace == null) {
      return;
    }
    final destination = await externalFileAccess.pickSaveLocation(
      suggestedFileName: '${slot.resource.displayName}.d88',
    );
    if (destination == null) {
      return;
    }
    final ejectId = await session.ejectFdd(drive);
    final ejectError = await _awaitCommand(ejectId);
    if (ejectError != null) {
      await destination.release();
      state = state.copyWith(failureMessage: '$ejectError');
      return;
    }
    await destination.withAccess(
      (nativePath) =>
          workspace.exportAtomic(slot.workspaceFileName, nativePath),
    );
    await destination.release();
    final workspacePath = '${workspace.nativePath}/${slot.workspaceFileName}';
    final insertId = await session.insertFdd(drive, workspacePath);
    final insertError = await _awaitCommand(insertId);
    if (insertError != null) {
      state = state.copyWith(failureMessage: '$insertError');
      return;
    }
    _refreshMountedDiskState(session, drive);
  }

  Future<void> _insertResource(int drive, ExternalResource resource) async {
    final session = _session;
    if (session == null) {
      await resource.release();
      return;
    }
    if (_fddSlots.containsKey(drive)) {
      await ejectFdd(drive);
    }
    try {
      final workspace = _workspace ??= await cacheWorkspace
          .createSessionWorkspace();
      final fileName = 'fd$drive-${resource.displayName}';
      final workspacePath = await resource.withAccess(
        (nativePath) => workspace.importCopy(nativePath, fileName: fileName),
      );
      final commandId = await session.insertFdd(drive, workspacePath);
      final error = await _awaitCommand(commandId);
      if (error != null) {
        await resource.release();
        state = state.copyWith(failureMessage: '$error');
        return;
      }
      _fddSlots[drive] = _FddSlot(
        resource: resource,
        workspaceFileName: fileName,
      );
      state = state.copyWith(
        fddMedia: {...state.fddMedia, drive: resource.displayName},
        fddSourceKind: {
          ...state.fddSourceKind,
          drive: _sourceKindOfPath(resource.displayName),
        },
      );
      _refreshMountedDiskState(session, drive);
      await _recordRecentFile(drive, resource);
    } on Object catch (error) {
      await resource.release();
      state = state.copyWith(failureMessage: '$error');
    }
  }

  /// 挿入・バンク切替の直後にコアへ問い合わせ、バンク情報と書込み保護の
  /// 表示をマウント中の媒体が実際に持つ値へ合わせる（FDD-04、FDD-06）。
  ///
  /// 書込み保護はドライブの記憶ではなく媒体自身が持つ状態（コアは
  /// `DISK::open()`のたびにファイル自身のヘッダから決め直す）。ここで
  /// 実際値を読み直さず前の媒体の値をそのまま表示し続けると、
  /// 見た目と実際の保護状態が食い違う。
  void _refreshMountedDiskState(EmulatorSession session, int drive) {
    final info = session.getFddBankInfo(drive);
    final writeProtected = session.getFddWriteProtect(drive);
    final settings = _driveSettingsOf(drive)
        .copyWith(writeProtected: writeProtected);
    _fddDriveSettings[drive] = settings;
    state = state.copyWith(
      fddBankNum: {...state.fddBankNum, drive: info.bankNum},
      fddCurBank: {...state.fddCurBank, drive: info.curBank},
      fddDriveSettings: {...state.fddDriveSettings, drive: settings},
    );
  }

  /// FD1(0)/FD2(1)から媒体を排出する（FDD-01）。
  ///
  /// コアが排出を終えたことを確認してから、作業領域の複製を原本へ
  /// 原子的に書き戻す（design.md 16.1）。未挿入のドライブは何もしない。
  Future<void> ejectFdd(int drive) async {
    final session = _session;
    final slot = _fddSlots[drive];
    if (session == null || slot == null) {
      return;
    }
    final commandId = await session.ejectFdd(drive);
    final error = await _awaitCommand(commandId);
    if (error != null) {
      state = state.copyWith(failureMessage: '$error');
      return;
    }
    final workspace = _workspace;
    if (workspace != null) {
      await slot.resource.withAccess(
        (nativePath) =>
            workspace.exportAtomic(slot.workspaceFileName, nativePath),
      );
    }
    await slot.resource.release();
    _fddSlots.remove(drive);
    final media = {...state.fddMedia}..remove(drive);
    final bankNum = {...state.fddBankNum}..remove(drive);
    final curBank = {...state.fddCurBank}..remove(drive);
    final sourceKind = {...state.fddSourceKind}..remove(drive);
    // 書込み保護は媒体自身が持つ状態のため、排出後はfalseへ戻す
    // （コアもDISK::close()で同様に戻す。design.md「FDD拡張」参照）。
    final driveSettings = _driveSettingsOf(drive)
        .copyWith(writeProtected: false);
    _fddDriveSettings[drive] = driveSettings;
    state = state.copyWith(
      fddMedia: media,
      fddBankNum: bankNum,
      fddCurBank: curBank,
      fddSourceKind: sourceKind,
      fddDriveSettings: {...state.fddDriveSettings, drive: driveSettings},
    );
  }

  /// 前回の観測との差分からView/Core FPSを求める（design.md 12.4）。
  void _pollStats() {
    final session = _session;
    if (session == null) {
      return;
    }
    // 録音キュー飽和（design.md 7.2）でホスト側が自発的に録音を止めた
    // 場合をここで拾い、UIへ反映する。
    final isRecordingActive = session.isRecordingActive;
    if (isRecordingActive != _isRecording) {
      _isRecording = isRecordingActive;
      state = state.copyWith(isRecording: isRecordingActive);
    }
    // 自動キー入力の自然終了（全文字を打ち終えた場合、INP-03）をここで
    // 拾う。利用者操作による中断（`stopAutoKey`）は呼出し元で即座に
    // 状態を更新するため、ここでは食い違ったときだけ同期する。
    final isAutoKeyingActive = _autoKeyEngine.isRunning;
    if (isAutoKeyingActive != _isAutoKeying) {
      _isAutoKeying = isAutoKeyingActive;
      state = state.copyWith(isAutoKeying: isAutoKeyingActive);
    }
    final stats = session.readStats();
    final last = _lastStats;
    _lastStats = stats;
    if (last == null) {
      return;
    }
    final seconds = _statsPollInterval.inMilliseconds / 1000;
    state = state.copyWith(
      viewFps: (stats.framesPublished - last.framesPublished) / seconds,
      coreFps: (stats.framesRun - last.framesRun) / seconds,
    );
  }

  /// [commandId]の[CommandCompleted]を待つ。成功ならnull、失敗ならエラー。
  Future<EmulatorErrorCode?> _awaitCommand(int commandId) {
    final completer = Completer<EmulatorErrorCode?>();
    _pendingCommands[commandId] = completer;
    return completer.future;
  }

  void _onEvent(EmulatorEvent event) {
    switch (event) {
      case LifecycleChanged(:final state):
        this.state = this.state.copyWith(session: state);
      case ScreenModeChanged(:final width, :final height):
        state = state.copyWith(frameWidth: width, frameHeight: height);
      case LedStateChanged(:final state):
        this.state = this.state.copyWith(ledState: state);
      case EmulatorErrorOccurred(:final code):
        state = state.copyWith(failureMessage: '$code');
      case CommandCompleted(:final commandId, :final error):
        _pendingCommands.remove(commandId)?.complete(error);
      case MediaAccessChanged(:final accessedDrives):
        final now = DateTime.now();
        state = state.copyWith(
          fddLastAccessed: {
            ...state.fddLastAccessed,
            for (final drive in accessedDrives) drive: now,
          },
        );
      default:
        break;
    }
  }

  Future<void> _teardown() async {
    // Timerの取消しは同期的に真っ先に行う。`ref.onDispose`はこの関数を
    // 待たないため、最初のawaitより後ろに置くとdispose直後にまだ
    // 生き残ってしまう（試験のFlutter testはpending timerを許さない）。
    // `AutoKeyEngine`内部の`Timer`も同じ理由で`disposeNow()`（同期）で
    // 即座に止める。保留中キーのupやKANAロック復元は行わない
    // （セッションはこの直後に手放すため、コア自体が止まればキー状態は
    // 無意味になる）。利用者操作による`Stop Paste`は`stopAutoKey()`の
    // 非同期`cancel()`を使う。
    _statsTimer?.cancel();
    _statsTimer = null;
    _autoKeyEngine.disposeNow();
    _liveTypeEngine.disposeNow();
    _liveTypeQueue.clear();
    _liveInterceptedKeys.clear();
    _isAutoKeying = false;
    _lastStats = null;
    final session = _session;
    _session = null;
    // design.md 5.1の終了順序（コア停止→録画停止→音声停止）のとおり、
    // セッションを手放す前に録音を確実にファイナライズする。中途半端な
    // （プレースホルダーサイズのままの）WAVファイルを残さない。
    if (session != null && _isRecording) {
      await session.stopRecording();
    }
    _isRecording = false;
    await _events?.cancel();
    _events = null;
    _pressedKeys.clear();
    _pendingCommands.clear();
    // 排出（design.md 16.1の書き戻し）を経ずに残ったスロットは
    // `shutdown()`を通らなかった場合（例: `dispose`のみ）にありうる。
    // `CacheWorkspace`は消失前提のため、書き戻さずアクセス権だけ返す。
    for (final slot in _fddSlots.values) {
      await slot.resource.release();
    }
    _fddSlots.clear();
    final workspace = _workspace;
    _workspace = null;
    if (workspace != null) {
      await workspace.dispose();
    }
    if (session == null) {
      return;
    }
    // 終了順序は design.md 5.1。Texture解放はセッション破棄より先で、
    // dispose の中で行われる。
    await session.stop();
    await session.dispose();
  }
}

class _FddSlot {
  _FddSlot({required this.resource, required this.workspaceFileName});

  final ExternalResource resource;
  final String workspaceFileName;
}
