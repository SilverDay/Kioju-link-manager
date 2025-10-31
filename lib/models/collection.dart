/// Model representing a collection (folder) for organizing links
class Collection {
  final int? id;
  final String? remoteId;
  final String name;
  final String? description;
  final String visibility; // 'public', 'private', 'hidden'
  final int linkCount;
  final bool isDirty; // Track local changes for sync
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastSyncedAt;
  final List<Tag> tags;

  Collection({
    this.id,
    this.remoteId,
    required this.name,
    this.description,
    this.visibility = 'public',
    this.linkCount = 0,
    this.isDirty = false,
    this.createdAt,
    this.updatedAt,
    this.lastSyncedAt,
    this.tags = const [],
  });

  /// Convert collection to database map
  Map<String, Object?> toMap() => {
    'id': id,
    'remote_id': remoteId,
    'name': name,
    'description': description,
    'visibility': visibility,
    'link_count': linkCount,
    'is_dirty': isDirty ? 1 : 0,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'last_synced_at': lastSyncedAt?.toIso8601String(),
  };

  /// Create collection from database map
  static Collection fromMap(Map<String, Object?> map) => Collection(
    id: map['id'] as int?,
    remoteId: map['remote_id'] as String?,
    name: map['name'] as String,
    description: map['description'] as String?,
    visibility: map['visibility'] as String? ?? 'public',
    linkCount: map['link_count'] as int? ?? 0,
    isDirty: (map['is_dirty'] as int? ?? 0) == 1,
    createdAt: map['created_at'] != null 
      ? DateTime.parse(map['created_at'] as String)
      : null,
    updatedAt: map['updated_at'] != null 
      ? DateTime.parse(map['updated_at'] as String)
      : null,
    lastSyncedAt: map['last_synced_at'] != null 
      ? DateTime.parse(map['last_synced_at'] as String)
      : null,
    tags: [], // Tags loaded separately from junction table
  );

  /// Create collection from API response
  static Collection fromApiResponse(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      throw ArgumentError('Collection name cannot be null or empty');
    }
    
    return Collection(
      remoteId: json['id']?.toString(),
      name: name,
      description: json['description'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      linkCount: json['link_count'] as int? ?? 0,
      createdAt: json['created_at'] != null 
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
      updatedAt: json['updated_at'] != null 
        ? DateTime.tryParse(json['updated_at'] as String)
        : null,
      tags: (json['tags'] as List?)
        ?.map((t) => Tag.fromJson(t as Map<String, dynamic>))
        .toList() ?? [],
    );
  }

  /// Convert collection to API request format
  Map<String, dynamic> toApiRequest() => {
    'name': name,
    if (description != null) 'description': description,
    'visibility': visibility,
    if (tags.isNotEmpty) 'tags': tags.map((t) => t.name).join(','),
  };

  /// Create a copy with updated fields
  Collection copyWith({
    int? id,
    String? remoteId,
    String? name,
    String? description,
    String? visibility,
    int? linkCount,
    bool? isDirty,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
    List<Tag>? tags,
  }) => Collection(
    id: id ?? this.id,
    remoteId: remoteId ?? this.remoteId,
    name: name ?? this.name,
    description: description ?? this.description,
    visibility: visibility ?? this.visibility,
    linkCount: linkCount ?? this.linkCount,
    isDirty: isDirty ?? this.isDirty,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    tags: tags ?? this.tags,
  );

  /// Mark collection as dirty (needs sync)
  Collection markDirty() => copyWith(
    isDirty: true,
    updatedAt: DateTime.now(),
  );

  /// Mark collection as synced
  Collection markSynced() => copyWith(
    isDirty: false,
    lastSyncedAt: DateTime.now(),
  );

  /// Check if collection has unsynced changes
  bool get hasUnsyncedChanges => isDirty;

  /// Check if collection needs sync (has changes or never synced)
  bool get needsSync => isDirty || lastSyncedAt == null;

