import 'emulator_event.dart';
import 'emulator_stats.dart';
import 'session_state.dart';

/// エミュレーターコアとの境界（design.md 4.1）。
///
/// 実装は `lib/platform/core_ffi/` にあり、`app` が注入する。
/// `features` はこの抽象だけに依存し、FFIやプラグインを直接触らない。
abstract class EmulatorSession {
  /// 直近のライフサイクル状態。
  SessionState get state;

  /// 低頻度イベントの通知。購読者がいなくてもコアは進み続ける。
  Stream<EmulatorEvent> get events;

  /// Core thread を起動する。
  ///
  /// すでに起動していれば [EmulatorException] を `invalidState` で投げる。
  /// 起動要求の受理と実際の初期化成功は別で、失敗は
  /// [LifecycleChanged] の [SessionState.failed] と
  /// [EmulatorErrorOccurred] で通知する。
  Future<void> start();

  /// Core thread を停止して join する。冪等。
  Future<void> stop();

  /// リセットを投入し、コマンドの連番を返す。
  ///
  /// 完了は同じIDの [CommandCompleted] で通知する。
  Future<int> reset(ResetKind kind);

  /// ブートモードを設定し、コマンドの連番を返す。
  ///
  /// コアはリセット時にこの値を読むため、反映されるのは次の
  /// [reset] または再起動からになる（SYS-04）。
  Future<int> setBootMode(BootMode mode);

  /// CPU速度倍率を設定し、コマンドの連番を返す（SYS-03）。
  ///
  /// [multiplier] は[SpeedMultiplier]の値。ネイティブ側のCore threadが
  /// 壁時計の1tickあたりに`vm->run()`を呼ぶ回数を変えるため、次の
  /// リセットを待たずに反映される。
  Future<int> setSpeedMultiplier(int multiplier);

  /// 無制限速度（Full Speed）の有効・無効を設定し、コマンドの連番を
  /// 返す（SYS-03の「無制限」）。
  ///
  /// 有効な間、ネイティブ側のCore threadは壁時計の待機を省いて
  /// `vm->run()`を呼び続ける。速度は実質ホストのCPU性能で決まる。
  /// 音声は生成量が実時間の消費量を大きく上回るため、有界リングの
  /// オーバーラン方針（最古破棄）により途切れがちになる。
  Future<int> setFullSpeed(bool enabled);

  /// CPU種別を設定し、コマンドの連番を返す（SYS-05）。
  ///
  /// コアの`update_config()`を呼ぶため、次のリセットを待たずに
  /// 反映される。
  Future<int> setCpuType(CpuType type);

  /// サイクルスチール・拡張RAM・HSYNC同期を設定し、コマンドの連番を
  /// 返す（SYS-06）。
  ///
  /// [switches]の3項目を毎回丸ごと置き換える。サイクルスチールと
  /// HSYNC同期は即時反映されるが、拡張RAMは次のリセットまで見た目に
  /// 反映されない。
  Future<int> setRunOptionSwitches(RunOptionSwitches switches);

  /// 標準OPNのFM・PSG、Beep、キーボード音、FDD機構音のうち[channel]の
  /// 音量を設定し、コマンドの連番を返す（AUD-03）。[volume]は0.0〜1.0
  /// （0.0〜1.0の範囲外はクランプする）。
  Future<int> setSoundChannelVolume(SoundChannel channel, double volume);

  /// RGBフィルター（VID-04）の有効・無効を設定し、コマンドの連番を返す。
  ///
  /// 有効な間、ネイティブ側が移植元と同じ計算でコアの画面へフィルターを
  /// 掛け、画面の[setScreenPower]倍の大きさの面をTextureへ渡す。
  Future<int> setRgbFilterEnabled(bool enabled);

  /// RGBフィルターが画面を広げる倍率（横[x]・縦[y]、1〜8）を設定し、
  /// コマンドの連番を返す（VID-04）。
  ///
  /// 移植元が表示の大きさから求める値（`ceil(表示幅 / 画面幅)`）と同じ
  /// ものを、表示側が求めて渡す。
  Future<int> setScreenPower(int x, int y);

  /// キーを押す。[vkCode] は win32 の仮想キーコード（INP-01）。
  ///
  /// リピートの抑止と重複押下の除去は呼び出し側（Controller）の責務で、
  /// ここは受け取った1回をそのままコアへ渡す。
  Future<void> keyDown(int vkCode);

  /// キーを離す。[vkCode] は win32 の仮想キーコード（INP-01）。
  Future<void> keyUp(int vkCode);

