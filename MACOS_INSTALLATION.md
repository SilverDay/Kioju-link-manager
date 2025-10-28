# macOS Installation Guide

This guide explains how to install and run the Kioju Link Manager on macOS, including solutions for security warnings.

## For Maintainers: Setting Up Code Signing

**Important:** To eliminate security warnings for end users, the app must be properly signed and notarized. This requires:

1. An active **Apple Developer Program** membership ($99/year)
2. A **Developer ID Application** certificate
3. Proper **GitHub Secrets** configuration

### Quick Setup Guide for Maintainers

#### Step 1: Get Apple Developer Credentials

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
2. Create a **Developer ID Application** certificate in your Apple Developer account:
   - Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list)
   - Click the **+** button to create a new certificate
   - Select **Developer ID Application** and follow the prompts
   - Download the certificate and import it into Keychain Access
3. Create an **App-Specific Password** for notarization:
   - Go to [appleid.apple.com](https://appleid.apple.com)
   - Sign in and go to Security > App-Specific Passwords
   - Click **+** to generate a new password
   - Save this password securely

#### Step 2: Export Certificate for GitHub Actions

1. Open **Keychain Access** on macOS
2. Find your **Developer ID Application** certificate
3. Right-click and select **Export "Developer ID Application..."**
4. Save as `.p12` format with a password (remember this password!)
5. Convert to base64 for GitHub:
   ```bash
   base64 -i YourCertificate.p12 | pbcopy
   ```
   This copies the base64-encoded certificate to your clipboard

#### Step 3: Configure GitHub Repository Secrets

Add these secrets to your GitHub repository (Settings > Secrets and variables > Actions):

| Secret Name | Description | How to Get It |
|------------|-------------|---------------|
| `MACOS_CERTIFICATE` | Base64-encoded .p12 certificate | Result from Step 2 |
| `MACOS_CERTIFICATE_PWD` | Password for the .p12 file | Password you set when exporting |
| `MACOS_SIGNING_IDENTITY` | Certificate identity name | e.g., "Developer ID Application: Your Name (TEAMID)" |
| `APPLE_ID` | Your Apple ID email | Your Apple Developer account email |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password | From Step 1.3 |
| `APPLE_TEAM_ID` | Your Apple Team ID | Found in [Apple Developer Membership](https://developer.apple.com/account/#!/membership) |

**To find your signing identity:**
```bash
security find-identity -v -p codesigning
```
Look for a line like: "Developer ID Application: Your Name (TEAM123456)"

#### Step 4: Verify Setup

Once secrets are configured:
1. Push a commit or create a release
2. GitHub Actions will automatically:
   - Sign the app with your Developer ID
   - Enable hardened runtime for security
   - Submit to Apple for notarization
   - Staple the notarization ticket to the app
3. Check the Actions logs to verify successful signing and notarization
4. Download the artifact and verify:
   ```bash
   codesign -dv --verbose=4 kioju_link_manager_flutter.app
   spctl -a -vv kioju_link_manager_flutter.app
   ```

**Expected output when properly signed:**
- Signature shows "Developer ID Application: Your Name"
- `spctl` reports "accepted" and "source=Notarized Developer ID"

---

## Understanding macOS Security

macOS includes a security feature called **Gatekeeper** that helps protect your Mac from malicious software. When you download an application from outside the Mac App Store, you may see a warning message.

### Common Warning Messages

You might see one of these messages:

- **"Apple could not verify 'kioju_link_manager' is free of malware that may harm your Mac or compromise your privacy."**
- **"'kioju_link_manager' can't be opened because it is from an unidentified developer."**
- **"'kioju_link_manager' is damaged and can't be opened. You should move it to the Trash."**

These warnings appear because the app is not signed with an Apple Developer certificate or not notarized by Apple.

## Installation Options

### Option 1: Official Signed Releases (Recommended)

When the project maintainers have set up code signing and notarization:

1. Download the latest release from the [Releases page](https://github.com/SilverDay/Kioju-link-manager/releases)
2. Download the `.dmg` or `.zip` file for macOS
3. If downloaded as `.dmg`:
   - Double-click to mount the disk image
   - Drag the app to your Applications folder
4. If downloaded as `.zip`:
   - Extract the zip file
   - Move `kioju_link_manager_flutter.app` to your Applications folder
5. Double-click to run the app

If the app is properly signed and notarized, it should open without warnings.

### Option 2: Running Unsigned Builds

If you're using an unsigned build or building from source, you'll need to manually approve the app.

#### Method 1: Using System Settings (Recommended)

1. Try to open the app by double-clicking it
2. When you see the security warning, click **"OK"** or **"Cancel"**
3. Open **System Settings** (or **System Preferences** on older macOS versions)
4. Go to **Privacy & Security**
5. Scroll down to the **Security** section
6. You should see a message about `kioju_link_manager_flutter` being blocked
7. Click **"Open Anyway"**
8. Confirm by clicking **"Open"** in the dialog that appears

#### Method 2: Using Right-Click (Alternative)

1. Locate the app in Finder (usually in your Applications folder)
2. **Right-click** (or Control-click) on the app
3. Select **"Open"** from the context menu
4. In the dialog that appears, click **"Open"**

This method bypasses Gatekeeper for this specific app, and you won't be asked again for this app.

#### Method 3: Using Terminal (Advanced)

If the above methods don't work, you can remove the quarantine attribute:

```bash
# Navigate to where you downloaded the app
cd ~/Applications  # or wherever the app is located

# Remove the quarantine attribute
xattr -cr kioju_link_manager_flutter.app

# Verify the quarantine attribute is removed
xattr -l kioju_link_manager_flutter.app
```

After removing the quarantine attribute, try opening the app again.

#### Method 4: Using the Launch Script (Easiest)

The repository includes a helper script that automates the quarantine removal:

```bash
# From the project directory
./launch-macos.sh
```

This script will:
- Locate your app automatically
- Check for quarantine attributes
- Offer to remove them with your permission
- Verify the code signature
- Launch the app

## Building from Source

If you're building the app from source code:

### Prerequisites

- macOS 10.15 or later
- Xcode Command Line Tools: `xcode-select --install`
- Flutter SDK 3.35.7 or later

### Build Steps

```bash
# Clone the repository
git clone https://github.com/SilverDay/Kioju-link-manager.git
cd Kioju-link-manager

# Install dependencies
flutter pub get

# Build for macOS
flutter build macos --release

# The app will be located at:
# build/macos/Build/Products/Release/kioju_link_manager_flutter.app

# Optional: Use the launch script to run the app
./launch-macos.sh
```

After building, the app will have an ad-hoc signature. You can use the `launch-macos.sh` script or follow the instructions in "Option 2: Running Unsigned Builds" above to run it.

## Verifying Signed Releases

If you've downloaded a release that should be signed and notarized, verify it:

### Check Code Signature
```bash
# View signature details
codesign -dv --verbose=4 kioju_link_manager_flutter.app

# Verify signature
codesign --verify --deep --strict --verbose=2 kioju_link_manager_flutter.app
```

**What to look for:**
- Authority should show "Developer ID Application: ..."
- Signature flags should include "runtime" for hardened runtime
- TeamIdentifier should be present

### Check Notarization
```bash
# Check if app is notarized
spctl -a -vv kioju_link_manager_flutter.app

# Check notarization ticket
stapler validate kioju_link_manager_flutter.app
```

**Expected results for properly signed & notarized app:**
- `spctl` should report: "accepted" and "source=Notarized Developer ID"
- `stapler validate` should report: "The validate action worked!"

If the app is properly signed and notarized, it should open without any security warnings.

## For Developers: Manual Code Signing

If you're a developer who wants to manually sign the app locally (instead of using GitHub Actions automated signing described at the top of this document):

### Prerequisites

- Apple Developer account ($99/year)
- Developer ID Application certificate installed in Keychain
- Apple ID with app-specific password

### Local Signing Steps

To sign the app locally after building:

```bash
# Build the app
flutter build macos --release

# Sign with hardened runtime and entitlements
codesign --force --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --deep \
  build/macos/Build/Products/Release/kioju_link_manager_flutter.app

# Verify the signature
codesign --verify --deep --strict --verbose=2 \
  build/macos/Build/Products/Release/kioju_link_manager_flutter.app

# Notarize (requires xcode-select with full Xcode, not just command line tools)
cd build/macos/Build/Products/Release
zip -r kioju_link_manager_flutter.zip kioju_link_manager_flutter.app

xcrun notarytool submit kioju_link_manager_flutter.zip \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID" \
  --wait

# Staple the notarization ticket
xcrun stapler staple kioju_link_manager_flutter.app
```

## Troubleshooting

### "App is damaged and can't be opened"

This usually means the app has the quarantine attribute. Use Method 3 from "Option 2" above to remove it.

### "Code signature invalid"

If you modified the app after it was signed, the signature becomes invalid. Re-build the app or re-download the original.

### App won't open after following the guide

1. Check Console.app for error messages when trying to open the app
2. Verify the app bundle is complete and not corrupted
3. Try building from source as a last resort
4. Open an issue on GitHub with details about your macOS version and the error

## Security Considerations

### Should I trust this app?

- **Review the source code**: The app is open source at https://github.com/SilverDay/Kioju-link-manager
- **Build from source**: You can compile the app yourself to ensure it matches the source code
- **Check signatures**: When official signed releases are available, verify the signature matches the developer
- **Use at your own risk**: As with any software, understand what permissions the app requests and what it does

### What permissions does the app need?

The app requires:
- **Network access**: To sync with the Kioju API
- **File access**: To import/export bookmark files (only files you select)
- **Keychain access**: To securely store your API token

The app is sandboxed and cannot access files outside of what you explicitly select.

## Getting Help

If you encounter issues:

1. Check this guide for common solutions
2. Search existing [GitHub Issues](https://github.com/SilverDay/Kioju-link-manager/issues)
3. Create a new issue with:
   - Your macOS version
   - How you obtained the app (download/build)
   - The exact error message or behavior
   - Steps you've already tried

## References

- [Apple's Gatekeeper Documentation](https://support.apple.com/en-us/HT202491)
- [Safely open apps on your Mac](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/)
- [Flutter macOS Development](https://docs.flutter.dev/platform-integration/macos/building)
