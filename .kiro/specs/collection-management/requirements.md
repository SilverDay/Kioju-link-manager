# Requirements Document

## Introduction

This feature transforms the Kioju Link Manager from displaying links in a flat list to organizing them in a hierarchical folder structure using collections. Collections act as folders that can contain links, with unassigned links displayed in a special "Uncategorized" folder. The implementation leverages the new collection management endpoints in the Kioju API to provide a modern, organized link management experience.

## Glossary

- **Collection**: A named container for organizing links, equivalent to a folder in the user interface
- **Kioju_Link_Manager**: The Flutter desktop application for managing Kioju bookmarks
- **Collection_API**: The Kioju API endpoints for collection management (collections_list, collections_create, etc.)
- **Link_Item**: A bookmark/link entity that can be assigned to a collection or remain uncategorized
- **Folder_Structure**: The hierarchical tree view displaying collections as folders and links as items
- **Uncategorized_Folder**: A special virtual folder containing links not assigned to any collection
- **Collection_Sync**: The process of synchronizing local collection data with the Kioju API

## Requirements

### Requirement 1

**User Story:** As a user, I want to see my links organized in folders (collections) instead of a flat list, so that I can better organize and find my bookmarks.

#### Acceptance Criteria

1. WHEN the application starts, THE Kioju_Link_Manager SHALL display collections as folders in a tree view structure
2. WHEN a collection contains links, THE Kioju_Link_Manager SHALL show the link count next to the collection name
3. WHEN links are not assigned to any collection, THE Kioju_Link_Manager SHALL display them in an "Uncategorized" folder
4. WHEN a user expands a collection folder, THE Kioju_Link_Manager SHALL display all links within that collection
5. THE Kioju_Link_Manager SHALL maintain the current Material 3 design system for the folder structure interface

### Requirement 2

**User Story:** As a user, I want to create new collections to organize my links, so that I can group related bookmarks together.

#### Acceptance Criteria

1. WHEN a user requests to create a new collection, THE Kioju_Link_Manager SHALL display a collection creation dialog
2. WHEN creating a collection, THE Kioju_Link_Manager SHALL require a collection name with maximum 100 characters
3. WHEN creating a collection, THE Kioju_Link_Manager SHALL allow optional description with maximum 2000 characters
4. WHEN creating a collection, THE Kioju_Link_Manager SHALL allow setting visibility to public, private, or hidden
5. WHEN collection creation is successful, THE Kioju_Link_Manager SHALL add the new collection to the folder structure immediately

### Requirement 3

**User Story:** As a user, I want to move links between collections or to uncategorized, so that I can reorganize my bookmarks as needed.

#### Acceptance Criteria

1. WHEN a user drags a link to a different collection folder, THE Kioju_Link_Manager SHALL move the link to that collection
2. WHEN a user drags a link to the uncategorized folder, THE Kioju_Link_Manager SHALL remove the link from its current collection
3. WHEN a link assignment operation fails, THE Kioju_Link_Manager SHALL display an error message and revert the visual change
4. WHEN a link is successfully moved, THE Kioju_Link_Manager SHALL update the link counts for affected collections
5. THE Kioju_Link_Manager SHALL provide visual feedback during drag and drop operations

### Requirement 4

**User Story:** As a user, I want to manage collections (rename, delete, edit), so that I can maintain my organizational structure.

#### Acceptance Criteria

1. WHEN a user right-clicks on a collection folder, THE Kioju_Link_Manager SHALL display a context menu with management options
2. WHEN a user selects rename collection, THE Kioju_Link_Manager SHALL allow editing the collection name and description
3. WHEN a user deletes a collection, THE Kioju_Link_Manager SHALL prompt for confirmation and link handling preference
4. WHEN deleting a collection with move_links mode, THE Kioju_Link_Manager SHALL move all links to uncategorized
5. WHEN collection management operations complete, THE Kioju_Link_Manager SHALL refresh the folder structure display

### Requirement 5

**User Story:** As a user, I want the app to sync collection data with the Kioju API, so that my organization is preserved across devices and sessions.

#### Acceptance Criteria

1. WHEN the application starts, THE Kioju_Link_Manager SHALL fetch collections from the Collection_API
2. WHEN collection data is modified locally, THE Kioju_Link_Manager SHALL synchronize changes with the Collection_API
3. WHEN API synchronization fails, THE Kioju_Link_Manager SHALL display error messages and maintain local state
4. WHEN the user has a free account, THE Kioju_Link_Manager SHALL display a message that collections require premium access
5. THE Kioju_Link_Manager SHALL cache collection data locally for offline viewing

### Requirement 6

**User Story:** As a user, I want to import existing bookmarks into collections, so that I can organize previously imported links.

#### Acceptance Criteria

1. WHEN importing bookmarks with folder structure, THE Kioju_Link_Manager SHALL create collections matching the folder names
2. WHEN importing bookmarks without folders, THE Kioju_Link_Manager SHALL place all links in uncategorized
3. WHEN a collection name conflicts during import, THE Kioju_Link_Manager SHALL prompt for resolution (merge, rename, skip)
4. WHEN bookmark import completes, THE Kioju_Link_Manager SHALL display a summary of created collections and assigned links
5. THE Kioju_Link_Manager SHALL maintain existing import functionality for browsers without collection support
