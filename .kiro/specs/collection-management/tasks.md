# Implementation Plan

- [x] 1. Set up premium status management and core models

  - Create premium status service for checking API token capabilities
  - Implement premium status checking on app start and token changes
  - Add premium status notifications and UI indicators
  - _Requirements: 5.4, 5.5_

- [x] 1.1 Create premium status service

  - Write PremiumStatusService class with checkPremiumStatus method
  - Implement premium notification display logic
  - Add premium status caching and periodic refresh
  - _Requirements: 5.4, 5.5_

- [x] 1.2 Integrate premium checking into app lifecycle

  - Add premium status check to app initialization
  - Implement premium check on API token changes in settings
  - Create premium upgrade notification UI components
  - _Requirements: 5.4, 5.5_

- [x] 1.3 Create Collection model and basic structure

  - Write Collection data model with serialization methods
  - Create Tag model for collection tagging
  - Add collection-related database schema updates
  - _Requirements: 1.1, 2.1, 4.1_

- [x] 1.4 Update database schema for collections

  - Add collections table with metadata fields
  - Add dirty flags to existing links table for sync tracking
  - Implement database migration from version 2 to 3
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 2. Implement collection management backend services

  - Create comprehensive collection service for CRUD operations
  - Integrate with Kioju API collection endpoints
  - Implement bidirectional sync with conflict detection
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 5.1, 5.2, 5.3_

- [x] 2.1 Create CollectionService with basic CRUD operations

  - Implement createCollection, updateCollection, deleteCollection methods
  - Add getCollections and getCollectionLinks methods
  - Create assignLinkToCollection for link organization
  - _Requirements: 2.1, 2.2, 4.1, 4.2, 4.3, 4.4_

- [x] 2.2 Integrate collection API endpoints

  - Add collections_list, collections_create, collections_update API calls
  - Implement collections_delete with link handling options
  - Add collections_assign_link and collections_get_links endpoints
  - _Requirements: 2.1, 2.2, 4.1, 4.2, 4.3, 4.4, 5.1_

- [x] 2.3 Implement sync functionality with conflict detection

  - Create syncUp method to push local changes to API
  - Implement syncDown with unsync change detection and warnings
  - Add hasUnsyncedChanges method for conflict checking
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 2.4 Add local caching and dirty flag management

  - Implement local collection caching in SQLite
  - Add markDirty functionality for tracking local changes
  - Create sync status tracking and last_synced_at timestamps
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 3. Transform UI from flat list to folder-based organization

  - Replace current flat link list with collection folder view
  - Implement drag and drop for link organization
  - Add collection management dialogs and context menus
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3.1 Create CollectionTreeWidget for folder display

  - Build expandable collection folders with link count indicators
  - Display uncategorized links at root level (not in folder)
  - Implement flat folder structure (no nesting)
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 3.2 Implement drag and drop functionality

  - Add drag support for links between collections and root
  - Implement drop zones for collections and uncategorized area
  - Provide visual feedback during drag operations
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 3.3 Create collection management dialogs

  - Build CreateCollectionDialog with name, description, visibility fields
  - Implement EditCollectionDialog for modifying collection properties
  - Add DeleteCollectionDialog with link handling options
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 4.1, 4.2, 4.3, 4.4_

- [x] 3.4 Add sync conflict warning dialog

  - Create SyncConflictDialog for unsync change warnings
  - Display options: "Sync Up First", "Continue", "Cancel"
  - Show count of unsynced collections and links
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 3.5 Update HomePage to use collection folder view

  - Replace flat ListView with CollectionTreeWidget
  - Integrate premium status checking and feature gating
  - Update sync buttons to handle collection synchronization
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 5.4, 5.5_

- [x] 4. Enhance import/export and search functionality

  - Update bookmark import to support collection creation
  - Enhance search to filter by collections
  - Add bulk operations for link management
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 4.1 Update bookmark import for collections

  - Modify importFromNetscapeHtml to create collections from folders
  - Handle collection name conflicts during import
  - Display import summary with created collections
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 4.2 Enhance search functionality

  - Add collection filtering to search interface
  - Implement search within specific collections
  - Update search results to show collection context
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 4.3 Add bulk link operations

  - Implement multi-select for links
  - Add bulk move to collection functionality
  - Create bulk delete with collection cleanup
  - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.2, 4.3_

- [x] 4.4 Write integration tests for collection workflows

  - Test complete collection creation and link assignment flow
  - Verify sync up and sync down with conflict scenarios
  - Test import with collection creation
  - _Requirements: 1.1, 2.1, 3.1, 5.1, 6.1_

- [x] 4.5 Add performance optimization for large datasets
  - Implement lazy loading for collection contents
  - Optimize tree view rendering for many collections
  - Add pagination for large link lists within collections
  - _Requirements: 1.1, 1.2, 1.3_
