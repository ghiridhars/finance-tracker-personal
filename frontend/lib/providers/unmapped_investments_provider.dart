import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unified_transaction_models.dart';
import '../services/api_service.dart';

final unmappedInvestmentsProvider =
    AsyncNotifierProvider<UnmappedInvestmentsNotifier, List<UnifiedTransaction>>(
  UnmappedInvestmentsNotifier.new,
);

class UnmappedInvestmentsNotifier extends AsyncNotifier<List<UnifiedTransaction>> {
  @override
  Future<List<UnifiedTransaction>> build() async {
    return await ApiService.getUnmappedInvestments();
  }

  void removeMappedTransaction(int transactionId) {
    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.where((tx) => tx.id != transactionId).toList()
      );
    }
  }
}
