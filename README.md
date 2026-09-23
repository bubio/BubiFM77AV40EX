# BubiFM77AV40EX

<p align="center">
  <img src="assets/branding/app_icon.png" alt="BubiFM77AV40EX" width="128" height="128">
</p>

[English](README.en.md)

FUJITSU FM77AV40EX のエミュレーターです。マルチプラットフォームです。


<p align="center">
  <a href="https://github.com/bubio/BubiFM77AV40EX/releases/latest">
    <img src="https://img.shields.io/github/v/release/bubio/BubiFM77AV40EX" alt="Latest Release">
  </a>
  <a href="https://github.com/bubio/BubiFM77AV40EX/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/bubio/BubiFM77AV40EX" alt="License">
  </a>
  <a href="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/ci.yml">
    <img src="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/build-macos.yml">
    <img src="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/build-macos.yml/badge.svg" alt="macOS">
  </a>
  <a href="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/build-windows.yml">
    <img src="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/build-windows.yml/badge.svg" alt="Windows">
  </a>
  <a href="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/build-linux.yml">
    <img src="https://github.com/bubio/BubiFM77AV40EX/actions/workflows/build-linux.yml/badge.svg" alt="Linux">
  </a>
  <a href="https://github.com/bubio/BubiFM77AV40EX/releases/latest">
    <img src="https://img.shields.io/github/downloads/bubio/BubiFM77AV40EX/total.svg" alt="Downloads">
  </a>
</p>