  /// Validate collection data
  String? validate() {
    if (name.trim().isEmpty) {
      return 'Collection name cannot be empty';
    }
    if (name.length > 100) {
      return 'Collection name cannot exceed 100 characters';
    }
    if (description != null && description!.length > 2000) {
      return 'Collection description cannot exceed 2000 characters';
    }
    if (!['public', 'private', 'hidden'].contains(visibility)) {
      return 'Invalid visibility setting';
    }
    return null;
  }

  @override
  String toString() => 'Collection(id: $id, name: $name, linkCount: $linkCount)';

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is Collection &&
    runtimeType == other.runtimeType &&
    id == other.id &&
    remoteId == other.remoteId &&
    name == other.name;

  @override
  int get hashCode => Object.hash(id, remoteId, name);
}

/// Model representing a tag for collections
class Tag {
  final int? id;
  final String name;
  final String slug;

  const Tag({
    this.id,
    required this.name,
    required this.slug,
  });

  /// Convert tag to database map
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'slug': slug,
  };

  /// Create tag from database map
  static Tag fromMap(Map<String, Object?> map) => Tag(
    id: map['id'] as int?,
    name: map['name'] as String,
    slug: map['slug'] as String,
  );

  /// Create tag from API response
  static Tag fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as int?,
    name: json['canonical_name'] as String? ?? json['name'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
  );

  /// Convert tag to API format
  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
  };

  /// Create a slug from tag name
  static String createSlug(String name) {
    return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Create tag from name (generates slug automatically)
  static Tag fromName(String name) => Tag(
    name: name,
    slug: createSlug(name),
  );

  @override
  String toString() => 'Tag(name: $name, slug: $slug)';

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is Tag &&
    runtimeType == other.runtimeType &&
    name == other.name &&
    slug == other.slug;

  @override
  int get hashCode => Object.hash(name, slug);
}

/// Enum for collection visibility options
enum CollectionVisibility {
  public('public'),
  private('private'),
  hidden('hidden');

  const CollectionVisibility(this.value);
  final String value;

  static CollectionVisibility fromString(String value) {
    return CollectionVisibility.values.firstWhere(
      (v) => v.value == value,
      orElse: () => CollectionVisibility.public,
    );
  }
}

/// Helper class for collection operations
class CollectionHelper {
  /// Validate collection name
  static String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Collection name is required';
    }
    if (name.length > 100) {
      return 'Collection name cannot exceed 100 characters';
    }
    return null;
  }

  /// Validate collection description
  static String? validateDescription(String? description) {
    if (description != null && description.length > 2000) {
      return 'Collection description cannot exceed 2000 characters';
    }
    return null;
  }

  /// Get display name for visibility
  static String getVisibilityDisplayName(String visibility) {
    switch (visibility) {
      case 'public':
        return 'Public';
      case 'private':
        return 'Private';
      case 'hidden':
        return 'Hidden';
      default:
        return 'Unknown';
    }
  }

  /// Get icon for visibility
  static String getVisibilityIcon(String visibility) {
    switch (visibility) {
      case 'public':
        return '🌐';
      case 'private':
        return '🔒';
      case 'hidden':
        return '👁️‍🗨️';
      default:
        return '❓';
    }
  }

  /// Sort collections by name
  static List<Collection> sortByName(List<Collection> collections) {
    final sorted = List<Collection>.from(collections);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  /// Sort collections by link count (descending)
  static List<Collection> sortByLinkCount(List<Collection> collections) {
    final sorted = List<Collection>.from(collections);
    sorted.sort((a, b) => b.linkCount.compareTo(a.linkCount));
    return sorted;
  }

  /// Sort collections by creation date (newest first)
  static List<Collection> sortByCreatedAt(List<Collection> collections) {
    final sorted = List<Collection>.from(collections);
    sorted.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return sorted;
  }
}
