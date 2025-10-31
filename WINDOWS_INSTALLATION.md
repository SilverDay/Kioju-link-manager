# Windows Installation Guide

## Overview
This guide explains how to install and use the Kioju Link Manager Windows installer (MSIX package).

## Installation

### Option 1: Install from MSIX Package (Recommended for End Users)

The MSIX installer is located at:
```
build\windows\x64\runner\Release\kioju_link_manager.msix
```

**Size:** ~23 MB

#### Steps to Install:

1. **Download or locate the MSIX file**
   - If downloaded, locate `kioju_link_manager.msix`
   - If building locally, it's in `build\windows\x64\runner\Release\`

2. **Install the certificate (First-time only)**
   - Right-click on `kioju_link_manager.msix`
   - Select "Properties"
   - Go to "Digital Signatures" tab
   - Select the signature and click "Details"
   - Click "View Certificate"
   - Click "Install Certificate"
   - Choose "Local Machine" or "Current User"
   - Place certificate in "Trusted Root Certification Authorities"
   - Complete the wizard

3. **Install the application**
   - Double-click `kioju_link_manager.msix`
   - Click "Install"
   - Wait for installation to complete
   - The app will appear in your Start Menu

### Option 2: Run Without Installation (Portable)

If you prefer not to install, you can run the executable directly:

1. Navigate to `build\windows\x64\runner\Release\`
2. Run `kioju_link_manager.exe`
3. All required DLLs and dependencies are in this folder

## Building the Installer Yourself

If you want to build the MSIX installer from source:

### Prerequisites
- Flutter SDK installed and configured
- Windows 10/11 SDK installed
- Visual Studio 2019 or later with C++ desktop development tools

### Build Steps

1. **Clone the repository:**
   ```powershell
   git clone https://github.com/silverday/Kioju-link-manager.git
   cd Kioju-link-manager
   ```

2. **Get dependencies:**
   ```powershell
   flutter pub get
   ```

3. **Build the Windows release:**
   ```powershell
   flutter build windows --release
   ```

4. **Create the MSIX installer:**
   ```powershell
   flutter pub run msix:create
   ```

5. **Locate the installer:**
   The MSIX file will be created at:
   ```
   build\windows\x64\runner\Release\kioju_link_manager.msix
   ```

## Uninstallation

### If installed via MSIX:
1. Open Settings → Apps → Apps & features
2. Search for "Kioju Link Manager"
3. Click and select "Uninstall"

### If running portable version:
Simply delete the Release folder containing the executable.

## Troubleshooting

### "Windows protected your PC" message
This appears because the app uses a self-signed certificate. Click "More info" and then "Run anyway" to proceed.

### Certificate Trust Issues
If you encounter certificate errors:
1. Install the certificate as described in the installation steps
2. Or build and sign with your own certificate for production use

### App won't start
- Ensure you have the latest Visual C++ Redistributable installed
- Check Windows Event Viewer for error details
- Verify all DLL files are present in the Release folder

## Configuration

### MSIX Settings
The installer is configured in `pubspec.yaml` under `msix_config`:
- **Display Name:** Kioju Link Manager
- **Publisher:** SilverDay
- **Version:** 2.0.0.0
- **Capabilities:** Internet Client (required for API access)

### Customizing the Build
To modify the installer:
1. Edit the `msix_config` section in `pubspec.yaml`
2. Replace `assets/kioju-icon.png` with your own icon
3. Rebuild using `flutter pub run msix:create`

## Distribution

### For Testing and Personal Use
The generated MSIX with a self-signed certificate is suitable for:
- Personal use
- Internal distribution within an organization
- Testing purposes

### For Public Distribution
For distributing to the general public, you should:
1. Obtain a code signing certificate from a trusted Certificate Authority
2. Sign the MSIX package with your certificate
3. Or publish through the Microsoft Store

## Microsoft Store Publication (Optional)

To publish on the Microsoft Store:
1. Create a Microsoft Partner Center account
2. Reserve your app name
3. Configure the MSIX with your Store identity
4. Upload the MSIX package through Partner Center
5. Complete the store listing and submit for review

## System Requirements

- **Operating System:** Windows 10 version 1809 or later, Windows 11
- **Architecture:** x64
- **Disk Space:** ~50 MB
- **Internet:** Required for syncing with Kioju API

## Features

The Windows installer includes:
- ✅ Desktop integration (Start Menu shortcut)
- ✅ Automatic updates support (when signed properly)
- ✅ Clean uninstallation
- ✅ All app dependencies included
- ✅ Icon integration
- ✅ Modern Windows app packaging

## Support

For issues or questions:
- GitHub Issues: https://github.com/silverday/Kioju-link-manager/issues
- Check the main README.md for general app documentation

## Version Information

- **App Version:** 2.0.0+1
- **MSIX Version:** 2.0.0.0
- **Build Date:** October 31, 2025
