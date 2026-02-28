/// Category model for transaction categorization.
class CategoryKeyword {
  final int? id;
  final String keyword;
  final int? categoryId;

  CategoryKeyword({this.id, required this.keyword, this.categoryId});

  factory CategoryKeyword.fromJson(Map<String, dynamic> json) {
    return CategoryKeyword(
      id: json['id'],
      keyword: json['keyword'] ?? '',
      categoryId: json['category_id'],
    );
  }
}

class Category {
  final int? id;
  final String name;
  final String? icon;
  final String? color;
  final int? parentId;
  final bool isSystem;
  final List<CategoryKeyword> keywords;

  Category({
    this.id,
    required this.name,
    this.icon,
    this.color,
    this.parentId,
    this.isSystem = true,
    this.keywords = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'] ?? '',
      icon: json['icon'],
      color: json['color'],
      parentId: json['parent_id'],
      isSystem: json['is_system'] ?? true,
      keywords: (json['keywords'] as List<dynamic>?)
              ?.map((k) => CategoryKeyword.fromJson(k))
              .toList() ??
          [],
    );
  }

  @override
  String toString() => name;
}

class Tag {
  final int? id;
  final String name;
  final String? color;

  Tag({this.id, required this.name, this.color});

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'],
      name: json['name'] ?? '',
      color: json['color'],
    );
  }

  @override
  String toString() => name;
}
