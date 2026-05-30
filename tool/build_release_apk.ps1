# Release 小包体积打包脚本
# - 按 CPU 架构拆分 APK（arm64 / armeabi-v7a 各一份，比通用 APK 小很多）
# - Dart 代码混淆 + 剥离调试符号（符号文件保存在 build/app/outputs/symbols，勿随 APK 分发）
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$symbolsDir = Join-Path $root "build\app\outputs\symbols"
New-Item -ItemType Directory -Force -Path $symbolsDir | Out-Null

Write-Host ">>> flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host ">>> flutter build apk --release --split-per-abi --target-platform=android-arm,android-arm64 --obfuscate --split-debug-info=$symbolsDir"
flutter build apk --release --split-per-abi --target-platform=android-arm,android-arm64 --obfuscate --split-debug-info="$symbolsDir"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "完成。输出目录:"
Write-Host "  build\app\outputs\flutter-apk\"
Write-Host "推荐安装 app-arm64-v8a-release.apk（绝大多数现网手机）。"
Write-Host "仅打 arm 包，不含 x86/x86_64 模拟器架构。"
Write-Host "调试符号目录（崩溃还原用，勿打包进 APK）: $symbolsDir"
