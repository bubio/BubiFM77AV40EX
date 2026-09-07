/// アプリケーションデータ領域の論理的な位置。
///
/// design.md 11.2/11.3 の`AppDataPaths`境界。実際の物理パスは
/// プラットフォームアダプターがOS APIから取得する。feature層は
/// ここで得た識別子だけを扱い、パス文字列を組み立てない。
abstract interface class AppDataPaths {
  /// コアがアプリケーションデータを置く位置（アプリケーションデータ領域の
  /// ルート）のOSパス。
  ///
  /// コアの`cpp_homedir`に渡す。既定に任せると`~/CommonSourceCodeProject/`を
  /// 作ってしまい、design.md 11.3 と食い違う。
  Future<String> coreHomeDirectoryPath();

  /// 利用者がROMを置くフォルダー（`roms/`）のOSパス。
  ///
  /// アプリは選ばせず、この位置に固定する（specification.md 6）。
  /// 利用者へ案内するため、UIに表示してよい唯一のパスである。
  Future<String> romsDirectoryPath();

  /// スクリーンショットの保存先（design.md 11.4）。
  ///
  /// デスクトップではOSのPicturesディレクトリ配下にアプリ名の
  /// フォルダーを作る。対応していないOSでは`null`（VID-05）。
  /// feature層が`dart:io`へ直接触れずに書き出せるよう、パス文字列では
  /// なく[AppDataLocation]を返す（design.md 3.1）。
  Future<AppDataLocation?> pictureFile(String fileName);

  /// 音声録音の保存先パス（design.md 11.4、AUD-06）。
  ///
  /// デスクトップではOSのMusicディレクトリ配下にアプリ名のフォルダーを
  /// 作る。対応していないOSでは`null`。ストリーミング書込み
  /// （`WavRecorder`）が`dart:io`で直接開くため、[pictureFile]と異なり
  /// [AppDataLocation]ではなく生のOSパス文字列を返す
  /// （[romsDirectoryPath]と同じ扱い）。
  Future<String?> musicFilePath(String fileName);

  /// 状態スロット（`states/slot-N/`）を表すハンドル（STA-01）。
  Future<StateSlotLocation> stateSlot(int slotIndex);

  /// 辞書学習データ（`dictionary/USERDIC.DAT`）。
  Future<AppDataLocation> dictionaryUserData();

  /// キーマップ定義（`keymaps/`）。
  Future<AppDataLocation> keymaps();

  /// 履歴（`history.json`）。
  Future<AppDataLocation> history();
}

/// 1つの状態スロット（design.md 337「`states/slot-N/state.bin`と
/// `metadata.json`を一組とし…」に`thumbnail.png`を加えた3ファイル構成）を
/// 束ねるハンドル。
///
/// `metadata.json`の存在をスロットが有効かどうかの判定基準にする
/// （保存は thumbnail → state → metadata の順で書き、途中で失敗しても
/// 読めるが壊れたスロットを残さないため）。
class StateSlotLocation {
  const StateSlotLocation({
    required this.state,
    required this.metadata,
    required this.thumbnail,
  });

  /// コアの状態バイナリ（`state.bin`）。
  final AppDataLocation state;

  /// アプリ版・コア識別子・作成日時・ディスク表示名等（`metadata.json`）。
  final AppDataLocation metadata;

  /// 保存時点の画面のサムネイル（`thumbnail.png`）。省略可能。
  final AppDataLocation thumbnail;
}

/// 永続データの位置と原子的な書込み手段。
abstract interface class AppDataLocation {
  /// コアへ渡すためのOSパス。ログへ出す場合は短縮する。
  String get nativePath;

  Future<bool> exists();

  Future<List<int>> read();

  /// 同一ディレクトリの一時ファイルへ書いてから原子的に置換する。
  Future<void> writeAtomic(List<int> bytes);

  Future<void> delete();
}
