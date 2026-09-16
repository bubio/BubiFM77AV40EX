# zlib 1.2.11（Windows専用の外部依存）

`native/core/upstream/src/fileio.cpp`は、Windows上でMSVC互換コンパイラ
（`_MSC_VER`が定義される環境。clangのMSVC ABI互換モードを含む）を検出すると
`native/core/upstream/src/common.h`が`USE_ZLIB`を自動的に有効化し、
gzip圧縮ROM/イメージの透過展開にzlibのgzip API（gzopen/gzclose/gzread等）を
無条件で要求する（コアは無改変、変更しない）。

この`USE_ZLIB`はmacOS/Linux（`_MSC_VER`が定義されない）では有効化されず、
`native/core/upstream/src/zlib-1.2.11/`にはヘッダー（`zlib.h`/`zconf.h`）
だけがコアのpinned revisionに含まれ、実装（`.c`）は含まれていなかった
（development_plan.md M5の記録を参照）。

このディレクトリは、コアのソース（`native/core/upstream/`、Gitサブモジュール、
無改変方針）とは独立したプロジェクト管理下の場所へ、zlib 1.2.11の実装一式を
そのまま配置したもの。コアの`fileio.cpp`が相対includeで期待する
`zlib-1.2.11/zlib.h`という配置に合わせるため、`native/CMakeLists.txt`が
このディレクトリを追加のインクルードパスとしてWindowsビルド時だけ登録する
（`native/bridge/osd`を`"sdl/osd.h"`解決のため追加しているのと同じ手法）。

- 取得元: https://github.com/madler/zlib/archive/refs/tags/v1.2.11.tar.gz
- バージョン: 1.2.11（`native/core/upstream/src/zlib-1.2.11/zlib.h`が
  既に固定しているバージョンと一致させた。同ヘッダーの内容は
  改行コード（CRLF/LF）を除き本ディレクトリの`zlib.h`と同一であることを
  確認済み）
- ライセンス: zlib License（`zlib.h`冒頭のコメントに全文を含む。
  改変・再配布・商用利用を許可する非コピーレフトライセンスで、
  改変の明示と本notice保持だけを求める）
- 1バイトも改変していない（アーカイブから展開したままの内容）

Windowsパッケージング作業（development_plan.md M5「必要なDLLとデータを
ZIPへ相対配置」）時、macOS版の`macos/Runner/Credits.rtf`に相当する
帰属表示にzlibを追加すること。
