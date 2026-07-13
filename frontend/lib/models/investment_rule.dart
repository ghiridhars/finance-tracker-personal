import 'asset_class.dart';

class InvestmentRule {
  final int id;
  final String platformName;
  final int assetClassId;
  final String keywords;
  final AssetClass? assetClass;

  InvestmentRule({
    required this.id,
    required this.platformName,
    required this.assetClassId,
    required this.keywords,
    this.assetClass,
  });

  factory InvestmentRule.fromJson(Map<String, dynamic> json) {
    return InvestmentRule(
      id: json['id'],
      platformName: json['platform_name'] ?? '',
      assetClassId: json['asset_class_id'] ?? 0,
      keywords: json['keywords'] ?? '',
      assetClass: json['asset_class'] != null ? AssetClass.fromJson(json['asset_class']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'platform_name': platformName,
      'asset_class_id': assetClassId,
      'keywords': keywords,
    };
    if (assetClass != null) {
      data['asset_class'] = assetClass!.toJson();
    }
    return data;
  }
}
