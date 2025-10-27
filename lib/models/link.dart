class LinkItem {
  final int? id;
  final String url;
  final String? title;
  final String? notes;
  final List<String> tags;
  final String? collection;
  final String? remoteId; // Kioju id
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LinkItem({
    this.id,
    required this.url,
    this.title,
    this.notes,
    this.tags = const [],
    this.collection,
    this.remoteId,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'url': url,
        'title': title,
        'notes': notes,
        'tags': tags.join(','),
        'collection': collection,
        'remote_id': remoteId,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  static LinkItem fromMap(Map<String, Object?> m) => LinkItem(
        id: m['id'] as int?,
        url: m['url'] as String,
        title: m['title'] as String?,
        notes: m['notes'] as String?,
        tags: (m['tags'] as String? ?? '').split(',').where((e) => e.isNotEmpty).toList(),
        collection: m['collection'] as String?,
        remoteId: m['remote_id'] as String?,
        createdAt: (m['created_at'] as String?) != null ? DateTime.parse(m['created_at'] as String) : null,
        updatedAt: (m['updated_at'] as String?) != null ? DateTime.parse(m['updated_at'] as String) : null,
      );
}
