/// Accounts & Statement Management provider (Phase 4).
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account_models.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class AccountsState {
  final List<Account> accounts;
  final bool isLoading;
  final String? error;

  const AccountsState({
    this.accounts = const [],
    this.isLoading = false,
    this.error,
  });

  AccountsState copyWith({
    List<Account>? accounts,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return AccountsState(
      accounts: accounts ?? this.accounts,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────

class AccountsNotifier extends Notifier<AccountsState> {
  @override
  AccountsState build() {
    return const AccountsState();
  }

  /// Load all linked accounts.
  Future<void> loadAccounts() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final accounts = await ApiService.getAccounts();
      state = state.copyWith(accounts: accounts, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createAccount(Map<String, dynamic> params) async {
    try {
      await ApiService.createAccount(
        bankName: params['bank_name'],
        accountType: params['account_type'],
        name: params['name'],
        accountNumber: params['account_number'],
        holderName: params['holder_name'],
        ifscCode: params['ifsc_code'],
        accountSubtype: params['account_subtype'],
        notes: params['notes'],
        loanPrincipal: params['loan_principal'],
        loanInterestRate: params['loan_interest_rate'],
        loanEmiAmount: params['loan_emi_amount'],
        loanStartDate: params['loan_start_date'],
        loanEndDate: params['loan_end_date'],
        creditLimit: params['credit_limit'],
        billingCycleDay: params['billing_cycle_day'],
        investedAmount: params['invested_amount'],
        currentValue: params['current_value'],
      );
      await loadAccounts();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateAccount(int id, Map<String, dynamic> params) async {
    try {
      await ApiService.updateAccount(id, params);
      await loadAccounts();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> mergeAccounts(int sourceId, int targetId) async {
    try {
      await ApiService.mergeAccounts(sourceId, targetId);
      await loadAccounts();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteAccount(int id) async {
    try {
      await ApiService.deleteAccount(id);
      await loadAccounts();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────

final accountsProvider =
    NotifierProvider<AccountsNotifier, AccountsState>(AccountsNotifier.new);
