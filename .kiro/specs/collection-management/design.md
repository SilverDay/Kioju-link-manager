# Design Document

## Overview

The collection management feature transforms the Kioju Link Manager from a flat list interface to a folder-based organization system. This design leverages the existing collection field in the LinkItem model and database schema while adding comprehensive collection management capabilities through the Kioju API.

The implementation follows a flat folder structure where collections appear as expandable folders containing their associated links, with uncategorized links displayed directly at the root level. Collections are not nested - each collection exists at the root level alongside any unassigned links. The design maintains the existing Material 3 aesthetic while introducing intuitive drag-and-drop functionality for link organization.

## Architecture

### Data Flow Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kioju API     │◄──►│  Collection      │◄──►│   Local SQLite  │
│   Collections   │    │  Service Layer   │    │   Database      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    UI Layer                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Collection     │  │   Link Items    │  │  Management     │ │
│  │  Tree View      │  │   Display       │  │  Dialogs        │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### State Management

The application uses Flutter's built-in state management with StatefulWidget for the main interface. Collection data is managed through:

- **Local State**: Current collections, expanded states, drag operations
- **Persistent State**: SQLite database for offline access and caching
- **Remote State**: Kioju API for synchronization across devices

## Components and Interfaces

### 1. Collection Model (`lib/models/collection.dart`)

```dart
class Collection {
  final int? id;
  final String? remoteId;
  final String name;
  final String? description;
  final String visibility; // 'public', 'private', 'hidden'
  final int linkCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Tag> tags;
}

class Tag {
  final int id;
  final String name;
  final String slug;
}
```

### 2. Collection Service (`lib/services/collection_service.dart`)

Handles all collection-related operations including:

- CRUD operations for collections
- Link assignment and movement
- Bidirectional synchronization with Kioju API
- Local caching and offline support
- Change tracking and conflict resolution

Key methods:

- `fetchCollections()` - Get all collections from API
- `createCollection()` - Create new collection
- `updateCollection()` - Modify collection metadata
- `deleteCollection()` - Remove collection with link handling
- `assignLinkToCollection()` - Move links between collections
- `getCollectionLinks()` - Fetch links for specific collection
- `getUncategorizedLinks()` - Get unassigned links for root display
- `syncUp()` - Push all local changes to Kioju
- `syncDown()` - Pull remote changes with conflict checking
- `hasUnsyncedChanges()` - Check for local modifications
- `markDirty()` - Flag items for sync

### 3. Collection Tree Widget (`lib/widgets/collection_tree.dart`)

A custom widget that displays collections in a flat folder structure:

- Expandable/collapsible collection folders (single level only)
- Link count indicators
- Drag and drop support for link organization between collections and root
- Context menus for collection management
- Search and filtering capabilities
- No nested collections - all collections appear at root level
- Uncategorized links displayed directly at root level (not in a folder)

### 4. Collection Management Dialogs

#### Create Collection Dialog (`lib/widgets/create_collection_dialog.dart`)

- Collection name input (required, max 100 chars)
- Description input (optional, max 2000 chars)
- Visibility selection (public/private/hidden)
- Tag assignment interface

#### Edit Collection Dialog (`lib/widgets/edit_collection_dialog.dart`)

- Modify existing collection properties
- Bulk link operations
- Collection statistics display

#### Delete Collection Dialog (`lib/widgets/delete_collection_dialog.dart`)

- Confirmation with link count display
- Link handling options (move to uncategorized vs delete)
- Impact preview

#### Sync Conflict Dialog (`lib/widgets/sync_conflict_dialog.dart`)

- Warning when attempting sync down with unsynced local changes
- Options: "Sync Up First", "Continue (may lose changes)", "Cancel"
- Display count of unsynced collections and links
- Clear explanation of potential data loss

### 5. Premium Status Management

#### Premium Status Service (`lib/services/premium_status_service.dart`)

Handles premium status checking and notifications:

- `checkPremiumStatus()` - Verify current API token premium status
- `showPremiumNotification()` - Display appropriate notification based on status
- `isPremiumRequired(feature)` - Check if specific feature requires premium
- `handlePremiumUpgrade()` - Guide user to upgrade process

