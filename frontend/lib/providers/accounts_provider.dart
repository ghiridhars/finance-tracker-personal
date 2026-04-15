/// Accounts & Statement Management provider (Phase 4).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account_models.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class AccountsState {
  final List<Account> accounts;
  final List<SavingsStatementSummary> savingsStatements;
  final List<CreditCardStatementSummary> ccStatements;
  final int savingsTotal;
  final int ccTotal;
  final bool isLoading;
  final String? error;
  final String? selectedAccountId; // filter by account identifier
  final String? selectedAccountType; // SAVINGS | CREDIT_CARD

  const AccountsState({
    this.accounts = const [],
    this.savingsStatements = const [],
    this.ccStatements = const [],
    this.savingsTotal = 0,
    this.ccTotal = 0,
    this.isLoading = false,
    this.error,
    this.selectedAccountId,
    this.selectedAccountType,
  });

  AccountsState copyWith({
    List<Account>? accounts,
    List<SavingsStatementSummary>? savingsStatements,
    List<CreditCardStatementSummary>? ccStatements,
    int? savingsTotal,
    int? ccTotal,
    bool? isLoading,
    String? error,
    String? selectedAccountId,
    String? selectedAccountType,
    bool clearError = false,
    bool clearSelection = false,
  }) {
    return AccountsState(
      accounts: accounts ?? this.accounts,
      savingsStatements: savingsStatements ?? this.savingsStatements,
      ccStatements: ccStatements ?? this.ccStatements,
      savingsTotal: savingsTotal ?? this.savingsTotal,
      ccTotal: ccTotal ?? this.ccTotal,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      selectedAccountId:
          clearSelection ? null : (selectedAccountId ?? this.selectedAccountId),
      selectedAccountType: clearSelection
          ? null
          : (selectedAccountType ?? this.selectedAccountType),
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

  /// Select an account (triggers the UI to show its transactions)
  void selectAccount(Account account) {
    state = state.copyWith(
      selectedAccountId: account.identifier,
      selectedAccountType: account.type,
      clearError: true,
    );
  }

  /// Clear account selection (go back to accounts list).
  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  /// Delete a savings statement and refresh.
  Future<bool> deleteSavingsStatement(int statementId) async {
    try {
      await ApiService.deleteSavingsStatement(statementId);
      state = state.copyWith(
        savingsStatements: state.savingsStatements
            .where((s) => s.id != statementId)
            .toList(),
        savingsTotal: state.savingsTotal - 1,
      );
      // Refresh accounts to update counts
      unawaited(loadAccounts());
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Delete a credit card statement and refresh.
  Future<bool> deleteCreditCardStatement(int statementId) async {
    try {
      await ApiService.deleteCreditCardStatement(statementId);
      state = state.copyWith(
        ccStatements:
            state.ccStatements.where((s) => s.id != statementId).toList(),
        ccTotal: state.ccTotal - 1,
      );
      unawaited(loadAccounts());
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────

final accountsProvider =
    NotifierProvider<AccountsNotifier, AccountsState>(AccountsNotifier.new);
