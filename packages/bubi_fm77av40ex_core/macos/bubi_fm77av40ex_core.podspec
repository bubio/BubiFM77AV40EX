#
# FFIプラグインのmacOS定義。
#
# ネイティブのビルドは script_phase から CMake（native/CMakeLists.txt）で行う。
# ここはビルド生成物をアプリへリンクさせるための薄い層に留める
# （design.md 16.1）。
#
Pod::Spec.new do |s|
  s.name             = 'bubi_fm77av40ex_core'
  s.version          = '0.1.0'
  s.summary          = 'FFI bindings to the eFM77AV40EX emulation core.'
  s.description      = <<-DESC
BubiFM77AV40EX が使う eFM77AV40EX エミュレーションコアの FFI プラグイン。
                       DESC
  s.homepage         = 'https://github.com/bubio/BubiFM77AV40EX'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'bubio' => 'bubio66@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  # Swift から C ABI を見るため、pod の public header にしておく。
  # DEFINES_MODULE=YES と合わせて umbrella header に載る。
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.5'
  s.swift_version = '5.0'

  # アプリターゲットからは PODS_TARGET_SRCROOT が使えないため、
  # Flutter が作る ephemeral のシンボリックリンク経由で参照する。
  plugin_root = '${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/bubi_fm77av40ex_core/macos'

  # 生成物は :output_files で宣言する。宣言がないと、-force_load の入力が
  # 「まだ存在しないのに生産者がいない」と判定され、初回のクリーンビルドが
  # このフェーズを実行する前に失敗する。
  # :always_out_of_date を付けて毎回走らせる（CMakeの増分判定により、
  # 変更がなければ即座に終わる）。付けないとソース変更後も古い成果物が
  # リンクされ続ける。
  s.script_phase = {
    :name => 'Build eFM77AV40EX core with CMake',
    :script => <<-SCRIPT,
      export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
      bash "${PODS_TARGET_SRCROOT}/build_cmake.sh"
    SCRIPT
    :execution_position => :before_compile,
    :output_files => ['${PODS_TARGET_SRCROOT}/cmake_build/macosx/libbubi_fm77av40ex_core_plugin.a'],
    :always_out_of_date => '1',
  }

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # PODS_TARGET_SRCROOT は ephemeral のシンボリックリンク越しの位置を指す。
    # そこから '..' を辿ると .symlinks/ へ抜けてしまい、リポジトリ側へ戻れない。
    # 実在するディレクトリである PODS_ROOT を基準にする。
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/../../native/bridge/include',
    # pod は use_frameworks! により動的フレームワークになる。C ABI の実体は
    # アプリ本体が -force_load で取り込む1つだけとし、ここでは持たない。
    # ここでも .a をリンクすると、コアがプロセス内に2つできる。
    # cpp_homedir のようなプロセス全域の状態が二重になり、Dart が握る
    # セッションと Swift が読むセッションが別物になる。
    # 実体はアプリ本体が -export_dynamic で公開しているため、
    # 読込み時に解決させる。
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-undefined,dynamic_lookup',
  }

  # user_target_xcconfig: アプリターゲットのリンカ設定。
  # FFIのシンボルを必要とするのはアプリ本体であり、pod の静的ライブラリは
  # リンカフラグを無視するため、-force_load はここに置く。
  #
  # -force_load だけでは足りない。実行ファイルのリンクでは
  # DEAD_CODE_STRIPPING が既定で有効で、Dartから動的に引くだけの
  # bfm_* はどこからも参照されないため丸ごと捨てられる。
  # -export_dynamic で全グローバルシンボルを動的シンボル表へ載せ、
  # dead strip の起点にする。これがないと Release ビルドで
  # DynamicLibrary.process() の lookup が実行時に失敗する。
  s.user_target_xcconfig = {
    # umbrella header は pod を取り込む側（アプリ本体）でも解決される。
    # pod_target_xcconfig はそこまで届かないため、同じ探索パスをここにも置く。
    # これがないと Runner のモジュール解決で bubi_fm77av.h が見つからない。
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/../../native/bridge/include',
    'OTHER_LDFLAGS' => "$(inherited) -force_load #{plugin_root}/cmake_build/macosx/libbubi_fm77av40ex_core_plugin.a -Wl,-export_dynamic -lc++",
    # Releaseビルドで DynamicLibrary.process() から引けるよう、
    # 公開シンボルを strip させない。可視性属性（BFM_API）だけでは足りない。
    'STRIP_STYLE' => 'debugging',
    'DEBUG_INFORMATION_FORMAT' => 'dwarf-with-dsym',
  }
end
