class Category {
  final int? id;
  final String name;
  final String? icon;
  final String? color;
  final int? parentId;
  final bool isSystem;

  Category({
    this.id,
    required this.name,
    this.icon,
    this.color,
    this.parentId,
    this.isSystem = true,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'] ?? '',
      icon: json['icon'],
      color: json['color'],
      parentId: json['parent_id'],
      isSystem: json['is_system'] ?? true,
    );
  }

  @override
  String toString() => name;
}

