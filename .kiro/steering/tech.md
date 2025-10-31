# Technology Stack

## Framework & Language

- **Flutter 3.35.7+** with Dart 3.5.7+
- **Material 3** design system for modern UI
- Desktop-focused development (Windows, macOS, Linux)

## Key Dependencies

- `sqflite` + `sqflite_common_ffi` - SQLite database for local storage
- `flutter_secure_storage` - Encrypted token storage
- `http` - API communication
- `path_provider` - Cross-platform file paths
- `file_selector` - Native file dialogs
- `url_launcher` - External link handling
- `provider` - State management
- `html` - HTML parsing for bookmark import

## Development Tools

- `flutter_lints` - Code quality and style enforcement
- `flutter_launcher_icons` - Icon generation
- `flutter_test` - Unit and widget testing

## Build System

### Prerequisites

- Flutter SDK 3.35.7 or later
- **Windows**: Visual Studio Build Tools 2022 with C++ workload
- **macOS**: Xcode Command Line Tools (`xcode-select --install`)

### Common Commands

```bash
# Install dependencies
flutter pub get

# Run in development
flutter run -d windows    # or -d macos / -d linux

# Build for release
flutter build windows --release
flutter build macos --release
flutter build linux --release

# Run tests
flutter test

# Analyze code
flutter analyze

# Generate launcher icons
flutter pub run flutter_launcher_icons:main
```

### Build Outputs

- **Windows**: `build\windows\x64\runner\Release\`
- **macOS**: `build\macos\Build\Products\Release\`
- **Linux**: `build\linux\x64\release\bundle\`

## Database

- SQLite with cross-platform FFI support
- Local database path: `{AppSupport}/kioju/kioju_links.db`
- Schema versioning with migration support
