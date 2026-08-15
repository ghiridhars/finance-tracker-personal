import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/classification_rule_models.dart';
import '../services/api/classification_rules_api.dart';

final classificationRulesProvider =
    AsyncNotifierProvider<ClassificationRulesNotifier, List<ClassificationRule>>(() {
  return ClassificationRulesNotifier();
});

class ClassificationRulesNotifier extends AsyncNotifier<List<ClassificationRule>> {
  @override
  Future<List<ClassificationRule>> build() async {
    return _loadRules();
  }

  Future<List<ClassificationRule>> _loadRules() async {
    return await ClassificationRulesApi.getRules();
  }

  Future<void> loadRules() async {
    state = const AsyncValue.loading();
    try {
      final rules = await _loadRules();
      state = AsyncValue.data(rules);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<ClassificationRule> addRule(ClassificationRule rule) async {
    try {
      final newRule = await ClassificationRulesApi.createRule(rule);
      if (state.hasValue) {
        state = AsyncValue.data([...state.value!, newRule]);
      }
      return newRule;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateRule(int id, ClassificationRule rule) async {
    try {
      final updatedRule = await ClassificationRulesApi.updateRule(id, rule);
      if (state.hasValue) {
        state = AsyncValue.data([
          for (final r in state.value!)
            if (r.id == id) updatedRule else r
        ]);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteRule(int id) async {
    try {
      await ClassificationRulesApi.deleteRule(id);
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.where((r) => r.id != id).toList());
      }
    } catch (e) {
      rethrow;
    }
  }
}
