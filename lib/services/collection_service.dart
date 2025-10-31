import 'package:sqflite/sqflite.dart';
import '../db.dart';
import '../models/collection.dart';
import '../models/link.dart';
import 'kioju_api.dart';
import 'sync_settings.dart';
import 'sync_strategy.dart';
import 'immediate_sync_strategy.dart';
import 'manual_sync_strategy.dart';

/// Service for managing collections with CRUD operations and API synchronization
class CollectionService {
  static CollectionService? _instance;

  /// Singleton instance
  static CollectionService get instance {
    _instance ??= CollectionService._();
    return _instance!;
  }

  CollectionService._();

  // ============================================================================
  // SYNC STRATEGY EXECUTION
  // ============================================================================

  /// Executes sync operation based on user preference
  Future<SyncResult> _executeSyncStrategy(SyncOperation operation) async {
    try {
      final isImmediateSync = await SyncSettings.isImmediateSyncEnabled();
      final SyncStrategy strategy =
          isImmediateSync ? ImmediateSyncStrategy() : ManualSyncStrategy();

      return await strategy.executeSync(operation);
    } catch (e) {
      // If sync strategy fails, ensure item is marked dirty for later sync
      if (operation is CollectionCreateOperation && operation.localId != null) {
        await markCollectionDirty(operation.localId!);
      } else if (operation is CollectionUpdateOperation &&
          operation.localId != null) {
        await markCollectionDirty(operation.localId!);
      }

      return SyncResult.immediateFailure(
        'Sync operation failed: ${e.toString()}',
        [operation.operationId],
      );
    }
  }

  // ============================================================================
  // LOCAL CRUD OPERATIONS
  // ============================================================================

  /// Create a new collection with configurable sync
  Future<Collection> createCollection({
    required String name,
    String? description,
    String visibility = 'public',
    List<Tag> tags = const [],
  }) async {
    // Validate input
    final validation = _validateCollectionData(name, description, visibility);
    if (validation != null) {
      throw ArgumentError(validation);
    }

    final db = await AppDb.instance();
    final now = DateTime.now();

    // Check for duplicate names
    final existing = await db.query(
      'collections',
      where: 'name = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw ArgumentError('A collection with this name already exists');
    }

    // Create collection locally first
    final collection = Collection(
      name: name.trim(),
      description: description?.trim(),
      visibility: visibility,
      isDirty: true, // Mark as needing sync initially
      createdAt: now,
      updatedAt: now,
      tags: tags,
    );

    // Insert into database
    final id = await db.insert('collections', collection.toMap());

    // Insert tags if any
    if (tags.isNotEmpty) {
      await _insertCollectionTags(id, tags);
    }

    final createdCollection = collection.copyWith(id: id);

    // Execute sync strategy
    await _executeSyncStrategy(
      CollectionCreateOperation(
        name: name.trim(),
        description: description?.trim(),
        visibility: visibility,
        tags: tags.map((t) => t.name).toList(),
        localId: id,
        markAsSynced: (remoteId) async {
          await markCollectionSynced(id, remoteId: remoteId);
        },
      ),
    );

    return createdCollection;
  }

