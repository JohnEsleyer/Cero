import 'dart:convert';

class Card {
  final String id;
  final String pageId;
  final String type; // 'markdown', 'image', 'subpage_link', 'file'
  final String content;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;

  Card({
    required this.id,
    required this.pageId,
    required this.type,
    required this.content,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'page_id': pageId,
      'type': type,
      'content': content,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'revision': revision,
    };
  }

  factory Card.fromMap(Map<String, dynamic> map) {
    return Card(
      id: map['id'] ?? '',
      pageId: map['page_id'] ?? '',
      type: map['type'] ?? 'markdown',
      content: map['content'] ?? '',
      sortOrder: map['sort_order'] ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
      revision: map['revision'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Card.fromJson(String source) => Card.fromMap(json.decode(source));

  Card copyWith({
    String? id,
    String? pageId,
    String? type,
    String? content,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? revision,
  }) {
    return Card(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      type: type ?? this.type,
      content: content ?? this.content,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }
}
