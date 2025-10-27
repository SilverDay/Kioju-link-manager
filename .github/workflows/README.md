# GitHub Workflows for Kioju Link Manager

This directory contains GitHub Actions workflows to automate building, testing, and deploying the Kioju Link Manager Flutter application.

## Available Workflows

### 1. `build-desktop.yml` - Main Build Pipeline

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main`
- Release publications

**Features:**
- ✅ Builds for Windows and macOS
- ✅ Runs automated tests
- ✅ Creates downloadable artifacts
- ✅ Automatically attaches builds to releases

**Artifacts:**
- `kioju-link-manager-windows` - Windows executable and dependencies
- `kioju-link-manager-macos` - macOS app bundle

### 2. `advanced-build.yml` - Manual Advanced Builds

**Triggers:**
- Manual workflow dispatch with options

**Features:**
- 🔧 Optional installer creation (MSI for Windows, DMG for macOS)
- 🔧 Code signing preparation (requires setup)
- 🔧 Advanced packaging options
- 🔧 Quality checks with coverage

**Usage:**
1. Go to Actions tab in GitHub
2. Select "Advanced Build & Deploy"
3. Click "Run workflow"
4. Choose your options:
   - Create installers: Yes/No
   - Upload to release: Yes/No

### 3. `pr-validation.yml` - Pull Request Validation

**Triggers:**
- Pull requests affecting Dart files or dependencies

**Features:**
- 🔍 Code analysis and linting
- 🔍 Formatting validation
- 🔍 Security scanning
- 🔍 Dependency audit

## Setup Instructions

### Basic Setup (No Additional Configuration Required)

The basic workflows will work immediately after committing these files. They will:
- Build your app for Windows and macOS
- Run tests
- Create downloadable artifacts
- Validate pull requests

### Advanced Setup (Optional)

#### For Code Signing (macOS)

Add these secrets to your GitHub repository:

1. `MACOS_CERTIFICATE` - Base64 encoded .p12 certificate
2. `MACOS_CERTIFICATE_PWD` - Certificate password
3. `MACOS_CERTIFICATE_NAME` - Certificate name for codesign

```bash
# Generate base64 certificate
base64 -i your_certificate.p12 | pbcopy
```

#### For Windows Code Signing

Add these secrets:
1. `WINDOWS_CERTIFICATE` - Base64 encoded .pfx certificate
2. `WINDOWS_CERTIFICATE_PWD` - Certificate password

#### For Release Automation

The workflows automatically use the `GITHUB_TOKEN` which is provided by GitHub Actions.

## Usage Examples

### Creating a Release with Builds

1. Create a new release on GitHub
2. The workflow automatically builds and attaches executables
3. Users can download platform-specific builds

### Manual Advanced Build

1. Navigate to Actions → Advanced Build & Deploy
2. Click "Run workflow"
3. Select options and run
4. Download artifacts from the workflow run

### Local Testing

Before pushing, you can test locally:

```bash
# Run the same checks as PR validation
flutter analyze --fatal-infos --fatal-warnings
dart format --set-exit-if-changed .
flutter test
dart pub audit
```

## Workflow Status

You can add status badges to your README:

```markdown
![Build Status](https://github.com/SilverDay/Kioju-link-manager/workflows/Build%20Desktop%20Apps/badge.svg)
![PR Validation](https://github.com/SilverDay/Kioju-link-manager/workflows/PR%20Validation/badge.svg)
```

## Troubleshooting

### Common Issues

1. **Build fails on dependencies**: Update Flutter version in workflows if needed
2. **Tests fail**: Ensure all tests pass locally before pushing
3. **Artifacts too large**: Consider using compression or excluding debug symbols

### Getting Help

- Check the Actions tab for detailed logs
- Ensure your Flutter version matches the workflow
- Verify all dependencies are properly declared in `pubspec.yaml`

## Customization

You can customize these workflows by:

1. Changing Flutter versions
2. Adding additional platforms (Linux)
3. Modifying build parameters
4. Adding deployment steps
5. Integrating with external services

## Security Notes

- Never commit secrets or certificates to the repository
- Use GitHub secrets for sensitive data
- Regularly update workflow dependencies
- Monitor for security advisories in dependencies