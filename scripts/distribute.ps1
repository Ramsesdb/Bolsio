# Build release APK then upload to Firebase App Distribution
Set-Location $PSScriptRoot\..

Write-Host "Building release APK (play flavor)..."
flutter build apk --release --flavor play --split-per-abi --target-platform android-arm64

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter build failed"
    exit 1
}

# Extract version from pubspec.yaml (strip build number, e.g. "1.0.0+1" -> "1.0.0")
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s+(.+)').Matches[0].Groups[1].Value -replace '\+.*',''
$source = "build\app\outputs\flutter-apk\app-play-arm64-v8a-release.apk"
$dest   = "build\app\outputs\flutter-apk\Nitido-${version}.apk"

Write-Host "Renaming APK: $source -> $dest"
Copy-Item -Path $source -Destination $dest -Force

if (-not (Test-Path $dest)) {
    Write-Error "Renamed APK not found at $dest"
    exit 1
}

Write-Host "Uploading $dest to Firebase App Distribution..."
Set-Location android
.\gradlew.bat appDistributionUploadPlayRelease
$result = $LASTEXITCODE
Set-Location ..

if ($result -ne 0) {
    Write-Error "Upload to App Distribution failed"
    exit 1
}

Write-Host "Done! Testers will receive an email notification."
