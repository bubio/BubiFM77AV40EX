# BubiFM77AV40EX

[Common Source Code Project](https://takeda-toshiya.my.coocan.jp/common/index.html)のeFM77AV40EXをマルチプラットフォームで動作できるようにするプロジェクト。
BubiC-8801MAやBubiX1turboZと同じように、eFM77AV40EXのエミュレーションコアをそのまま使い、アプリケーションを独自に実装する。



## この文書について

- この文書は青写真（雑な要求仕様）としての入力文書になるため内容を編集してはいけません。
- 開発が進み事情が変化した場合、必ずしもこの文書の内容に従う必要はない。



## 対応プラットフォーム

Android、iOS、Linux、macOS、Windowsを対象とします。

#### サポートするOSバージョンと優先順位

1. macOS: 13.5以上 / Intel / Appleシリコン
2. Linux: Ubuntu 24.04以上 / amd64 / arm64
3. Windows: Windows 11以上 / x64 / arm64
4. Android: Android 13 (SDK33 )以上
5. iOS: iOS 26.0以上

macOSでの開発が完了したのちに、他プラットフォームへ広げていきます。

#### 頒布方法と形式

GitHubのリリースで頒布します。

1. macOS: dmg形式。/Applicationフォルダへのエイリアスを含む。
2. Linux: dev, rpm, appimage
3. Windows: zip
4. Android: apk
5. iOS: 実行ファイルでの提供はしない



## 技術スタック

- FVMを介してFlutter を使用します（最新の3.47.2をインストール済み）。
- エミュレーターの音の再生に[flutter_soloud](https://pub.dev/packages/flutter_soloud)を使う。
- 状態管理・依存注入に[flutter_riverpod](https://pub.dev/packages/flutter_riverpod)を使う。



## アーキテクチャ

コアは専用スレッドで動かし、Flutterの描画周期から独立させます。映像、PCM、キー入力などの高頻度データはRiverpodを通しません。

「機能ごとの縦割り」を主体にし、交換可能な技術境界だけ横割りにします。



```
lib/
  app/          # 起動、画面構成、依存注入
  features/     # session、media、debugger、settingsなど
  emulator/     # コアの抽象APIと共通モデル
  platform/     # FFI、WebAssembly、Texture、SoLoud、永続化
  shared/       # 本当に共通なWidgetなど
```

依存方向は次のように固定します。

```
app → features
app → platform（実装の注入のみ）

features → emulator API
features → shared

platform → emulator API
```

各機能では、状態、Controller、Riverpod Providerを一緒に置きます。形式だけのUseCase、Repository、Eventファイルなどは作りません。



## 機能要件

- オリジナルが提供する機能をできる限り実装する。
- ただし使用感向上を狙う。
- GUIはOSネイティブのLook＆Feelがベター。例えば、macOSのメニューなど。
- UI言語は日本語、英語に対応する。
- メニューの構成は、BubiX1turboZに合わせる。
- ステータスバーの構成は、BubiC-8801MAに合わせる。
- CLIオプション機能を追加すること。フォーマットはBubilator88と合わせる。
- 設定ファイルなどの置き場所はOSの習慣に従うこと。



## 非機能要件

- Git/GitHubでソースコードを管理する。
- GitHub Actionsを使用したCI/CDワークフローを実施する。
- ビルドはローカルとCIで同等となるようにする。ビルド手順が複雑な場合はスクリプトを用意する。
- 特別な指示がない場合は、mainブランチへ直接コミット、プッシュする。
- 技術ドキュメントは、docs/dev/フォルダの下に作成するものとし、Gitのサブモジュールとする。docs/dev/のリモートは、git@github.com:bubio/dev-docs.git に本プロジェクト用のブランチを作成して管理する（開発ドキュメントの隠蔽が目的）。



## 禁止事項

- SDLパッケージを使ってはいけません。
- eFM77AV40EXのエミュレーションコア部分は変更してはいけません。
- 指示があるまではコミット、プッシュしてはならない。
- ユーザー名を暴露しないようにする。パスは~ /$HOMEなどを用いる。
- README.mdに開発関連の内容を書いてはいけません。



## バージョン番号

- セマンティックバージョニングにします。

- ビルド番号がある場合は1からの連番とします。

  

## ライセンス

- Common Source Code Projectに準じます。



## 参考

- BubiX1turboZ : ~/dev/_Emu/BubiX1turboZ/

- BubiC-8801MA: ~/dev/_Emu/BubiC-8801MA/

- Common Source Code Project: ~/dev/_Emu/Original/common_source_project/

  

## 注意事項

- BIOSファイルが必要になったら相談すること
- 市販ゲームの確認が必要になったら相談すること

