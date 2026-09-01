#
# 利用者が選んだ位置への永続アクセス権を扱うプラグイン（macOS）。
#
Pod::Spec.new do |s|
  s.name             = 'bubi_fm77av40ex_platform'
  s.version          = '0.1.0'
  s.summary          = 'Security-scoped bookmark support for BubiFM77AV40EX.'
  s.description      = <<-DESC
Flutter公式パッケージが覆わない macOS のブックマークAPIを扱う。
                       DESC
  s.homepage         = 'https://github.com/bubio/BubiFM77AV40EX'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'bubio' => 'bubio66@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.5'
  s.swift_version = '5.0'
end
