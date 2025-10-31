# Requirements Document

## Introduction

This feature extends the configurable sync behavior to all data modification operations in the Kioju Link Manager application. Users can choose between immediate synchronization (changes are synced to the server immediately) and manual synchronization (changes are marked dirty and synced during manual sync operations). This provides flexibility for different user workflows and network conditions.

## Glossary

- **Kioju_App**: The Kioju Link Manager Flutter desktop application
- **Sync_Service**: The service responsible for synchronizing data with the Kioju API
- **Immediate_Sync_Mode**: Configuration where all changes are automatically synced to server immediately
- **Manual_Sync_Mode**: Configuration where changes are marked dirty and synced only during manual sync operations
- **Data_Operation**: Any create, update, delete, or move operation on links or collections
- **Dirty_Flag**: Database flag indicating that local data has changes not yet synced to server

## Requirements

### Requirement 1

**User Story:** As a user, I want to configure whether my changes sync immediately or manually, so that I can choose the sync behavior that fits my workflow and network conditions.

#### Acceptance Criteria

1. WHEN the user accesses settings, THE Kioju_App SHALL display an "Immediate Sync" toggle setting
2. WHEN the user enables immediate sync, THE Kioju_App SHALL store this preference persistently
3. WHEN the user disables immediate sync, THE Kioju_App SHALL store this preference persistently
4. THE Kioju_App SHALL load the sync preference on application startup
5. THE Kioju_App SHALL default to manual sync mode for new installations

### Requirement 2

**User Story:** As a user, I want my link operations to respect my sync preference, so that links are handled according to my chosen workflow.

#### Acceptance Criteria

1. WHEN immediate sync is enabled AND the user creates a new link, THE Kioju_App SHALL sync the link to server immediately
2. WHEN manual sync is enabled AND the user creates a new link, THE Kioju_App SHALL mark the link as dirty for later sync
3. WHEN immediate sync is enabled AND the user edits a link, THE Kioju_App SHALL sync the changes to server immediately
4. WHEN manual sync is enabled AND the user edits a link, THE Kioju_App SHALL mark the link as dirty for later sync
5. WHEN immediate sync is enabled AND the user deletes a link, THE Kioju_App SHALL sync the deletion to server immediately
6. WHEN manual sync is enabled AND the user deletes a link, THE Kioju_App SHALL mark the link as dirty for later sync

### Requirement 3

**User Story:** As a user, I want my collection operations to respect my sync preference, so that collections are handled according to my chosen workflow.

#### Acceptance Criteria

1. WHEN immediate sync is enabled AND the user creates a collection, THE Kioju_App SHALL sync the collection to server immediately
2. WHEN manual sync is enabled AND the user creates a collection, THE Kioju_App SHALL mark the collection as dirty for later sync
3. WHEN immediate sync is enabled AND the user edits a collection, THE Kioju_App SHALL sync the changes to server immediately
4. WHEN manual sync is enabled AND the user edits a collection, THE Kioju_App SHALL mark the collection as dirty for later sync
5. WHEN immediate sync is enabled AND the user deletes a collection, THE Kioju_App SHALL sync the deletion to server immediately
6. WHEN manual sync is enabled AND the user deletes a collection, THE Kioju_App SHALL mark the collection as dirty for later sync

### Requirement 4

**User Story:** As a user, I want link movement operations to respect my sync preference, so that organizational changes are handled according to my chosen workflow.

#### Acceptance Criteria

1. WHEN immediate sync is enabled AND the user moves a link between collections, THE Kioju_App SHALL sync the move operation to server immediately
2. WHEN manual sync is enabled AND the user moves a link between collections, THE Kioju_App SHALL mark the affected link as dirty for later sync
3. WHEN immediate sync is enabled AND the user moves multiple links, THE Kioju_App SHALL sync all move operations to server immediately
4. WHEN manual sync is enabled AND the user moves multiple links, THE Kioju_App SHALL mark all affected links as dirty for later sync

### Requirement 5

**User Story:** As a user, I want appropriate feedback about sync operations, so that I understand what happened with my changes.

#### Acceptance Criteria

1. WHEN immediate sync succeeds, THE Kioju_App SHALL display a success message indicating the operation was synced
2. WHEN immediate sync fails, THE Kioju_App SHALL display an error message and mark the data as dirty for later sync
3. WHEN manual sync is enabled, THE Kioju_App SHALL display a message indicating the change was saved locally
4. THE Kioju_App SHALL provide different message text for immediate vs manual sync modes
5. WHEN sync errors occur, THE Kioju_App SHALL include helpful error details in the message

### Requirement 6

**User Story:** As a user, I want bulk operations to respect my sync preference, so that large-scale changes are handled efficiently according to my chosen workflow.

#### Acceptance Criteria

1. WHEN immediate sync is enabled AND the user performs bulk operations, THE Kioju_App SHALL sync all changes to server immediately
2. WHEN manual sync is enabled AND the user performs bulk operations, THE Kioju_App SHALL mark all affected items as dirty for later sync
3. WHEN immediate sync is enabled AND bulk sync fails partially, THE Kioju_App SHALL mark failed items as dirty and report the status
4. THE Kioju_App SHALL provide progress feedback during bulk immediate sync operations
5. THE Kioju_App SHALL handle bulk operation errors gracefully without losing data

### Requirement 7

**User Story:** As a user, I want import operations to respect my sync preference, so that imported data is handled according to my chosen workflow.

#### Acceptance Criteria

1. WHEN immediate sync is enabled AND the user imports bookmarks, THE Kioju_App SHALL sync all imported items to server immediately
2. WHEN manual sync is enabled AND the user imports bookmarks, THE Kioju_App SHALL mark all imported items as dirty for later sync
3. WHEN immediate sync is enabled AND import sync fails partially, THE Kioju_App SHALL mark failed items as dirty and report the status
4. THE Kioju_App SHALL provide progress feedback during import immediate sync operations
5. THE Kioju_App SHALL handle import sync errors gracefully without losing imported data
