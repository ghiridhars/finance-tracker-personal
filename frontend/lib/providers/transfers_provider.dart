/// Transfers state management — handles transfer detection, linking, and listing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api/transfers_api.dart';

// ── State ───────────────────────────────────────────────

class TransfersState {
  final bool isLoading;
  final String? error;
  final List<TransferPair> pairs;
  final TransferDetectResult? lastDetectResult;

  const TransfersState({
    this.isLoading = false,
    this.error,
    this.pairs = const [],
    this.lastDetectResult,
  });

  TransfersState copyWith({
    bool? isLoading,
    String? error,
    List<TransferPair>? pairs,
    TransferDetectResult? lastDetectResult,
    bool clearError = false,
  }) {
    return TransfersState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      pairs: pairs ?? this.pairs,
      lastDetectResult: lastDetectResult ?? this.lastDetectResult,
    );
  }
}

// ── Notifier ────────────────────────────────────────────

class TransfersNotifier extends Notifier<TransfersState> {
  @override
  TransfersState build() {
    Future.microtask(() => loadAll());
    return const TransfersState(isLoading: true);
  }

  /// Load all linked transfer pairs.
  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final pairs = await TransfersApi.listTransfers();
      state = state.copyWith(isLoading: false, pairs: pairs);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Run auto-detection on all unlinked transactions.
  Future<void> detectTransfers() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await TransfersApi.detectTransfers();
      state = state.copyWith(
        isLoading: false,
        lastDetectResult: result,
      );
      // Refresh the full list after detection
      await loadAll();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Manually link two transactions.
  Future<void> linkTransfer({
    required int transactionId1,
    required int transactionId2,
    String transferType = 'INTERNAL_TRANSFER',
  }) async {
    try {
      await TransfersApi.linkTransfer(
        transactionId1: transactionId1,
        transactionId2: transactionId2,
        transferType: transferType,
      );
      await loadAll();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Unlink a transfer pair.
  Future<void> unlinkTransfer(String transferGroupId) async {
    try {
      await TransfersApi.unlinkTransfer(transferGroupId);
      await loadAll();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Update transfer type for a pair.
  Future<void> updateTransferType(
    String transferGroupId,
    String transferType,
  ) async {
    try {
      await TransfersApi.updateTransferType(transferGroupId, transferType);
      await loadAll();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

// ── Provider ────────────────────────────────────────────

final transfersProvider = NotifierProvider<TransfersNotifier, TransfersState>(
  TransfersNotifier.new,
);