## BubiFM77AV40EXとは
---
BubiFM77AV40EXは、武田俊也さんの [Common Source Code Project](https://takeda-toshiya.my.coocan.jp/common/index.html) に含まれる eFM77AV40EX のエミュレーションコアを使った、FM77AV40EX のマルチプラットフォームエミュレータです。

エミュレーションコアには手を加えず、Flutter で作ったフロントエンドから FFI で呼び出しています。macOS、Windows、Linux に対応しています。

UIは日本語と英語に対応しています。

<p align="center">
  <img width="752" src="docs/Screenshot.png" alt="BubiFM77AV40EX Screenshot">
</p>

<br />

## インストール方法
---

[リリース](https://github.com/bubio/BubiFM77AV40EX/releases/latest)からお手持ちの環境にあった実行ファイルをダウンロードしてください。ファイル名は `BubiFM77AV40EX-<version>-<platform>-<arch>.<ext>` です。

| プラットフォーム | 最小OSバージョン | 形式 | アーキテクチャ |
| --- | --- | --- | --- |
| macOS | macOS 13.5 Ventura | `.dmg` | `apple-silicon`, `intel` |
| Windows | Windows 10 | `.zip` | `x64` |
| Linux（Debian / Ubuntu） | Ubuntu 24.04以降 | `.deb` | `amd64`, `arm64` |
| Linux（Fedora / RHEL / openSUSE） | - | `.rpm` | `x86_64`, `aarch64` |
| Linux（ポータブル） | - | `.AppImage` | `x86_64`, `aarch64` |

<br />

- **macOS:** DMGを開いて`BubiFM77AV40EX.app`を`アプリケーション`フォルダに移動するなどして実行してください。署名・公証をしていないため、初回起動時にブロックされた場合は、`システム設定`の`プライバシーとセキュリティ`から開くことを許可してください。
- **Windows:** ZIPを展開し、`BubiFM77AV40EX.exe`を実行してください。
- **Linux:** GTK 3とALSAのライブラリが必要です。deb、rpmはパッケージマネージャーでインストールしてください。AppImageは実行権限を付けてそのまま実行できます。

<br />

## ROMファイル
---
ROMファイルは同梱していません。実機から吸い出したROMをご用意ください。

| ファイル名 | サイズ | 用途 |
| --- | --- | --- |
| `INITIATE.ROM` | 8KB | 起動必須 |
| `SUBSYS_A.ROM` | 8KB | 起動必須 |
| `SUBSYS_B.ROM` | 8KB | 起動必須 |
| `SUBSYS_C.ROM` | 10KB | 起動必須 |
| `SUBSYSCG.ROM` | 8KB | 起動必須 |
| `EXTSUB.ROM` | 48KB | 起動必須 |
| `FBASIC302.ROM`（または`FBASIC301.ROM` / `FBASIC300.ROM` / `FBASIC30.ROM`） | 31KB | BASICモードでの起動に必要 |
| `KANJI1.ROM`（または`KANJI.ROM`） | 128KB | 第1水準漢字（任意） |
| `KANJI2.ROM` | 128KB | 第2水準漢字（任意） |
| `DICROM.ROM` | 256KB | 辞書（任意） |

F-BASIC ROMがない場合も、DOSモードで起動できます。

<br />

### 配置場所
ROMファイルの配置場所は以下になります（一度、アプリケーションを起動するとフォルダが作成されます）。アプリケーションのROM確認画面からフォルダを開くこともできます。

| OS | 配置場所 |
| --- | --- |
| macOS | `~/Library/Application Support/BubiFM77AV40EX/roms` |
| Windows | `%APPDATA%\BubiFM77AV40EX\roms` |
| Linux | `~/.local/share/BubiFM77AV40EX/roms` |

<br />

## 使用方法
---

### コマンドライン起動

最大2個のディスクイメージをコマンドラインで指定できます。指定順にFD1、FD2へ挿入されます。

```shell
BubiFM77AV40EX [-option ...] image-file [image-No] [image-file [image-No]]

BubiFM77AV40EX game.d88
BubiFM77AV40EX game.d88 2
BubiFM77AV40EX system.d88 data.d88
BubiFM77AV40EX -dos -x2 game.d88
```

`image-No` はD88などのマルチバンクイメージのバンク番号で、1始まりです。マルチバンクイメージを1つだけ指定してバンクを省略した場合は、バンク1をFD1、バンク2（あれば）をFD2に挿入します。

オプション（大文字・小文字は区別しません。同じ設定を複数指定した場合は最後のものが有効です）:

```text
-basic / -dos                       ブートモード
-2mhz / -1.2mhz                     CPU速度
-x1 / -x2 / -x4 / -x8 / -x16        速度倍率
-fullspeed                          速度制限なし
-cycle_steal / -no_cycle_steal      サイクルスチール
-extram / -no_extram                拡張RAM
-hsync / -no_hsync                  HSYNC同期
-h / -help / --help                 ヘルプを表示して終了
```

終了コードは、0=成功またはヘルプ表示、2=構文エラー、3=メディアエラー、4=ROM／起動エラー、5=内部エラーです。

<br />

## ビルド方法
---

どのプラットフォームでも [FVM](https://fvm.app/) と Git が必要です。Flutterは必ずFVM経由で実行し、バージョンは`.fvmrc`で固定しています。エミュレーションコアは、ビルドスクリプトがGitサブモジュールとして固定リビジョンを取得します。

```shell
git clone https://github.com/bubio/BubiFM77AV40EX.git
cd BubiFM77AV40EX
fvm install
```

開発中は以下で実行・検査できます。

```shell
fvm flutter run -d <macos|windows|linux>
./scripts/check.sh   # 書式・静的解析・テスト
```

<br />

### macOS

#### 必要なもの

Xcode、[Homebrew](https://brew.sh/)でインストールしたCMakeとCocoaPodsが必要です。

```shell
brew install cmake cocoapods
```

#### ビルド

```shell
./scripts/build_macos.sh
```

`build/macos/Build/Products/Release/BubiFM77AV40EX.app`が作成されます。

DMGを作成する場合は以下を実行します。`build/macos/dmg`フォルダにApple Silicon版とIntel版のDMGが作成されます。

```shell
./scripts/build_macos_dmg.sh arm64 x86_64
```

<br />

### Windows

#### 必要なもの

Visual Studio 2022（C++によるデスクトップ開発）とGit for Windowsが必要です。

#### ビルド

Git Bashでエミュレーションコアを取得してから、PowerShellでビルドします。

```shell
./scripts/build_native_core.sh fetch
```

```powershell
pwsh scripts/build_windows.ps1
```

`build/windows/dist`フォルダにZIPファイルが作成されます。

<br />

### Linux

#### 必要なもの

**Debian系（Ubuntuなど / apt）:**

```shell
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libasound2-dev liblzma-dev libstdc++-12-dev
```

パッケージを作成する場合は、`imagemagick`、`desktop-file-utils`、`rpm`も必要です。

#### ビルド

ビルドしたマシンと同じアーキテクチャ（x86_64 / arm64）向けに作成します。

```shell
./scripts/build_linux.sh release
./scripts/package_linux.sh
```

`build/linux/dist`フォルダにdeb、rpm、AppImageファイルが作成されます。`./scripts/package_linux.sh deb`のように形式を指定することもできます。

<br />

## ライセンス
---

GPLv2です。エミュレーションコアである Common Source Code Project のライセンスに準じます。詳細は[LICENSE](LICENSE)を参照してください。

<br />

## 謝辞
---

エミュレーションコアを公開してくださっている武田俊也さんにお礼申し上げます。
