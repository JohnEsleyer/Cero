import 'dart:convert';

class CommentItem {
  final String id;
  final String text;
  final DateTime createdAt;

  CommentItem({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CommentItem.fromMap(Map<String, dynamic> map) => CommentItem(
    id: map['id'] ?? '',
    text: map['text'] ?? '',
    createdAt: map['createdAt'] != null
        ? DateTime.parse(map['createdAt'])
        : DateTime.now(),
  );

  CommentItem copyWith({String? text}) => CommentItem(
    id: id,
    text: text ?? this.text,
    createdAt: createdAt,
  );
}

class Card {
  final String id;
  final String pageId;
  final String type; // 'markdown', 'image', 'subpage_link', 'file'
  final String content;
  final String comment;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;

  Card({
    required this.id,
    required this.pageId,
    required this.type,
    required this.content,
    this.comment = '',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 0,
  });

  List<CommentItem> get commentsList {
    if (comment.isEmpty) return [];
    try {
      final list = json.decode(comment);
      if (list is List) {
        return list.map((e) => CommentItem.fromMap(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {}
    return [];
  }

  static String commentsToJson(List<CommentItem> items) =>
      json.encode(items.map((e) => e.toMap()).toList());

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'page_id': pageId,
      'type': type,
      'content': content,
      'comment': comment,
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
      comment: map['comment'] ?? '',
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
    String? comment,
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
      comment: comment ?? this.comment,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      revision: revision ?? this.revision,
    );
  }
}