  /// FD1/FD2へ媒体を挿入し、コマンドの連番を返す（FDD-01）。
  ///
  /// [drive] は0=FD1、1=FD2。[imagePath] はコアがそのまま開くOSパスで、
  /// D88/D77/D8E/1DDの書き戻し用作業コピーを用意するのは呼び出し側
  /// （`FfiEmulatorSession`）の責務（design.md 9.1）。対象ドライブに
  /// 挿入済みなら[EmulatorException]を`invalidState`で投げる。
  Future<int> insertFdd(int drive, String imagePath, {int bank = 0});

  /// FD1/FD2から媒体を排出し、コマンドの連番を返す（FDD-01）。
  ///
  /// 未挿入のドライブへの排出は冪等に成功する。
  Future<int> ejectFdd(int drive);

  /// [drive]にマウント中の媒体の書込み保護を設定し、コマンドの連番を
  /// 返す（FDD-06）。
  ///
  /// 書込み保護はディスク単位のランタイム状態であり、ドライブの記憶
  /// ではない。コアは次に挿入された別の媒体では、その媒体自身のヘッダ
  /// から値を決め直すため、この呼出しは今マウントされている媒体にしか
  /// 効かない。
  Future<int> setFddWriteProtect(int drive, bool enabled);

  /// ドライブごとのタイミング補正を設定し、コマンドの連番を返す（FDD-06）。
  Future<int> setFddTiming(int drive, bool enabled);

  /// ドライブごとのCRCエラー無視を設定し、コマンドの連番を返す（FDD-06）。
  Future<int> setFddCrcCheck(int drive, bool ignore);

  /// 空の2D/2DDディスクイメージを[destinationPath]へ作成し、コマンドの
  /// 連番を返す（FDD-05）。挿入は行わない。呼び出し側が改めて
  /// [insertFdd] を呼ぶこと。
  Future<int> createBlankFdd(FddMediaType mediaType, String destinationPath);

  /// 現在の実行状態を[destinationPath]へ保存し、コマンドの連番を返す
  /// （STA-01）。スロット番号自体は呼び出し側のディレクトリ構成が表し、
  /// コアへは渡さない。
  Future<int> saveState(String destinationPath);

  /// [sourcePath]から状態を読み込み、コマンドの連番を返す（STA-02）。
  ///
  /// 先頭バージョンが既知値と一致しないファイルはロードされず、
  /// [EmulatorErrorCode.stateIncompatible]で完了する。コアはこれより
  /// 深い不一致も検出して現在の実行状態へ内部でロールバックするが、
  /// その場合は成功で完了する（design.md「状態保存（M3、
  /// STA-01/STA-02）の実装方式」の既知の制限）。
  Future<int> loadState(String sourcePath);

  /// [drive]に挿入中のD88のバンク情報を返す（FDD-04）。未挿入なら
  /// 両方0。
  ({int bankNum, int curBank}) getFddBankInfo(int drive);

  /// [drive]に挿入中の媒体の実際の書込み保護状態を返す（FDD-06）。
  ///
  /// コアは挿入のたびにディスク自身のヘッダ由来の値へ決め直すため、
  /// これは「そのドライブに対して最後に指定した値」ではなく「今
  /// マウントされている媒体が実際に持つ値」を返す。未挿入ならfalse。
  bool getFddWriteProtect(int drive);

  /// CMTを再生用に開き、コマンドの連番を返す（CMT-01）。
  ///
  /// [imagePath] はコアがそのまま開くOSパス（拡張子.t77/.wav/.tapで
  /// コアが自動判別する）。既に挿入済みなら[EmulatorException]を
  /// `invalidState`で投げる。原作`.rc`の"Play"に対応する。
  Future<int> insertCmtForPlayback(String imagePath);

  /// CMTを録音用に新規作成して開き、コマンドの連番を返す（CMT-02）。
  ///
  /// [imagePath] は新規作成する絶対パス（既存ファイルの有無は問わない）。
  /// 既に挿入済みなら[EmulatorException]を`invalidState`で投げる。
  /// 原作`.rc`の"Rec"に対応する。
  Future<int> insertCmtForRecording(String imagePath);

  /// CMTを排出し、コマンドの連番を返す（CMT-01）。
  ///
  /// 未挿入のドライブへの排出は冪等に成功する。
  Future<int> ejectCmt();

  /// CMTの走行を開始し、コマンドの連番を返す（CMT-03）。
  /// 原作`.rc`の"Play Button"に対応する（挿入用の[insertCmtForPlayback]/
  /// [insertCmtForRecording]とは別物）。
  Future<int> playCmt();

  /// CMTの走行を止め、コマンドの連番を返す（CMT-03）。
  /// 原作`.rc`の"Stop Button"に対応する。
  Future<int> stopCmt();

  /// CMTを早送りし、コマンドの連番を返す（CMT-03）。
  Future<int> fastForwardCmt();

  /// CMTを巻戻し、コマンドの連番を返す（CMT-03）。
  Future<int> rewindCmt();