#### Premium Status Checking

- **On App Start**: Check premium status after API token validation
- **On Token Change**: Immediately verify new token's premium status
- **Periodic Refresh**: Re-check status periodically (daily) to catch upgrades/downgrades
- **Feature Access**: Gate collection management features behind premium check

#### Premium Notifications

- **Free User**: "Collection management requires Kioju Premium. Upgrade to organize your links into folders and access advanced features."
- **Premium User**: No notification, full access to all features
- **Token Invalid**: "Please check your API token in Settings"
- **Network Error**: "Unable to verify premium status. Some features may be limited."

### 6. Enhanced Home Page (`lib/pages/home_page.dart`)

The main interface is restructured to support the folder view:

```
┌─────────────────────────────────────────────────────────────┐
│  App Bar (unchanged)                                        │
├─────────────────────────────────────────────────────────────┤
│  Search Bar (enhanced with collection filtering)            │
├─────────────────────────────────────────────────────────────┤
│  Collection Folder View (Flat Structure)                   │
│  ├─ 📁 Development Tools (15 links)                        │
│  │   ├─ 🔗 GitHub Repository                               │
│  │   ├─ 🔗 Stack Overflow                                  │
│  │   └─ 🔗 Documentation Site                              │
│  ├─ 📁 Research (8 links)                                  │
│  ├─ 📁 Personal (3 links)                                  │
│  ├─ � Unccategorized Link 1                                │
│  ├─ 🔗 Uncategorized Link 2                                │
│  └─ 🔗 Uncategorized Link 3                                │
└─────────────────────────────────────────────────────────────┘
```

## Data Models

### Database Schema Updates

The existing schema already supports collections through the `collection` field. Additional tables for enhanced functionality:

```sql
-- New collections table for metadata
CREATE TABLE collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_id TEXT UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  visibility TEXT DEFAULT 'public',
  link_count INTEGER DEFAULT 0,
  is_dirty INTEGER DEFAULT 0,  -- Track local changes for sync
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  last_synced_at TEXT
);

-- Enhanced links table (add dirty flag to existing schema)
ALTER TABLE links ADD COLUMN is_dirty INTEGER DEFAULT 0;
ALTER TABLE links ADD COLUMN last_synced_at TEXT;

-- Collection tags junction table
CREATE TABLE collection_tags (
  collection_id INTEGER,
  tag_name TEXT,
  FOREIGN KEY (collection_id) REFERENCES collections (id),
  PRIMARY KEY (collection_id, tag_name)
);
```

### API Integration Mapping

The service layer maps between local models and API responses:

```dart
// API Response -> Local Model
Collection.fromApiResponse(Map<String, dynamic> json) {
  return Collection(
    remoteId: json['id']?.toString(),
    name: json['name'],
    description: json['description'],
    visibility: json['visibility'] ?? 'public',
    linkCount: json['link_count'] ?? 0,
    createdAt: DateTime.parse(json['created_at']),
    updatedAt: DateTime.parse(json['updated_at']),
    tags: (json['tags'] as List?)?.map((t) => Tag.fromJson(t)).toList() ?? [],
  );
}
```

## Error Handling

### API Error Scenarios

1. **Premium Required**: Display upgrade prompt for free users with clear feature limitations
2. **Rate Limiting**: Show cooldown timer and retry options
3. **Network Errors**: Graceful degradation to offline mode
4. **Validation Errors**: Inline form validation with helpful messages
5. **Conflict Resolution**: Handle duplicate collection names and merge scenarios
6. **Premium Status Changes**: Handle upgrades/downgrades gracefully with UI updates

### Premium Status Integration

````dart
// Premium status checking on app start and token changes
class PremiumStatusService {
  static Future<void> checkAndNotifyPremiumStatus() async {
    try {
      final status = await KiojuApi.checkPremiumStatus();
      final isPremium = status['is_premium'] == true;

      if (!isPremium) {
        _showPremiumUpgradeNotification();
      }

      // Update UI state to show/hide premium features
      _updateFeatureAccess(isPremium);

    } catch (e) {
      _showPremiumCheckFailedNotification();
    }
  }

