# Kioju Link Manager — Flutter

A modern, cross-platform Flutter application for managing Kioju links with seamless browser bookmark import/export and sync capabilities. Built with Material 3 design principles for a polished, native experience on Windows, macOS, and Linux.

## ✨ Features

- **Modern Material 3 UI** — Clean, responsive design with dark/light theme support
- **Cross-Platform** — Native desktop experience on Windows, macOS, and Linux
- **Bookmark Management** — Import from Chrome, Firefox, Safari, and Edge
- **Secure Sync** — Two-way synchronization with Kioju API using encrypted token storage
- **Smart Export** — Export your links as HTML bookmarks compatible with all browsers
- **First-Time Setup** — Guided onboarding for new users
- **Offline Storage** — Local SQLite database for reliable offline access

## 🛠 Technical Stack

- **Flutter 3.35.7** with Dart 3.5.7
- **Material 3** design system
- **SQLite** for local data persistence
- **Flutter Secure Storage** for encrypted API token storage
- **file_selector** for cross-platform file dialogs
- **url_launcher** for external link handling

## 🚀 Quick Start

### Prerequisites
- Flutter SDK 3.35.7 or later
- For Windows: Visual Studio Build Tools 2022 with C++ workload
- For macOS: Xcode Command Line Tools (`xcode-select --install`)

### Installation

#### Downloading Pre-built Releases
1. Go to the [Releases page](https://github.com/SilverDay/Kioju-link-manager/releases)
2. Download the appropriate package for your platform
3. **For macOS users**: 
   - Properly signed and notarized releases (when available) will open without security warnings
   - If you see security warnings, see [MACOS_INSTALLATION.md](MACOS_INSTALLATION.md) for complete setup instructions
   - The installation guide also contains instructions for maintainers on setting up code signing

#### Building from Source
```powershell
# Clone the repository
git clone https://github.com/silverday/Kioju-link-manager.git
cd Kioju-link-manager

# Install dependencies
flutter pub get

# Run the application
flutter run -d windows   # or -d macos / -d linux
```

### First Launch
1. The app will prompt you to enter your Kioju API token
2. Get your token from your Kioju instance settings
3. Paste it in the setup dialog and start managing your links!

## 📱 Usage

### Managing Links
- View all your synced links in a clean, card-based interface
- Click any link to open it in your default browser
- Use the sync buttons to upload local bookmarks or download from Kioju

### Import Bookmarks
1. Click the **Sync Up** button (upload icon)
2. Select your browser's bookmark file
3. Choose to sync immediately or review locally first

### Export Bookmarks
1. Click the **Sync Down** button (download icon)
2. Choose your export location
3. Import the generated HTML file into any browser

### Settings
- Access settings via the gear icon in the top-right
- Manage your API token securely
- View sync status and app information

## 🏗 Building for Windows

The application requires Visual Studio Build Tools for Windows compilation:

```powershell
# Build for Windows release
flutter build windows --release

# The executable will be in build\windows\x64\runner\Release\
```

## 📁 Project Structure

```
lib/
├── main.dart              # App entry point with Material 3 themes
├── db.dart               # SQLite database management
├── models/
│   └── link.dart         # Link data model
├── pages/
│   ├── home_page.dart    # Main interface with modern UI
│   └── settings_page.dart # Settings and token management
├── services/
│   └── kioju_api.dart    # API integration and sync logic
└── utils/
    ├── bookmark_export.dart # HTML export functionality
    └── bookmark_import.dart # Browser bookmark parsing
```

## 🔧 Configuration

The app connects to the Kioju API at `https://kioju.de/api/api.php`. API tokens are stored securely using Flutter Secure Storage and encrypted at rest.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built with [Flutter](https://flutter.dev/) by Google
- Material 3 design system
- [Kioju](https://kioju.de/) for the excellent bookmark management platform
