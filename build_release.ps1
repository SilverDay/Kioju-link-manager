# Build script for creating release packages
# Run this on Windows to build Windows installers

$ErrorActionPreference = "Stop"

# Get version from pubspec.yaml
$version = (Select-String -Path "pubspec.yaml" -Pattern "version:\s*(.+)").Matches.Groups[1].Value.Trim()
Write-Host "Building Kioju Link Manager version $version" -ForegroundColor Cyan

# Create dist directory
New-Item -ItemType Directory -Force -Path "dist" | Out-Null

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "Building Windows Release" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow

Write-Host "Building Windows app..." -ForegroundColor Green
flutter build windows --release

Write-Host "Creating MSIX installer..." -ForegroundColor Green
flutter pub run msix:create

# Copy to dist folder
$msixSource = "build\windows\x64\runner\Release\kioju_link_manager.msix"
$msixDest = "dist\kioju_link_manager-$version-windows.msix"

if (Test-Path $msixSource) {
    Copy-Item $msixSource $msixDest -Force
    Write-Host "✅ Windows MSIX created: $msixDest" -ForegroundColor Green
} else {
    Write-Host "❌ MSIX file not found at $msixSource" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "Creating Windows Portable ZIP" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow

$releaseFolder = "build\windows\x64\runner\Release"
$zipDest = "dist\kioju_link_manager-$version-windows-portable.zip"

if (Test-Path $releaseFolder) {
    Write-Host "Creating portable ZIP archive..." -ForegroundColor Green
    Compress-Archive -Path "$releaseFolder\*" -DestinationPath $zipDest -Force
    Write-Host "✅ Windows Portable ZIP created: $zipDest" -ForegroundColor Green
} else {
    Write-Host "❌ Release folder not found at $releaseFolder" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "Build Summary" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "Version: $version" -ForegroundColor Cyan
Write-Host ""
Write-Host "Created packages:" -ForegroundColor Green

if (Test-Path "dist") {
    Get-ChildItem "dist" | ForEach-Object {
        $size = if ($_.Length -gt 1MB) {
            "{0:N2} MB" -f ($_.Length / 1MB)
        } else {
            "{0:N2} KB" -f ($_.Length / 1KB)
        }
        Write-Host "  $($_.Name) - $size" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Test the installers on Windows" -ForegroundColor White
Write-Host "2. Build macOS DMG on a Mac (run build_release.sh)" -ForegroundColor White
Write-Host "3. Create a GitHub release for version $version" -ForegroundColor White
Write-Host "4. Upload all installers to the release" -ForegroundColor White
Write-Host "5. Update release notes with changelog" -ForegroundColor White
Write-Host ""
Write-Host "Note: macOS and Linux builds require their respective platforms" -ForegroundColor Yellow
