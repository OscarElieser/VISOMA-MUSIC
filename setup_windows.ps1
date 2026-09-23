$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter no está disponible en PATH. Instala Flutter y Android Studio antes de continuar.'
}

flutter create --platforms=android .
if ($LASTEXITCODE -ne 0) { throw 'Falló la creación del proyecto Android.' }

$manifestPath = Join-Path $PSScriptRoot 'android/app/src/main/AndroidManifest.xml'
$manifest = Get-Content -Raw -Encoding UTF8 $manifestPath
if ($manifest -notmatch 'android.permission.INTERNET') {
    $manifest = $manifest.Replace('<application', '<uses-permission android:name="android.permission.INTERNET" />' + "`r`n    " + '<application')
}
$manifest = [regex]::Replace($manifest, 'android:label="[^"]*"', 'android:label="VÍSOMA MUSIC"')
Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron descargar las dependencias.' }
dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { throw 'No se pudo aplicar el icono oficial de VÍSOMA MUSIC.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'El análisis de Dart falló; revisa los mensajes anteriores.' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Las pruebas fallaron; revisa los mensajes anteriores.' }
flutter build apk --debug
if ($LASTEXITCODE -ne 0) { throw 'No se pudo construir el APK de prueba.' }

Write-Host 'APK de prueba: build/app/outputs/flutter-apk/app-debug.apk'
