# Design Document

## Overview

The configurable sync behavior feature provides users with control over when their data changes are synchronized with the Kioju API server. This design extends the existing sync infrastructure to support both immediate and manual sync modes across all data operations including links, collections, bulk operations, and imports.

## Architecture

### Current State

- Manual sync operations exist for batch synchronization
- All data operations currently use manual sync approach (mark as dirty)
- Link and collection operations consistently mark items as dirty for later manual sync
- Recent fixes ensure consistent manual sync behavior across all operations

### Target State

- Add immediate sync toggle setting to allow users to choose sync behavior
- All data modification operations respect the user's sync preference (immediate vs manual)
- Consistent error handling and user feedback across all operations
- Centralized sync behavior logic for maintainability

## Components and Interfaces

### 1. Settings Service Enhancement

**Purpose**: Centralize sync preference management and provide easy access across the app.

**Interface**:

```dart
class SyncSettings {
  static Future<bool> isImmediateSyncEnabled() async
  static Future<void> setImmediateSyncEnabled(bool enabled) async
}
```

**Implementation**:

- Move the static method from SettingsPage to a dedicated service
- Provide caching to avoid repeated SharedPreferences calls
- Ensure thread-safe access to preferences

### 2. Sync Strategy Pattern

**Purpose**: Encapsulate sync behavior logic and make it reusable across different operations.

**Interface**:

```dart
abstract class SyncStrategy {
  Future<SyncResult> executeSync(SyncOperation operation);
}

class ImmediateSyncStrategy implements SyncStrategy {
  Future<SyncResult> executeSync(SyncOperation operation);
}

class ManualSyncStrategy implements SyncStrategy {
  Future<SyncResult> executeSync(SyncOperation operation);
}
```

**SyncOperation Types**:

- LinkCreateOperation
- LinkUpdateOperation
- LinkDeleteOperation
- LinkMoveOperation
- CollectionCreateOperation
- CollectionUpdateOperation
- CollectionDeleteOperation
- BulkOperation
- ImportOperation

### 3. Enhanced Collection Service

**Current State**: Collection service has basic CRUD operations with some sync logic.

**Enhancements Needed**:

- Integrate with sync strategy pattern
- Add configurable sync support to all collection operations
- Implement proper error handling and rollback for failed immediate syncs
- Add dirty flag management for manual sync mode

**Modified Methods**:

```dart
class CollectionService {
  Future<void> createCollection(String name, {String? parentId});
  Future<void> updateCollection(String id, String name);
  Future<void> deleteCollection(String id);
  Future<void> moveLinksToCollection(List<String> linkIds, String? collectionId);
}
```

### 4. Enhanced Link Operations

**Current State**: Link editing partially supports configurable sync.

**Enhancements Needed**:

- Extend to all link operations (create, delete, move)
- Standardize error handling and user feedback
- Implement bulk operation support

**Modified Operations**:

- Link creation in add link dialog
- Link deletion operations
- Link movement between collections
- Bulk link operations

### 5. Import Service Enhancement

**Current State**: Import operations create links locally without immediate sync consideration.

**Enhancements Needed**:

- Add sync strategy integration to import process
- Implement progress tracking for immediate sync during imports
- Handle partial sync failures gracefully

## Data Models

### SyncResult Model

```dart
class SyncResult {
  final bool success;
  final String? errorMessage;
  final List<String> failedItemIds;
  final SyncResultType type;
}

enum SyncResultType {
  immediate_success,
  immediate_partial_failure,
  immediate_failure,
  manual_queued
}
```

### Enhanced Database Schema

**Links Table**:

- Existing `is_dirty` flag (already implemented)
- Existing `last_synced_at` timestamp (already implemented)

**Collections Table**:

- Add `is_dirty` flag for collection sync tracking
- Add `last_synced_at` timestamp for collection sync tracking

## Error Handling

### Immediate Sync Failures

**Strategy**: Graceful degradation to manual sync mode

1. Attempt immediate sync operation
2. If sync fails, mark item as dirty for later sync
3. Show user-friendly error message with context
4. Preserve all local changes

**Error Categories**:

- Network connectivity issues
- Server errors (5xx)
- Authentication failures
- Validation errors (4xx)
- Timeout errors

### Partial Bulk Operation Failures

**Strategy**: Continue processing and report status

1. Process bulk operations individually
2. Track success/failure for each item
3. Mark failed items as dirty
4. Provide detailed status report to user

## Testing Strategy

### Unit Tests

- SyncStrategy implementations
- SyncSettings service
- Error handling scenarios
- Database dirty flag management

### Integration Tests

- End-to-end sync workflows
- Bulk operation handling
- Import process with sync
- Error recovery scenarios

### User Interface Tests

- Settings toggle functionality
- User feedback messages
- Progress indicators for bulk operations
- Error message display

## Implementation Phases

### Phase 1: Core Infrastructure

1. Create SyncSettings service
2. Implement SyncStrategy pattern
3. Add collection dirty flag support
4. Update database schema

### Phase 2: Collection Operations

1. Update collection creation with sync strategy
2. Update collection editing with sync strategy
3. Update collection deletion with sync strategy
4. Add comprehensive error handling

### Phase 3: Link Operations

1. Update link creation with sync strategy
2. Update link deletion with sync strategy
3. Update link movement with sync strategy
4. Enhance bulk operations

### Phase 4: Import and Advanced Features

1. Update import process with sync strategy
2. Add progress tracking for bulk immediate sync
3. Implement comprehensive error reporting
4. Add user feedback enhancements

## User Experience Considerations

### Feedback Messages

- **Immediate Success**: "Collection created and synced successfully"
- **Immediate Failure**: "Collection created locally, but server sync failed: [error]"
- **Manual Mode**: "Collection created locally. Use sync to upload changes."

### Progress Indicators

- Show progress bars for bulk immediate sync operations
- Provide cancellation options for long-running sync operations
- Display sync status in appropriate UI locations

### Performance Considerations

- Cache sync preference to avoid repeated database calls
- Implement batching for bulk immediate sync operations
- Use background threads for sync operations to avoid UI blocking
- Implement retry logic with exponential backoff for failed syncs

## Security Considerations

- Ensure sync preference is stored securely
- Validate all data before sync operations
- Implement proper authentication for all API calls
- Handle token expiration gracefully during sync operations

## Backward Compatibility

- Existing manual sync functionality remains unchanged
- Default to manual sync mode for existing installations
- Graceful handling of missing dirty flags in existing data
- Maintain existing API contracts
