# Project Structure

## Root Directory

```
├── lib/                    # Main application code
├── assets/                 # Static assets (icons, images)
├── test/                   # Unit and widget tests
├── windows/                # Windows platform-specific code
├── macos/                  # macOS platform-specific code
├── web/                    # Web platform files (minimal)
├── pubspec.yaml           # Dependencies and project config
└── analysis_options.yaml  # Dart analyzer configuration
```

## Library Organization (`lib/`)

```
lib/
├── main.dart              # App entry point with Material 3 theme setup
├── db.dart               # SQLite database singleton and schema
├── models/               # Data models and entities
│   └── link.dart         # LinkItem model with serialization
├── pages/                # UI screens and page widgets
│   ├── home_page.dart    # Main interface
│   └── settings_page.dart # Settings and token management
├── services/             # Business logic and external integrations
│   ├── kioju_api.dart    # API client and sync operations
│   ├── app_settings.dart # App configuration management
│   └── web_metadata_service.dart # Link metadata fetching
├── utils/                # Utility functions and helpers
│   ├── bookmark_export.dart # HTML export functionality
│   └── bookmark_import.dart # Browser bookmark parsing
└── widgets/              # Reusable UI components
```

## Architecture Patterns

### Data Layer

- **Database**: Singleton pattern with `AppDb.instance()`
- **Models**: Simple data classes with `toMap()` and `fromMap()` methods
- **Storage**: SQLite with cross-platform FFI support

### Service Layer

- **API Client**: Centralized HTTP communication in `kioju_api.dart`
- **Settings**: Secure storage for API tokens and app configuration
- **Import/Export**: Utility classes for bookmark file handling

### UI Layer

- **Pages**: Full-screen widgets representing app screens
- **Widgets**: Reusable components following Material 3 design
- **State Management**: Provider pattern for reactive UI updates

## Naming Conventions

- **Files**: snake_case (e.g., `home_page.dart`, `kioju_api.dart`)
- **Classes**: PascalCase (e.g., `LinkItem`, `KiojuApi`)
- **Variables/Methods**: camelCase (e.g., `remoteId`, `fetchLinks()`)
- **Constants**: SCREAMING_SNAKE_CASE for compile-time constants

## Database Schema

- **links**: Main entity table with auto-increment ID
- **config**: Key-value store for app settings
- **Migration**: Version-based schema updates in `db.dart`

## Platform-Specific Code

- Desktop platforms use FFI for SQLite
- Native file dialogs via `file_selector`
- Secure storage encryption varies by platform
