# Windows成果物（x64のGUI .exe入り配布ZIP）のビルド入口。ローカルとCIで同じ手順を使う。
#
# 事前に scripts/build_native_core.sh fetch（Git Bash）でコアを取得しておくこと。
# PowerShellからbashを呼ぶとWSLのbashを掴むことがあるため、ここでは取得しない。
#
#   usage: pwsh scripts/build_windows.ps1
#   出力 : build/windows/dist/BubiFM77AV40EX-<version>-windows-x64.zip
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location (Split-Path -Parent $PSScriptRoot)

$AppName = 'BubiFM77AV40EX'

function Invoke-Step {
  param([string]$Command, [string[]]$Arguments)
  Write-Host "==> $Command $($Arguments -join ' ')"
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Command が終了コード $LASTEXITCODE で失敗しました"
  }
}

if (-not (Test-Path 'native/core/upstream/src/emu.h')) {
  throw 'コアが未取得です。Git Bashで scripts/build_native_core.sh fetch を実行してください。'
}

$Version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value
if (-not $Version) {
  throw 'pubspec.yamlからバージョンを取得できません'
}

Invoke-Step fvm @('flutter', 'pub', 'get')
Invoke-Step fvm @('flutter', 'build', 'windows', '--release')

$Release = "build/windows/x64/runner/Release"
$Exe = Join-Path $Release "$AppName.exe"
if (-not (Test-Path $Exe)) {
  throw "expected executable not found: $Exe"
}

# --- 通常起動でコンソールを出さないGUIサブシステムかを確かめる（design.md 15.2） ---
# PEオプショナルヘッダーのSubsystem（PEシグネチャから0x5C）が2ならGUI。
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Exe))
$peOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
$subsystem = [System.BitConverter]::ToUInt16($bytes, $peOffset + 0x5C)
if ($subsystem -ne 2) {
  throw "実行ファイルが /SUBSYSTEM:WINDOWS ではありません（Subsystem=$subsystem）"
}
Write-Host '==> サブシステム検査: WINDOWS (GUI)'

# --- 配布ZIPを組み立てる ---
$Staging = "build/windows/dist/$AppName"
$Zip = "build/windows/dist/$AppName-$Version-windows-x64.zip"
if (Test-Path 'build/windows/dist') {
  Remove-Item -Recurse -Force 'build/windows/dist'
}
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
Copy-Item -Recurse -Path "$Release/*" -Destination $Staging

# Flutterのrunnerは Visual C++ ランタイムを同梱しない。展開先の環境に
# 依存しないよう、ビルドに使ったVisual StudioのredistからDLLを添える。
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$crtDir = Get-ChildItem -Directory -Path (Join-Path $vsPath 'VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT') |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crtDir) {
  throw 'Visual C++ ランタイムのredistが見つかりません'
}
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  Copy-Item -Path (Join-Path $crtDir.FullName $dll) -Destination $Staging
}
Write-Host "==> VC++ ランタイム: $($crtDir.FullName)"

Invoke-Step fvm @('dart', 'run', 'tool/collect_licenses.dart', "$Staging/THIRD_PARTY_LICENSES.txt")
Copy-Item -Path 'LICENSE' -Destination "$Staging/LICENSE.txt"

Compress-Archive -Path $Staging -DestinationPath $Zip
Write-Host "==> built: $Zip"
