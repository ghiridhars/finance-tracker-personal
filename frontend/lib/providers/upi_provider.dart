/// UPI ID state management provider.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/upi_models.dart';
import '../services/api/upi_api.dart';

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class UpiState {
  final List<UpiId> upiIds;
  final bool isLoading;
  final String? error;

  const UpiState({
    this.upiIds = const [],
    this.isLoading = false,
    this.error,
  });

  List<UpiId> get ownUpiIds => upiIds.where((u) => u.isOwn).toList();
  List<UpiId> get thirdPartyUpiIds => upiIds.where((u) => !u.isOwn).toList();

  List<UpiId> forAccount(String accountIdentifier) =>
      upiIds.where((u) => u.accountIdentifier == accountIdentifier).toList();

  UpiState copyWith({
    List<UpiId>? upiIds,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return UpiState(
      upiIds: upiIds ?? this.upiIds,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────

class UpiNotifier extends Notifier<UpiState> {
  @override
  UpiState build() {
    // Auto-load on first access
    Future.microtask(() => loadUpiIds());
    return const UpiState(isLoading: true);
  }

  /// Load all UPI IDs from the backend.
  Future<void> loadUpiIds() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final upiIds = await UpiApi.getUpiIds();
      state = state.copyWith(upiIds: upiIds, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Add a new UPI ID mapping.
  Future<bool> addUpiId({
    required String upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool isOwn = false,
  }) async {
    try {
      await UpiApi.createUpiId(
        upiHandle: upiHandle,
        label: label,
        accountType: accountType,
        accountIdentifier: accountIdentifier,
        categoryId: categoryId,
        isOwn: isOwn,
      );
      await loadUpiIds();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Update an existing UPI ID mapping.
  Future<bool> updateUpiId(
    int upiId, {
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool? isOwn,
  }) async {
    try {
      await UpiApi.updateUpiId(
        upiId,
        label: label,
        accountType: accountType,
        accountIdentifier: accountIdentifier,
        categoryId: categoryId,
        isOwn: isOwn,
      );
      await loadUpiIds();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Delete a UPI ID mapping.
  Future<bool> deleteUpiId(int upiId) async {
    try {
      await UpiApi.deleteUpiId(upiId);
      state = state.copyWith(
        upiIds: state.upiIds.where((u) => u.id != upiId).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Re-scan all transactions against UPI-based rules.
  Future<UpiRescanResult?> rescan() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await UpiApi.rescanTransactions();
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────

final upiProvider = NotifierProvider<UpiNotifier, UpiState>(UpiNotifier.new);