  /// Update an existing collection with configurable sync
  Future<Collection> updateCollection({
    required int id,
    String? name,
    String? description,
    String? visibility,
    List<Tag>? tags,
  }) async {
    final db = await AppDb.instance();

    // Get existing collection
    final existing = await getCollectionById(id);
    if (existing == null) {
      throw ArgumentError('Collection not found');
    }

    // Validate new data if provided
    if (name != null || description != null || visibility != null) {
      final validation = _validateCollectionData(
        name ?? existing.name,
        description ?? existing.description,
        visibility ?? existing.visibility,
      );
      if (validation != null) {
        throw ArgumentError(validation);
      }
    }

    // Check for duplicate names if name is being changed
    if (name != null && name.trim() != existing.name) {
      final duplicate = await db.query(
        'collections',
        where: 'name = ? AND id != ?',
        whereArgs: [name.trim(), id],
        limit: 1,
      );

      if (duplicate.isNotEmpty) {
        throw ArgumentError('A collection with this name already exists');
      }
    }

    // Create updated collection
    final updatedCollection = existing.copyWith(
      name: name?.trim(),
      description: description?.trim(),
      visibility: visibility,
      tags: tags,
      isDirty: true,
      updatedAt: DateTime.now(),
    );

    // Update in database
    await db.update(
      'collections',
      updatedCollection.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );

    // Update tags if provided
    if (tags != null) {
      await _updateCollectionTags(id, tags);
    }

    // If collection name changed, update all links that reference this collection
    if (name != null && name.trim() != existing.name) {
      await db.update(
        'links',
        {
          'collection': name.trim(),
          'is_dirty':
              1, // Mark links as dirty since collection reference changed
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'collection = ?',
        whereArgs: [existing.name],
      );
    }

    // Execute sync strategy
    await _executeSyncStrategy(
      CollectionUpdateOperation(
        localId: id,
        remoteId: existing.remoteId,
        name: updatedCollection.name,
        description: updatedCollection.description,
        visibility: updatedCollection.visibility,
        tags: updatedCollection.tags.map((t) => t.name).toList(),
        markAsSynced: (remoteId) async {
          await markCollectionSynced(id, remoteId: remoteId);
        },
      ),
    );

    return updatedCollection;
  }

  /// Delete a collection with configurable sync
  Future<void> deleteCollection(
    int id, {
    String deleteMode = 'move_links',
  }) async {
    final db = await AppDb.instance();

    // Get collection to verify it exists
    final collection = await getCollectionById(id);
    if (collection == null) {
      throw ArgumentError('Collection not found');
    }

    // Execute sync strategy first (before local deletion)
    await _executeSyncStrategy(
      CollectionDeleteOperation(
        localId: id,
        remoteId: collection.remoteId,
        name: collection.name,
      ),
    );

    // Handle links based on delete mode
    if (deleteMode == 'move_links') {
      // Move all links to uncategorized (set collection to null)
      await db.update(
        'links',
        {
          'collection': null,
          'is_dirty': 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'collection = ?',
        whereArgs: [collection.name],
      );
    } else if (deleteMode == 'delete_links') {
      // Delete all links in the collection
      await db.delete(
        'links',
        where: 'collection = ?',
        whereArgs: [collection.name],
      );
    }

    // Delete collection tags
    await db.delete(
      'collection_tags',
      where: 'collection_id = ?',
      whereArgs: [id],
    );

    // Delete collection
    await db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  /// Get all collections
  Future<List<Collection>> getCollections() async {
    final db = await AppDb.instance();

    final results = await db.query('collections', orderBy: 'name ASC');

    final collections = <Collection>[];

    for (final row in results) {
      final collection = Collection.fromMap(row);
      final tags = await _getCollectionTags(collection.id!);
      collections.add(collection.copyWith(tags: tags));
    }

    return collections;
  }

  /// Get a collection by ID
  Future<Collection?> getCollectionById(int id) async {
    final db = await AppDb.instance();

    final results = await db.query(
      'collections',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final collection = Collection.fromMap(results.first);
    final tags = await _getCollectionTags(id);

    return collection.copyWith(tags: tags);
  }

  /// Get a collection by name
  Future<Collection?> getCollectionByName(String name) async {
    final db = await AppDb.instance();

    final results = await db.query(
      'collections',
      where: 'name = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final collection = Collection.fromMap(results.first);
    final tags = await _getCollectionTags(collection.id!);

    return collection.copyWith(tags: tags);
  }

  /// Get links within a specific collection
  Future<List<LinkItem>> getCollectionLinks(
    String collectionName, {
    int? limit,
    int? offset,
  }) async {
    final db = await AppDb.instance();

    final results = await db.query(
      'links',
      where: 'collection = ?',
      whereArgs: [collectionName],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => LinkItem.fromMap(row)).toList();
  }

  /// Get uncategorized links (not assigned to any collection)
  Future<List<LinkItem>> getUncategorizedLinks({
    int? limit,
    int? offset,
  }) async {
    final db = await AppDb.instance();

    final results = await db.query(
      'links',
      where: 'collection IS NULL OR collection = ""',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => LinkItem.fromMap(row)).toList();
  }

  /// Assign a link to a collection
  Future<void> assignLinkToCollection(
    int linkId,
    String? collectionName,
  ) async {
    final db = await AppDb.instance();

    // Verify link exists
    final linkResults = await db.query(
      'links',
      where: 'id = ?',
      whereArgs: [linkId],
      limit: 1,
    );

    if (linkResults.isEmpty) {
      throw ArgumentError('Link not found');
    }

    // Verify collection exists if provided
    if (collectionName != null && collectionName.isNotEmpty) {
      final collection = await getCollectionByName(collectionName);
      if (collection == null) {
        throw ArgumentError('Collection not found');
      }
    }

    // Update link's collection
    await db.update(
      'links',
      {
        'collection': collectionName,
        'is_dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [linkId],
    );

    // Update link counts for affected collections
    await updateCollectionLinkCounts();
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Validate collection data
  String? _validateCollectionData(
    String name,
    String? description,
    String visibility,
  ) {
    if (name.trim().isEmpty) {
      return 'Collection name cannot be empty';
    }
    if (name.length > 100) {
      return 'Collection name cannot exceed 100 characters';
    }
    if (description != null && description.length > 2000) {
      return 'Collection description cannot exceed 2000 characters';
    }
    if (!['public', 'private', 'hidden'].contains(visibility)) {
      return 'Invalid visibility setting';
    }
    return null;
  }

  /// Insert tags for a collection
  Future<void> _insertCollectionTags(int collectionId, List<Tag> tags) async {
    if (tags.isEmpty) return;

    final db = await AppDb.instance();

    for (final tag in tags) {
      await db.insert('collection_tags', {
        'collection_id': collectionId,
        'tag_name': tag.name,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Update tags for a collection
  Future<void> _updateCollectionTags(int collectionId, List<Tag> tags) async {
    final db = await AppDb.instance();

    // Delete existing tags
    await db.delete(
      'collection_tags',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
    );

    // Insert new tags
    await _insertCollectionTags(collectionId, tags);
  }

  /// Get tags for a collection
  Future<List<Tag>> _getCollectionTags(int collectionId) async {
    final db = await AppDb.instance();

    final results = await db.query(
      'collection_tags',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
    );

    return results
        .map((row) => Tag.fromName(row['tag_name'] as String))
        .toList();
  }

  /// Sync link assignments from API
  Future<Map<String, dynamic>> _syncLinkAssignments() async {
    final db = await AppDb.instance();
    final results = {'updated': 0, 'errors': <String>[]};

    try {
      // First, clear all existing collection assignments
      await db.update(
        'links',
        {'collection': null},
        where: 'remote_id IS NOT NULL', // Only clear synced links
      );

      // Get all local collections
      final localCollections = await db.query(
        'collections',
        where: 'remote_id IS NOT NULL',
      );

      // Sync links for each collection
      for (final collectionRow in localCollections) {
        final collection = Collection.fromMap(collectionRow);
        final remoteId = collectionRow['remote_id'] as String;

        try {
          // Get links for this collection from API
          final response = await KiojuApi.getCollectionLinks(remoteId);

          if (response['success'] == true && response['links'] != null) {
            final apiLinks = response['links'] as List;

            // Update each link's collection assignment
            for (final apiLink in apiLinks) {
              final linkRemoteId = apiLink['id'].toString();

              final updateCount = await db.update(
                'links',
                {'collection': collection.name},
                where: 'remote_id = ?',
                whereArgs: [linkRemoteId],
              );

              if (updateCount > 0) {
                results['updated'] = (results['updated'] as int) + 1;
              }
            }
          }
        } catch (e) {
          (results['errors'] as List<String>).add(
            'Error syncing links for collection ${collection.name}: $e',
          );
        }
      }

      // Also sync uncategorized links
      try {
        final response = await KiojuApi.getUncategorizedLinks();

        if (response['success'] == true && response['links'] != null) {
          final apiLinks = response['links'] as List;

          // These links should have collection = null (already cleared above)
          // Just count them as updated
          for (final apiLink in apiLinks) {
            final linkRemoteId = apiLink['id'].toString();

            // Verify the link exists locally
            final existingLinks = await db.query(
              'links',
              where: 'remote_id = ?',
              whereArgs: [linkRemoteId],
              limit: 1,
            );

            if (existingLinks.isNotEmpty) {
              results['updated'] = (results['updated'] as int) + 1;
            }
          }
        }
      } catch (e) {
        (results['errors'] as List<String>).add(
          'Error syncing uncategorized links: $e',
        );
      }
    } catch (e) {
      (results['errors'] as List<String>).add(
        'Error syncing link assignments: $e',
      );
    }

    return results;
  }

  /// Update link counts for all collections
  /// Update link counts for all collections
  Future<void> updateCollectionLinkCounts() async {
    final db = await AppDb.instance();

    // Get all collections
    final collections = await db.query('collections');

    for (final collection in collections) {
      final collectionId = collection['id'] as int;
      final collectionName = collection['name'] as String;

      // Count links in this collection
      final countResult = await db.rawQuery(
        '''
        SELECT COUNT(*) as count 
        FROM links 
        WHERE collection = ?
      ''',
        [collectionName],
      );

      final count = countResult.first['count'] as int;

      // Update collection link count
      await db.update(
        'collections',
        {'link_count': count, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [collectionId],
      );
    }
  }

  /// Mark collection as dirty for sync
  Future<void> markCollectionDirty(int collectionId) async {
    final db = await AppDb.instance();
    await db.update(
      'collections',
      {'is_dirty': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  /// Mark link as dirty for sync
  Future<void> markLinkDirty(int linkId) async {
    final db = await AppDb.instance();
    await db.update(
      'links',
      {'is_dirty': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [linkId],
    );
  }

  // ============================================================================
  // SYNC FUNCTIONALITY
  // ============================================================================

  /// Check if there are unsynced local changes
  Future<bool> hasUnsyncedChanges() async {
    final db = await AppDb.instance();

    // Check for dirty collections
    final dirtyCollections = await db.query(
      'collections',
      where: 'is_dirty = 1',
      limit: 1,
    );

    if (dirtyCollections.isNotEmpty) return true;

    // Check for dirty links
    final dirtyLinks = await db.query('links', where: 'is_dirty = 1', limit: 1);

    return dirtyLinks.isNotEmpty;
  }

  /// Get count of unsynced changes
  Future<Map<String, int>> getUnsyncedChangesCount() async {
    final db = await AppDb.instance();

    // Count dirty collections
    final collectionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections WHERE is_dirty = 1',
    );
    final collectionsCount = collectionsResult.first['count'] as int;

    // Count dirty links
    final linksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links WHERE is_dirty = 1',
    );
    final linksCount = linksResult.first['count'] as int;

    return {'collections': collectionsCount, 'links': linksCount};
  }

  /// Sync local changes up to the API
  Future<Map<String, dynamic>> syncUp() async {
    final results = <String, dynamic>{
      'success': true,
      'collections_synced': 0,
      'links_synced': 0,
      'errors': <String>[],
    };

    try {
      // Sync collections first
      final collectionsResult = await _syncCollectionsUp();
      results['collections_synced'] = collectionsResult['synced'] ?? 0;
      if (collectionsResult['errors'] != null) {
        (results['errors'] as List<String>).addAll(
          collectionsResult['errors'] as List<String>,
        );
      }

      // Sync links
      final linksResult = await _syncLinksUp();
      results['links_synced'] = linksResult['synced'] ?? 0;
      if (linksResult['errors'] != null) {
        (results['errors'] as List<String>).addAll(
          linksResult['errors'] as List<String>,
        );
      }

      // Update success status
      results['success'] = (results['errors'] as List<String>).isEmpty;
    } catch (e) {
      results['success'] = false;
      (results['errors'] as List<String>).add('Sync failed: $e');
    }

    return results;
  }

  /// Sync remote changes down from the API
  Future<Map<String, dynamic>> syncDown({bool forceOverwrite = false}) async {
    // Check for unsynced changes unless forcing overwrite
    if (!forceOverwrite) {
      final hasUnsynced = await hasUnsyncedChanges();
      if (hasUnsynced) {
        throw Exception(
          'Unsynced local changes detected. Sync up first or use forceOverwrite.',
        );
      }
    }

    final results = <String, dynamic>{
      'success': true,
      'collections_updated': 0,
      'links_updated': 0,
      'errors': <String>[],
    };

    try {
      // Fetch collections from API
      final collectionsResult = await _syncCollectionsDown(
        forceOverwrite: forceOverwrite,
      );
      results['collections_updated'] = collectionsResult['updated'] ?? 0;
      if (collectionsResult['errors'] != null) {
        (results['errors'] as List<String>).addAll(
          collectionsResult['errors'] as List<String>,
        );
      }

      // Sync link assignments after collections are synced
      final linkAssignmentResult = await _syncLinkAssignments();
      results['links_updated'] = linkAssignmentResult['updated'] ?? 0;
      if (linkAssignmentResult['errors'] != null) {
        (results['errors'] as List<String>).addAll(
          linkAssignmentResult['errors'] as List<String>,
        );
      }

      // Update link counts after sync
      await updateCollectionLinkCounts();

      // Update success status
      results['success'] = (results['errors'] as List<String>).isEmpty;
    } catch (e) {
      results['success'] = false;
      (results['errors'] as List<String>).add('Sync down failed: $e');
    }

    return results;
  }

  /// Perform full bidirectional sync
  Future<Map<String, dynamic>> fullSync({bool resolveConflicts = false}) async {
    final results = <String, dynamic>{
      'success': true,
      'sync_up': <String, dynamic>{},
      'sync_down': <String, dynamic>{},
      'errors': <String>[],
    };

    try {
      // Check for conflicts first
      if (!resolveConflicts) {
        final hasUnsynced = await hasUnsyncedChanges();
        if (hasUnsynced) {
          final counts = await getUnsyncedChangesCount();
          throw Exception(
            'Sync conflict: ${counts['collections']} collections and ${counts['links']} links have unsynced changes. '
            'Sync up first or use resolveConflicts=true.',
          );
        }
      }

      // Sync up first
      final syncUpResult = await syncUp();
      results['sync_up'] = syncUpResult;

      // Then sync down
      final syncDownResult = await syncDown(forceOverwrite: resolveConflicts);
      results['sync_down'] = syncDownResult;

      // Overall success
      results['success'] =
          (syncUpResult['success'] ?? false) &&
          (syncDownResult['success'] ?? false);

      if (syncUpResult['errors'] != null) {
        (results['errors'] as List<String>).addAll(
          syncUpResult['errors'] as List<String>,
        );
      }
      if (syncDownResult['errors'] != null) {
        (results['errors'] as List<String>).addAll(
          syncDownResult['errors'] as List<String>,
        );
      }
    } catch (e) {
      results['success'] = false;
      (results['errors'] as List<String>).add('Full sync failed: $e');
    }

    return results;
  }

  // ============================================================================
  // PRIVATE SYNC HELPERS
  // ============================================================================

  /// Sync collections up to API
  Future<Map<String, dynamic>> _syncCollectionsUp() async {
    final db = await AppDb.instance();
    final results = {'synced': 0, 'errors': <String>[]};

    // Get dirty collections
    final dirtyCollections = await db.query(
      'collections',
      where: 'is_dirty = 1',
      orderBy: 'updated_at ASC',
    );

    for (final row in dirtyCollections) {
      try {
        final collection = Collection.fromMap(row);

        if (collection.remoteId == null) {
          // Create new collection on API
          try {
            final response = await KiojuApi.createCollection(
              name: collection.name,
              description: collection.description,
              visibility: collection.visibility,
              tags: collection.tags.map((t) => t.name).toList(),
            );

            if (response['success'] == true && response['collection'] != null) {
              final apiCollection = response['collection'];

              // Update local collection with remote ID
              await db.update(
                'collections',
                {
                  'remote_id': apiCollection['id'].toString(),
                  'is_dirty': 0,
                  'last_synced_at': DateTime.now().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [collection.id],
              );

              results['synced'] = (results['synced'] as int) + 1;
            } else {
              (results['errors'] as List<String>).add(
                'Failed to create collection "${collection.name}": ${response['message'] ?? 'Unknown error'}',
              );
            }
          } catch (e) {
            String errorMessage =
                'Failed to create collection "${collection.name}": $e';

            // Handle specific HTTP errors
            if (e.toString().contains('409')) {
              // 409 could mean collection already exists OR was just created but returned error
              // Always try to find the collection and link to it
              try {
                // Wait a moment for server to settle
                await Future.delayed(const Duration(milliseconds: 500));

                final listResponse = await KiojuApi.listCollections();

                if (listResponse['success'] == true &&
                    listResponse['collections'] != null) {
                  final apiCollections = listResponse['collections'] as List;
                  final existingCollection = apiCollections.firstWhere(
                    (c) => c['name'] == collection.name,
                    orElse: () => null,
                  );

                  if (existingCollection != null) {
                    // Collection exists (either was already there or just created) - link to it
                    await db.update(
                      'collections',
                      {
                        'remote_id': existingCollection['id'].toString(),
                        'is_dirty': 0,
                        'last_synced_at': DateTime.now().toIso8601String(),
                      },
                      where: 'id = ?',
                      whereArgs: [collection.id],
                    );

                    results['synced'] = (results['synced'] as int) + 1;
                  } else {
                    // Collection doesn't exist despite 409 - this is a real error
                    errorMessage =
                        'Collection "${collection.name}" returned 409 but does not exist on server';
                    (results['errors'] as List<String>).add(errorMessage);
                  }
                } else {
                  errorMessage =
                      'Collection "${collection.name}" returned 409 but could not retrieve collection list to verify';
                  (results['errors'] as List<String>).add(errorMessage);
                }
              } catch (linkError) {
                errorMessage =
                    'Collection "${collection.name}" returned 409 and failed to verify/link: $linkError';
                (results['errors'] as List<String>).add(errorMessage);
              }
            } else if (e.toString().contains('400')) {
              errorMessage =
                  'Invalid collection data for "${collection.name}" (400 Bad Request)';
              (results['errors'] as List<String>).add(errorMessage);
            } else {
              (results['errors'] as List<String>).add(errorMessage);
            }
          }
        } else {
          // Update existing collection on API
          final response = await KiojuApi.updateCollection(
            id: collection.remoteId!,
            name: collection.name,
            description: collection.description,
            visibility: collection.visibility,
            tags: collection.tags.map((t) => t.name).toList(),
          );

          if (response['success'] == true) {
            // Mark as synced
            await db.update(
              'collections',
              {
                'is_dirty': 0,
                'last_synced_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [collection.id],
            );

            results['synced'] = (results['synced'] as int) + 1;
          } else {
            (results['errors'] as List<String>).add(
              'Failed to update collection "${collection.name}": ${response['message'] ?? 'Unknown error'}',
            );
          }
        }
      } catch (e) {
        (results['errors'] as List<String>).add('Error syncing collection: $e');
      }
    }

    return results;
  }

  /// Sync links up to API (create new links and update collection assignments)
  Future<Map<String, dynamic>> _syncLinksUp() async {
    final db = await AppDb.instance();
    final results = {'synced': 0, 'errors': <String>[]};

    // First, sync new links (those without remote_id)
    final newLinks = await db.query(
      'links',
      where: 'remote_id IS NULL',
      orderBy: 'created_at ASC',
    );

    for (final row in newLinks) {
      try {
        final link = LinkItem.fromMap(row);

        // Create link via API
        final response = await KiojuApi.addLink(
          url: link.url,
          title: link.title,
          tags: link.tags.isNotEmpty ? link.tags : null,
          isPrivate: '1', // Default to private for safety
        );

        if (response['success'] == true && response['link'] != null) {
          final apiLink = response['link'];
          final remoteId = apiLink['id']?.toString();

          if (remoteId != null) {
            // Update local link with remote ID
            await db.update(
              'links',
              {
                'remote_id': remoteId,
                'is_dirty': 0,
                'last_synced_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [link.id],
            );

            // If the link has a collection assignment, sync that too
            if (link.collection != null && link.collection!.isNotEmpty) {
              final collectionResult = await db.query(
                'collections',
                columns: ['remote_id'],
                where: 'name = ?',
                whereArgs: [link.collection],
                limit: 1,
              );

              if (collectionResult.isNotEmpty) {
                final collectionRemoteId =
                    collectionResult.first['remote_id'] as String?;
                if (collectionRemoteId != null) {
                  await KiojuApi.assignLinkToCollection(
                    linkId: remoteId,
                    collectionId: collectionRemoteId,
                  );
                }
              }
            }

            results['synced'] = (results['synced'] as int) + 1;
          }
        } else {
          (results['errors'] as List<String>).add(
            'Failed to create link "${link.title ?? link.url}": ${response['message'] ?? 'Unknown error'}',
          );
        }
      } catch (e) {
        // Handle 409 conflicts for links (duplicate URL) - just mark as warning, not error
        if (e.toString().contains('409')) {
          (results['errors'] as List<String>).add(
            'Warning: Link may already exist (409 conflict) - skipping',
          );
        } else {
          (results['errors'] as List<String>).add('Error creating link: $e');
        }
      }
    }

    // Then, sync collection assignments for existing dirty links
    final dirtyLinks = await db.query(
      'links',
      where: 'is_dirty = 1 AND remote_id IS NOT NULL',
      orderBy: 'updated_at ASC',
    );

    for (final row in dirtyLinks) {
      try {
        final link = LinkItem.fromMap(row);

        if (link.remoteId != null) {
          // Find collection remote ID if assigned
          String? collectionRemoteId;
          if (link.collection != null && link.collection!.isNotEmpty) {
            final collectionResult = await db.query(
              'collections',
              columns: ['remote_id'],
              where: 'name = ?',
              whereArgs: [link.collection],
              limit: 1,
            );

            if (collectionResult.isNotEmpty) {
              collectionRemoteId =
                  collectionResult.first['remote_id'] as String?;
            }
          }

          // Assign link to collection via API
          final response = await KiojuApi.assignLinkToCollection(
            linkId: link.remoteId!,
            collectionId: collectionRemoteId,
          );

          if (response['success'] == true) {
            // Mark link as synced
            await db.update(
              'links',
              {
                'is_dirty': 0,
                'last_synced_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [link.id],
            );

            results['synced'] = (results['synced'] as int) + 1;
          } else {
            (results['errors'] as List<String>).add(
              'Failed to assign link to collection: ${response['message'] ?? 'Unknown error'}',
            );
          }
        }
      } catch (e) {
        // Handle 409 conflicts for collection assignments - just mark as synced since assignment might already exist
        if (e.toString().contains('409')) {
          try {
            await db.update(
              'links',
              {
                'is_dirty': 0,
                'last_synced_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
            results['synced'] = (results['synced'] as int) + 1;
          } catch (updateError) {
            (results['errors'] as List<String>).add(
              'Link collection assignment returned 409 and failed to mark as synced: $updateError',
            );
          }
        } else {
          (results['errors'] as List<String>).add('Error syncing link: $e');
        }
      }
    }

    return results;
  }

  /// Sync collections down from API
  Future<Map<String, dynamic>> _syncCollectionsDown({
    bool forceOverwrite = false,
  }) async {
    final db = await AppDb.instance();
    final results = {'updated': 0, 'errors': <String>[]};

    try {
      // Fetch collections from API
      final response = await KiojuApi.listCollections();

      if (response['success'] == true && response['collections'] != null) {
        final apiCollections = response['collections'] as List;

        // Get API collection IDs for comparison
        final apiCollectionIds =
            apiCollections
                .map((c) => c['id']?.toString())
                .where((id) => id != null && id.isNotEmpty)
                .toSet();

        if (forceOverwrite) {
          // When force overwriting, clear all local collections and replace with API collections

          // First, get all local collections to update their links to uncategorized
          final allLocalCollections = await db.query('collections');
          for (final localCollection in allLocalCollections) {
            final collectionName = localCollection['name'] as String;
            // Update links that were assigned to this collection to be uncategorized
            await db.update(
              'links',
              {'collection': null, 'is_dirty': 1},
              where: 'collection = ?',
              whereArgs: [collectionName],
            );
          }

          // Clear all collection tags
          await db.delete('collection_tags');

          // Clear all collections
          await db.delete('collections');
        } else {
          // Normal sync: remove local collections that no longer exist on API
          final localCollections = await db.query('collections');

          for (final localCollection in localCollections) {
            final remoteId = localCollection['remote_id'] as String?;
            final collectionName = localCollection['name'] as String;
            final collectionId = localCollection['id'] as int;

            // If this local collection has a remote_id but it's not in the API list, remove it
            if (remoteId != null && !apiCollectionIds.contains(remoteId)) {
              // Remove collection tags first
              await db.delete(
                'collection_tags',
                where: 'collection_id = ?',
                whereArgs: [collectionId],
              );

              // Remove the collection
              await db.delete(
                'collections',
                where: 'id = ?',
                whereArgs: [collectionId],
              );

              // Update links that were assigned to this collection to be uncategorized
              await db.update(
                'links',
                {'collection': null, 'is_dirty': 1},
                where: 'collection = ?',
                whereArgs: [collectionName],
              );

              results['updated'] = (results['updated'] as int) + 1;
            }
            // If this is a local-only collection (no remote_id), keep it during normal sync
            // Only remove local-only collections during forceOverwrite
          }
        }

        // Process API collections
        for (final apiCollection in apiCollections) {
          try {
            final remoteId = apiCollection['id']?.toString();
            if (remoteId == null || remoteId.isEmpty) {
              (results['errors'] as List<String>).add(
                'Collection has no ID, skipping: ${apiCollection['name'] ?? 'Unknown'}',
              );
              continue;
            }

            final collectionName = apiCollection['name'] as String?;
            if (collectionName == null || collectionName.isEmpty) {
              (results['errors'] as List<String>).add(
                'Collection has no name, skipping ID: $remoteId',
              );
              continue;
            }

            final now = DateTime.now().toIso8601String();

            if (forceOverwrite) {
              // When force overwriting, always create new collections
              final collection = Collection.fromApiResponse(apiCollection);
              final collectionMap = collection.toMap();
              collectionMap['remote_id'] = remoteId;
              collectionMap['is_dirty'] = 0;
              collectionMap['last_synced_at'] = now;

              final id = await db.insert('collections', collectionMap);

              // Insert tags
              if (collection.tags.isNotEmpty) {
                await _insertCollectionTags(id, collection.tags);
              }

              results['updated'] = (results['updated'] as int) + 1;
            } else {
              // Normal sync: check if collection exists locally
              final existingResult = await db.query(
                'collections',
                where: 'remote_id = ?',
                whereArgs: [remoteId],
                limit: 1,
              );

              if (existingResult.isEmpty) {
                // Create new local collection
                final collection = Collection.fromApiResponse(apiCollection);
                final collectionMap = collection.toMap();
                collectionMap['remote_id'] = remoteId;
                collectionMap['is_dirty'] = 0;
                collectionMap['last_synced_at'] = now;

                final id = await db.insert('collections', collectionMap);

                // Insert tags
                if (collection.tags.isNotEmpty) {
                  await _insertCollectionTags(id, collection.tags);
                }

                results['updated'] = (results['updated'] as int) + 1;
              } else {
                // Update existing collection
                final existingCollection = Collection.fromMap(
                  existingResult.first,
                );
                final updatedCollection = Collection.fromApiResponse(
                  apiCollection,
                );

                final collectionMap = updatedCollection.toMap();
                collectionMap['id'] = existingCollection.id;
                collectionMap['remote_id'] = remoteId;
                collectionMap['is_dirty'] = 0;
                collectionMap['last_synced_at'] = now;

                await db.update(
                  'collections',
                  collectionMap,
                  where: 'id = ?',
                  whereArgs: [existingCollection.id],
                );

                // Update tags
                await _updateCollectionTags(
                  existingCollection.id!,
                  updatedCollection.tags,
                );

                results['updated'] = (results['updated'] as int) + 1;
              }
            }
          } catch (e) {
            (results['errors'] as List<String>).add(
              'Error processing collection from API: $e',
            );
          }
        }
      } else {
        (results['errors'] as List<String>).add(
          'Failed to fetch collections from API: ${response['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      (results['errors'] as List<String>).add(
        'Error fetching collections from API: $e',
      );
    }

    return results;
  }

  // ============================================================================
  // CACHING AND DIRTY FLAG MANAGEMENT
  // ============================================================================

  /// Get collections that need sync (dirty or never synced)
  Future<List<Collection>> getCollectionsNeedingSync() async {
    final db = await AppDb.instance();

    final results = await db.query(
      'collections',
      where: 'is_dirty = 1 OR last_synced_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    final collections = <Collection>[];

    for (final row in results) {
      final collection = Collection.fromMap(row);
      final tags = await _getCollectionTags(collection.id!);
      collections.add(collection.copyWith(tags: tags));
    }

    return collections;
  }

  /// Get links that need sync (dirty or never synced)
  Future<List<LinkItem>> getLinksNeedingSync() async {
    final db = await AppDb.instance();

    final results = await db.query(
      'links',
      where: 'is_dirty = 1 OR last_synced_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    return results.map((row) => LinkItem.fromMap(row)).toList();
  }

  /// Clear all dirty flags (after successful sync)
  Future<void> clearAllDirtyFlags() async {
    final db = await AppDb.instance();
    final now = DateTime.now().toIso8601String();

    await db.update('collections', {
      'is_dirty': 0,
      'last_synced_at': now,
    }, where: 'is_dirty = 1');

    await db.update('links', {
      'is_dirty': 0,
      'last_synced_at': now,
    }, where: 'is_dirty = 1');
  }

  /// Mark collection as synced
  Future<void> markCollectionSynced(
    int collectionId, {
    String? remoteId,
  }) async {
    final db = await AppDb.instance();
    final updateData = {
      'is_dirty': 0,
      'last_synced_at': DateTime.now().toIso8601String(),
    };

    if (remoteId != null) {
      updateData['remote_id'] = remoteId;
    }

    await db.update(
      'collections',
      updateData,
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  /// Mark link as synced
  Future<void> markLinkSynced(int linkId, {String? remoteId}) async {
    final db = await AppDb.instance();
    final updateData = {
      'is_dirty': 0,
      'last_synced_at': DateTime.now().toIso8601String(),
    };

    if (remoteId != null) {
      updateData['remote_id'] = remoteId;
    }

    await db.update('links', updateData, where: 'id = ?', whereArgs: [linkId]);
  }

  /// Get sync status for collections and links
  Future<Map<String, dynamic>> getSyncStatus() async {
    final db = await AppDb.instance();

    // Count total collections and links
    final totalCollectionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections',
    );
    final totalLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links',
    );

    // Count dirty items
    final dirtyCollectionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections WHERE is_dirty = 1',
    );
    final dirtyLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links WHERE is_dirty = 1',
    );

    // Count never synced items
    final unsyncedCollectionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections WHERE last_synced_at IS NULL',
    );
    final unsyncedLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links WHERE last_synced_at IS NULL',
    );

    // Get last sync times
    final lastCollectionSyncResult = await db.rawQuery(
      'SELECT MAX(last_synced_at) as last_sync FROM collections WHERE last_synced_at IS NOT NULL',
    );
    final lastLinkSyncResult = await db.rawQuery(
      'SELECT MAX(last_synced_at) as last_sync FROM links WHERE last_synced_at IS NOT NULL',
    );

    return {
      'collections': {
        'total': totalCollectionsResult.first['count'] as int,
        'dirty': dirtyCollectionsResult.first['count'] as int,
        'never_synced': unsyncedCollectionsResult.first['count'] as int,
        'last_sync': lastCollectionSyncResult.first['last_sync'] as String?,
      },
      'links': {
        'total': totalLinksResult.first['count'] as int,
        'dirty': dirtyLinksResult.first['count'] as int,
        'never_synced': unsyncedLinksResult.first['count'] as int,
        'last_sync': lastLinkSyncResult.first['last_sync'] as String?,
      },
    };
  }

  /// Get count of pending changes that need to be synced
  Future<Map<String, dynamic>> getPendingChangesCount() async {
    final db = await AppDb.instance();

    // Count dirty collections (modified locally)
    final dirtyCollectionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections WHERE is_dirty = 1',
    );
    final dirtyCollections = dirtyCollectionsResult.first['count'] as int;

    // Count dirty links (modified locally)
    final dirtyLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links WHERE is_dirty = 1',
    );
    final dirtyLinks = dirtyLinksResult.first['count'] as int;

    // Count new collections (never synced)
    final newCollectionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections WHERE remote_id IS NULL',
    );
    final newCollections = newCollectionsResult.first['count'] as int;

    // Count new links (never synced)
    final newLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links WHERE remote_id IS NULL',
    );
    final newLinks = newLinksResult.first['count'] as int;

    final totalCollections = dirtyCollections + newCollections;
    final totalLinks = dirtyLinks + newLinks;

    return {
      'collections': {
        'dirty': dirtyCollections,
        'new': newCollections,
        'total': totalCollections,
      },
      'links': {'dirty': dirtyLinks, 'new': newLinks, 'total': totalLinks},
      'total': totalCollections + totalLinks,
    };
  }

  /// Refresh collection cache from database
  Future<void> refreshCollectionCache() async {
    // This method can be used to invalidate any in-memory caches
    // For now, we're using direct database queries, so no action needed
    // But this provides a hook for future caching implementations
  }

  /// Clean up orphaned data
  Future<void> cleanupOrphanedData() async {
    final db = await AppDb.instance();

    // Remove collection tags for non-existent collections
    await db.rawDelete('''
      DELETE FROM collection_tags 
      WHERE collection_id NOT IN (SELECT id FROM collections)
    ''');

    // Update link counts for all collections
    await updateCollectionLinkCounts();
  }

  /// Get collection statistics
  Future<Map<String, dynamic>> getCollectionStatistics() async {
    final db = await AppDb.instance();

    // Total collections
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections',
    );
    final total = totalResult.first['count'] as int;

    // Collections by visibility
    final publicResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM collections WHERE visibility = 'public'",
    );
    final privateResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM collections WHERE visibility = 'private'",
    );
    final hiddenResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM collections WHERE visibility = 'hidden'",
    );

    // Collections with links
    final withLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM collections WHERE link_count > 0',
    );

    // Average links per collection
    final avgLinksResult = await db.rawQuery(
      'SELECT AVG(link_count) as avg FROM collections WHERE link_count > 0',
    );

    // Most popular collection
    final popularResult = await db.rawQuery(
      'SELECT name, link_count FROM collections ORDER BY link_count DESC LIMIT 1',
    );

    // Total links in collections vs uncategorized
    final totalLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links',
    );
    final categorizedLinksResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM links WHERE collection IS NOT NULL AND collection != ""',
    );

    final totalLinks = totalLinksResult.first['count'] as int;
    final categorizedLinks = categorizedLinksResult.first['count'] as int;
    final uncategorizedLinks = totalLinks - categorizedLinks;

    return {
      'total_collections': total,
      'visibility': {
        'public': publicResult.first['count'] as int,
        'private': privateResult.first['count'] as int,
        'hidden': hiddenResult.first['count'] as int,
      },
      'collections_with_links': withLinksResult.first['count'] as int,
      'average_links_per_collection':
          avgLinksResult.first['avg'] as double? ?? 0.0,
      'most_popular_collection':
          popularResult.isNotEmpty
              ? {
                'name': popularResult.first['name'] as String,
                'link_count': popularResult.first['link_count'] as int,
              }
              : null,
      'links': {
        'total': totalLinks,
        'categorized': categorizedLinks,
        'uncategorized': uncategorizedLinks,
        'categorization_percentage':
            totalLinks > 0 ? (categorizedLinks / totalLinks * 100).round() : 0,
      },
    };
  }

  /// Validate database integrity
  Future<List<String>> validateDatabaseIntegrity() async {
    final db = await AppDb.instance();
    final issues = <String>[];

    // Check for collections with invalid link counts
    final invalidCountsResult = await db.rawQuery('''
      SELECT c.id, c.name, c.link_count, 
             (SELECT COUNT(*) FROM links WHERE collection = c.name) as actual_count
      FROM collections c
      WHERE c.link_count != (SELECT COUNT(*) FROM links WHERE collection = c.name)
    ''');

    for (final row in invalidCountsResult) {
      issues.add(
        'Collection "${row['name']}" has incorrect link count: stored=${row['link_count']}, actual=${row['actual_count']}',
      );
    }

    // Check for orphaned collection tags
    final orphanedTagsResult = await db.rawQuery('''
      SELECT collection_id, tag_name
      FROM collection_tags
      WHERE collection_id NOT IN (SELECT id FROM collections)
    ''');

    if (orphanedTagsResult.isNotEmpty) {
      issues.add('Found ${orphanedTagsResult.length} orphaned collection tags');
    }

    // Check for links with non-existent collections
    final invalidLinksResult = await db.rawQuery('''
      SELECT id, url, collection
      FROM links
      WHERE collection IS NOT NULL 
        AND collection != ""
        AND collection NOT IN (SELECT name FROM collections)
    ''');

    for (final row in invalidLinksResult) {
      issues.add(
        'Link "${row['url']}" references non-existent collection "${row['collection']}"',
      );
    }

    return issues;
  }
}