  /// CMTの波形整形の有効・無効を設定し、コマンドの連番を返す（CMT-04）。
  Future<int> setCmtWaveShaping(bool enabled);

  /// CMT高速ロード（テープ再生中だけ無制限速度で進め、その間の音声を
  /// 捨てる）の有効・無効を設定し、コマンドの連番を返す（CMT-06）。
  Future<int> setCmtFastLoad(bool enabled);

  /// CMTノイズ・CMT信号・CMT音声を個別に有効・無効化し、コマンドの連番を
  /// 返す（AUD-07）。
  Future<int> setCmtSoundEnabled(CmtSoundKind kind, bool enabled);

  /// CMTノイズ・CMT信号の音量を調整し、コマンドの連番を返す（AUD-07）。
  ///
  /// [kind]に[CmtSoundKind.voice]を渡すと[EmulatorException]を
  /// `invalidArgument`で投げる（upstreamがCMT音声用の内部音量へ配線して
  /// いないため。design.md「標準音声設定（M3、AUD-03）の実装方式」隣接の
  /// 注記参照）。
  Future<int> setCmtSoundVolume(CmtSoundKind kind, double volume);

  /// CMTの現在状態を返す（CMT-05）。
  ///
  /// [getFddBankInfo]と同型の直接アクセサ。走行位置は0〜100
  /// （未挿入または再生中でなければ0）。
  ({bool inserted, bool playing, bool recording, int position, String message})
  getCmtStatus();

  /// ジョイスティック[index]（0=JS1、1=JS2）の直接入力を[bits]へ更新する
  /// （方向・ボタンのビット定義は`JoystickBit`、M3 INP-04）。都度即座に
  /// 反映される高頻度状態であり、コマンドの連番は持たない
  /// （getFddBankInfo/getFddWriteProtectと同型の直接アクセサ）。
  void setJoystickState(int index, int bits);

  /// ゲスト時間の進行を一時停止・再開する。
  ///
  /// 一時停止中もコマンドは受理・完了する（媒体挿入や状態保存は通る）が、
  /// VMは進まず音声も生成されない。[setJoystickState]と同型の直接
  /// アクセサで、コマンドの連番は持たない。起動前後どちらから呼んでも
  /// よく、値は次の[start]にも残る。
  void setPaused(bool paused);

  /// 観測値を読み出す。
  EmulatorStats readStats();

  /// マスター音量を変える（0.0〜1.0、design.md 12.4）。
  ///
  /// 音声を組み立てていないセッションでは何もしない。
  void setVolume(double volume);

  /// FDD機構音のうち読み書き音（ホスト側合成、AUD-04）の有効・無効を
  /// 変える。
  ///
  /// ブリッジを経由しないホスト側のみの処理で、音声を組み立てていない
  /// セッションでは何もしない。シーク音・ヘッド音は[setFddNoiseEnabled]。
  void setFddMechanicalSoundEnabled(bool enabled);

  /// FDD機構音のうち読み書き音の音量を変える（0.0〜1.0、AUD-04）。
  ///
  /// シーク音・ヘッド音の音量は[setSoundChannelVolume]の
  /// [SoundChannel.fddMechanism]（コアのch9）で別に変える。
  void setFddMechanicalSoundVolume(double volume);

  /// FDD機構音のうちシーク音・ヘッドロード／アンロード音（コアが
  /// ブリッジの合成WAVを鳴らす、AUD-04）の有効・無効を設定し、コマンドの
  /// 連番を返す。新しいセッションの既定は有効。
  Future<int> setFddNoiseEnabled(bool enabled);

  /// 最終ミキサー直後のPCMを[filePath]へWAV録音開始する（AUD-06）。
  ///
  /// 既に録音中、またはファイルを開けない場合は`false`を返す。音声を
  /// 組み立てていないセッションでは常に`false`を返す。
  Future<bool> startRecording(String filePath);

  /// 録音を止め、WAVヘッダーを確定してファイルを閉じる（AUD-06）。
  /// 録音中でなければ何もしない。
  Future<void> stopRecording();

  /// 現在録音中かどうか（AUD-06）。キュー飽和で録音側が自発的に止めた
  /// 場合もここへ反映される。
  bool get isRecordingActive;

  /// 画面を受け取る Texture を用意し、そのIDを返す。
  ///
  /// 呼ぶたびに新しいIDを作るのではなく、すでにあればそれを返す。
  /// 解除は [detachVideoTexture] で行い、[dispose] は先に解除する。
  /// 順序を守らないと描画スレッドが解放済みのセッションを読む
  /// （design.md 5.1 の終了順序）。
  Future<int> attachVideoTexture();

  /// Texture を解除する。冪等。
  Future<void> detachVideoTexture();

  /// セッションを破棄する。以後この実体は使えない。冪等。
  Future<void> dispose();
}
