import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/investment_rule.dart';
import '../services/api_service.dart';

final investmentRuleProvider =
    AsyncNotifierProvider<InvestmentRuleNotifier, List<InvestmentRule>>(
  InvestmentRuleNotifier.new,
);

class InvestmentRuleNotifier extends AsyncNotifier<List<InvestmentRule>> {
  @override
  Future<List<InvestmentRule>> build() async {
    return await ApiService.getInvestmentRules();
  }

  Future<void> addRule(String platformName, int assetClassId, String keywords) async {
    try {
      final newRule = await ApiService.createInvestmentRule(platformName, assetClassId, keywords);
      if (state.hasValue) {
        state = AsyncValue.data([...state.value!, newRule]);
      } else {
        ref.invalidateSelf();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateRule(int id, String platformName, int assetClassId, String keywords) async {
    try {
      final updated = await ApiService.updateInvestmentRule(
        id, 
        platformName: platformName, 
        assetClassId: assetClassId, 
        keywords: keywords,
      );
      if (state.hasValue) {
        state = AsyncValue.data([
          for (final r in state.value!)
            if (r.id == id) updated else r
        ]);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteRule(int id) async {
    try {
      await ApiService.deleteInvestmentRule(id);
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.where((r) => r.id != id).toList());
      }
    } catch (e) {
      rethrow;
    }
  }
}
