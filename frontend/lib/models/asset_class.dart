class AssetClass {
  final int id;
  final String name;
  final String colorHex;
  final String iconName;

  AssetClass({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.iconName,
  });

  factory AssetClass.fromJson(Map<String, dynamic> json) {
    return AssetClass(
      id: json['id'],
      name: json['name'] ?? '',
      colorHex: json['color_hex'] ?? '#4CAF50',
      iconName: json['icon_name'] ?? 'account_balance_wallet',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color_hex': colorHex,
      'icon_name': iconName,
    };
  }
}
