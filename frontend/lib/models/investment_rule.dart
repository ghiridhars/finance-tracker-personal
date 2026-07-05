class InvestmentRule {
  final int id;
  final String platformName;
  final String assetClass;
  final String keywords;

  InvestmentRule({
    required this.id,
    required this.platformName,
    required this.assetClass,
    required this.keywords,
  });

  factory InvestmentRule.fromJson(Map<String, dynamic> json) {
    return InvestmentRule(
      id: json['id'],
      platformName: json['platform_name'] ?? '',
      assetClass: json['asset_class'] ?? '',
      keywords: json['keywords'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'platform_name': platformName,
      'asset_class': assetClass,
      'keywords': keywords,
    };
  }
}
