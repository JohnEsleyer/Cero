import 'dart:convert';

class DbItem {
  final String id;
  final String title;
  final String content;
  final DateTime updatedAt;

  DbItem({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DbItem.fromMap(Map<String, dynamic> map) {
    return DbItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt']) 
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory DbItem.fromJson(String source) => DbItem.fromMap(json.decode(source));

  DbItem copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? updatedAt,
  }) {
    return DbItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