  static void _showPremiumUpgradeNotification() {
    // Show non-intrusive notification about premium features
    // Include link to upgrade and feature comparison
  }
}

### Sync Strategy

#### Sync Up (Push to Kioju)

- Upload all local changes (collections and links) to Kioju API
- Track local modifications with dirty flags in database
- Batch operations for efficiency
- Handle partial failures gracefully

#### Sync Down (Pull from Kioju)

- Check for unsynchronized local changes before pulling
- Display warning dialog if local changes exist: "You have unsynchronized changes. Syncing down may overwrite local modifications. Sync up first or continue?"
- Merge remote changes with local data
- Resolve conflicts using last-modified timestamps

#### Conflict Resolution

- **Collection Conflicts**: Remote wins for metadata, merge link assignments
- **Link Conflicts**: Preserve local changes, flag for user review
- **Deletion Conflicts**: Prompt user for resolution (restore vs keep deleted)

### Offline Support

- Local SQLite cache for all collection data
- Queue pending operations for sync when online
- Visual indicators for sync status (dirty flags, sync timestamps)
- Graceful degradation when API unavailable

### User Experience Error Handling

```dart
try {
  await collectionService.createCollection(name, description);
  showSuccessMessage('Collection created successfully');
} on AuthorizationException {
  showPremiumRequiredDialog('Collection Management');
} on ValidationException catch (e) {
  showValidationErrors(e.errors);
} on NetworkException {
  showOfflineMessage('Changes saved locally, will sync when online');
} catch (e) {
  showErrorMessage('Failed to create collection: ${e.message}');
}
````

## Testing Strategy

### Unit Tests

1. **Collection Model Tests**

   - Serialization/deserialization
   - Validation logic
   - Edge cases (empty names, long descriptions)

2. **Collection Service Tests**

   - API integration with mocked responses
   - Offline behavior simulation
   - Error handling scenarios
   - Sync conflict resolution

3. **Database Tests**
   - CRUD operations
   - Migration scenarios
   - Data integrity constraints

### Widget Tests

1. **Collection Tree Widget**

   - Expand/collapse functionality
   - Drag and drop operations
   - Context menu interactions
   - Search and filtering

2. **Management Dialogs**
   - Form validation
   - User input handling
   - Error state display

### Integration Tests

1. **End-to-End Collection Workflows**

   - Create collection → Add links → Organize → Sync
   - Import bookmarks with folder structure
   - Offline/online mode transitions

2. **API Integration Tests**
   - Full sync cycle testing
   - Premium vs free user scenarios
   - Rate limiting behavior

### Performance Tests

1. **Large Dataset Handling**

   - 1000+ collections with 10,000+ links
   - Tree view rendering performance
   - Search and filter responsiveness

2. **Memory Usage**
   - Collection data caching strategies
   - Image and metadata loading optimization

## Implementation Phases

### Phase 1: Premium Status and Core Models

- Premium status service implementation
- Premium checking on app start and token changes
- Collection model and basic service structure
- Database schema updates with migration

### Phase 2: Collection Management Backend

- Collection service CRUD operations
- API integration for collection endpoints
- Sync functionality with conflict detection
- Local caching and dirty flag tracking

### Phase 3: UI Transformation

- Replace flat list with folder view
- Implement drag and drop functionality
- Add collection management dialogs
- Premium feature gating in UI

### Phase 4: Enhanced Features and Polish

- Advanced search and filtering
- Bulk operations
- Import/export with collection support
- Performance optimization and testing

## Security Considerations

### Data Validation

- Sanitize all user inputs for collection names and descriptions
- Validate collection visibility settings
- Prevent SQL injection in database queries

### API Security

- Secure token storage (existing implementation)
- Rate limit compliance
- Premium feature access control

### Privacy

- Respect collection visibility settings
- Secure local data storage
- Clear data on app uninstall

## Accessibility

### Screen Reader Support

- Proper semantic labels for tree view navigation
- Announced state changes for expand/collapse
- Keyboard navigation support

### Visual Accessibility

- High contrast mode support
- Scalable text and icons
- Clear visual hierarchy in tree structure

### Motor Accessibility

- Large touch targets for mobile
- Alternative to drag-and-drop (context menus)
- Keyboard shortcuts for power users
