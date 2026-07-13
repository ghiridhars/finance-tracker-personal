/// StatementsNotifier — manages upload state and parsed results.
/// After a successful upload, triggers auto-refresh of transaction lists.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'transactions_provider.dart';

/// Upload state.
class UploadState {
  final bool isUploading;
  final String? resultMessage;
  final bool isError;
  final bool backendReachable;

  const UploadState({
    this.isUploading = false,
    this.resultMessage,
    this.isError = false,
    this.backendReachable = true,
  });

  UploadState copyWith({
    bool? isUploading,
    String? resultMessage,
    bool? isError,
    bool? backendReachable,
    bool clearResult = false,
  }) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      resultMessage: clearResult ? null : (resultMessage ?? this.resultMessage),
      isError: isError ?? this.isError,
      backendReachable: backendReachable ?? this.backendReachable,
    );
  }
}

/// Notifier managing statement uploads.
class StatementsNotifier extends Notifier<UploadState> {
  @override
  UploadState build() {
    return const UploadState();
  }

  /// Check backend connectivity.
  Future<void> checkBackend() async {
    try {
      await ApiService.healthCheck();
      state = state.copyWith(backendReachable: true);
    } catch (_) {
      state = state.copyWith(
        backendReachable: false,
        resultMessage:
            'Cannot reach backend at ${ApiService.baseUrl}\n'
            'Make sure the Python backend is running:\n'
            '  cd backend && uvicorn app.main:app --port 8080',
        isError: true,
      );
    }
  }

  void clearResult() {
    state = state.copyWith(clearResult: true, isError: false);
  }

  /// Upload via the unified v2 endpoint (any bank, any type, PDF or CSV).
  Future<void> uploadV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
    bool isCsv = false,
    String? password,
  }) async {
    state = state.copyWith(isUploading: true, clearResult: true, isError: false);

    try {
      // Connectivity check
      try {
        await ApiService.healthCheck();
      } catch (_) {
        throw Exception(
          'Cannot connect to backend at ${ApiService.baseUrl}. '
          'Ensure the Python backend is running on port 8080.',
        );
      }

      final Map<String, dynamic> response;
      if (isCsv) {
        response = await ApiService.uploadCsvStatementV2(
          fileBytes: fileBytes,
          fileName: fileName,
          bank: bank,
          statementType: statementType,
          save: save,
        );
      } else {
        response = await ApiService.uploadStatementV2(
          fileBytes: fileBytes,
          fileName: fileName,
          bank: bank,
          statementType: statementType,
          save: save,
          password: password,
        );
      }

      state = UploadState(
        isUploading: false,
        isError: false,
        backendReachable: true,
        resultMessage: _formatV2Result(response),
      );

      // Auto-refresh transaction lists
      if (statementType == 'CREDIT_CARD') {
        ref.read(creditCardTransactionsProvider.notifier).loadTransactions();
      } else {
        ref.read(savingsTransactionsProvider.notifier).loadTransactions();
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('XMLHttpRequest error')) {
        errorMsg =
            'Network error — could not reach the backend.\n\n'
            'Common causes:\n'
            '  1. Backend not running (start with: cd backend && uvicorn app.main:app --port 8080)\n'
            '  2. CORS issue\n'
            '  3. Backend crashed during parsing — check terminal';
      }
      state = UploadState(
        isUploading: false,
        isError: true,
        resultMessage: errorMsg,
      );
    }
  }

  String _formatV2Result(Map<String, dynamic> response) {
    final bank = response['bank'] ?? '?';
    final stType = response['statement_type'] ?? '?';
    final parser = response['parser_used'] ?? '?';
    final stmt = response['statement'] as Map<String, dynamic>?;

    final lines = <String>[
      '✓ Statement Parsed Successfully',
      '',
      'Bank:            $bank',
      'Type:            $stType',
      'Parser Used:     $parser',
    ];

    if (stmt != null) {
      // Credit card specific
      if (stmt.containsKey('card_number')) {
        lines.addAll([
          'Card:            ${stmt['card_number'] ?? 'N/A'}',
          'Statement Date:  ${stmt['statement_date'] ?? 'N/A'}',
          'Total Dues:      ₹${stmt['total_dues'] ?? 'N/A'}',
        ]);
      }
      // Savings specific
      if (stmt.containsKey('account_number')) {
        lines.addAll([
          'Account:         ${stmt['account_number'] ?? 'N/A'}',
          'Period:          ${stmt['from_date'] ?? '?'} to ${stmt['to_date'] ?? '?'}',
          'Opening Bal:     ₹${stmt['opening_balance'] ?? 'N/A'}',
          'Closing Bal:     ₹${stmt['closing_balance'] ?? 'N/A'}',
        ]);
      }

      final transactions = stmt['transactions'] as List<dynamic>?;
      lines.add('');
      lines.add('Transactions:    ${transactions?.length ?? 0}');
    }

    return lines.join('\n');
  }
}

/// Provider for upload state.
final statementsProvider =
    NotifierProvider<StatementsNotifier, UploadState>(StatementsNotifier.new);
