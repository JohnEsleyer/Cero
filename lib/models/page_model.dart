import 'dart:convert';

class DbPage {
  final String id;
  final String? parentId;
  final String title;
  final String content;
  final String emoji;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  final int sortOrder;
  final int revision;

  DbPage({
    required this.id,
    this.parentId,
    required this.title,
    required this.content,
    required this.emoji,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.sortOrder = 0,
    this.revision = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'parent_id': parentId,
      'title': title,
      'content': content,
      'emoji': emoji,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_archived': isArchived ? 1 : 0,
      'sort_order': sortOrder,
      'revision': revision,
    };
  }

  factory DbPage.fromMap(Map<String, dynamic> map) {
    final parentVal = map['parent_id'];
    return DbPage(
      id: map['id'] ?? '',
      parentId: (parentVal == null || parentVal == '') ? null : parentVal,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      emoji: map['emoji'] ?? '📓',
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at']) 
          : DateTime.now(),
      updatedAt: map['updated_at'] != null 
          ? DateTime.parse(map['updated_at']) 
          : DateTime.now(),
      isArchived: (map['is_archived'] ?? 0) == 1,
      sortOrder: map['sort_order'] ?? 0,
      revision: map['revision'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory DbPage.fromJson(String source) => DbPage.fromMap(json.decode(source));

  DbPage copyWith({
    String? id,
    String? parentId,
    String? title,
    String? content,
    String? emoji,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
    int? sortOrder,
    int? revision,
  }) {
    return DbPage(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      content: content ?? this.content,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
      revision: revision ?? this.revision,
    );
  }
}
