import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/upi_models.dart';
import '../services/api_service.dart';

enum UpiFilter { all, own, thirdParty }

class UpiDirectoryState {
  final List<UpiId> mappings;
  final List<Map<String, dynamic>> unassignedHandles;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final UpiFilter filter;

  const UpiDirectoryState({
    this.mappings = const [],
    this.unassignedHandles = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.filter = UpiFilter.all,
  });

  UpiDirectoryState copyWith({
    List<UpiId>? mappings,
    List<Map<String, dynamic>>? unassignedHandles,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
    UpiFilter? filter,
  }) {
    return UpiDirectoryState(
      mappings: mappings ?? this.mappings,
      unassignedHandles: unassignedHandles ?? this.unassignedHandles,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      filter: filter ?? this.filter,
    );
  }
}

class UpiDirectoryNotifier extends Notifier<UpiDirectoryState> {
  @override
  UpiDirectoryState build() {
    Future.microtask(() => loadData());
    return const UpiDirectoryState(isLoading: true);
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        ApiService.getUpiIds(),
        ApiService.getUnassignedUpiHandles(),
      ]);
      state = state.copyWith(
        mappings: results[0] as List<UpiId>,
        unassignedHandles: results[1] as List<Map<String, dynamic>>,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setFilter(UpiFilter filter) {
    state = state.copyWith(filter: filter);
  }

  Future<bool> createMapping({
    required String upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool isOwn = false,
  }) async {
    try {
      await ApiService.createUpiId(
        upiHandle: upiHandle,
        label: label,
        accountType: accountType,
        accountIdentifier: accountIdentifier,
        categoryId: categoryId,
        isOwn: isOwn,
      );
      await loadData();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateMapping(
    int upiId, {
    String? upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool? isOwn,
  }) async {
    try {
      await ApiService.updateUpiId(
        upiId,
        upiHandle: upiHandle,
        label: label,
        accountType: accountType,
        accountIdentifier: accountIdentifier,
        categoryId: categoryId,
        isOwn: isOwn,
      );
      await loadData();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> deleteMapping(int upiId) async {
    try {
      await ApiService.deleteUpiId(upiId);
      await loadData();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<UpiRescanResult?> rescan() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await ApiService.rescanUpiTransactions();
      await loadData(); // Reload after rescan
      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }
}

final upiDirectoryProvider =
    NotifierProvider<UpiDirectoryNotifier, UpiDirectoryState>(
      UpiDirectoryNotifier.new,
    );
