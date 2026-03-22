/// API service facade — backward-compatible wrapper.
///
/// This file delegates all calls to domain-specific API modules in api/.
/// Existing imports of 'api_service.dart' continue to work without changes.
/// New code should import from api/ directly.
library;

// Re-export all domain API modules for barrel-file compatibility
export 'api/api_client.dart';
export 'api/transaction_api.dart';
export 'api/upload_api.dart';
export 'api/analytics_api.dart';
export 'api/account_api.dart';
export 'api/budget_api.dart';
export 'api/export_api.dart';
export 'api/transfers_api.dart';
export 'api/upi_api.dart';

import 'api/api_client.dart';
import 'api/transaction_api.dart';
import 'api/upload_api.dart';
import 'api/analytics_api.dart';
import 'api/account_api.dart';
import 'api/budget_api.dart';
import 'api/export_api.dart';
import 'api/transfers_api.dart';
import 'api/upi_api.dart';

import '../models/savings_models.dart';
import '../models/credit_card_models.dart';
import '../models/category_models.dart';
import '../models/unified_transaction_models.dart';
import '../models/analytics_models.dart';
import '../models/account_models.dart';
import '../models/budget_models.dart';
import '../models/upi_models.dart';

/// Backward-compatible facade. All methods delegate to domain-specific API classes.
/// New code should use TransactionApi, UploadApi, AnalyticsApi, etc. directly.
class ApiService {
  // ── Base URL & Auth ───────────────────────────────────────

  static String get baseUrl => ApiClient.baseUrl;
  static void setBaseUrl(String url) => ApiClient.setBaseUrl(url);
  static void setAuthToken(String? token) => ApiClient.setAuthToken(token);

  // ── Health ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> healthCheck() => ExportApi.healthCheck();

  // ── Legacy transaction endpoints ──────────────────────────

  static Future<List<SavingsTransaction>> getSavingsTransactions({
    String? from, String? to,
  }) => TransactionApi.getSavingsTransactions(from: from, to: to);

  static Future<List<CreditCardTransaction>> getCreditCardTransactions({
    String? from, String? to,
  }) => TransactionApi.getCreditCardTransactions(from: from, to: to);

  // ── V2 Upload ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadStatementV2({
    required List<int> fileBytes, required String fileName,
    required String bank, required String statementType, bool save = true,
  }) => UploadApi.uploadStatementV2(
    fileBytes: fileBytes, fileName: fileName,
    bank: bank, statementType: statementType, save: save,
  );

  static Future<Map<String, dynamic>> uploadCsvStatementV2({
    required List<int> fileBytes, required String fileName,
    required String bank, required String statementType, bool save = true,
  }) => UploadApi.uploadCsvStatementV2(
    fileBytes: fileBytes, fileName: fileName,
    bank: bank, statementType: statementType, save: save,
  );

  // ── V2 Categories ─────────────────────────────────────────

  static Future<List<Category>> getCategories() => ExportApi.getCategories();
  static Future<Category> createCategory({
    required String name, String? icon, String? color,
    List<String> keywords = const [],
  }) => ExportApi.createCategory(name: name, icon: icon, color: color, keywords: keywords);
  static Future<Category> addCategoryKeywords(int categoryId, List<String> keywords) =>
      ExportApi.addCategoryKeywords(categoryId, keywords);
  static Future<void> deleteCategory(int categoryId) => ExportApi.deleteCategory(categoryId);

  // ── V2 Transactions ───────────────────────────────────────

  static Future<List<UnifiedTransaction>> getUnifiedTransactions({
    String? from, String? to, int? categoryId, String? bank,
    String? accountIdentifier, String? sourceType, bool? isTransfer, String? type,
    String? search, double? minAmount, double? maxAmount,
    int limit = 100, int offset = 0,
  }) => TransactionApi.getUnifiedTransactions(
    from: from, to: to, categoryId: categoryId, bank: bank,
    accountIdentifier: accountIdentifier, sourceType: sourceType, isTransfer: isTransfer, type: type,
    search: search, minAmount: minAmount, maxAmount: maxAmount,
    limit: limit, offset: offset,
  );

  static Future<UnifiedTransaction> updateTransaction(
    int transactionId, {int? categoryId, String? merchantName, String? notes, List<int>? tagIds,}
  ) => TransactionApi.updateTransaction(
    transactionId, categoryId: categoryId, merchantName: merchantName, notes: notes, tagIds: tagIds,
  );

  static Future<int> recategorizeAll() => TransactionApi.recategorizeAll();
  static Future<void> deleteTransaction(int transactionId) =>
      TransactionApi.deleteTransaction(transactionId);

  // ── V2 Analytics ──────────────────────────────────────────

  static Future<DashboardSummary> getDashboardSummary({String? from, String? to}) =>
      AnalyticsApi.getDashboardSummary(from: from, to: to);
  static Future<List<CategorySpending>> getSpendingByCategory({String? from, String? to}) =>
      AnalyticsApi.getSpendingByCategory(from: from, to: to);
  static Future<List<SpendingTrend>> getSpendingTrends({
    String? from, String? to, String granularity = 'daily',
  }) => AnalyticsApi.getSpendingTrends(from: from, to: to, granularity: granularity);
  static Future<List<IncomeVsExpense>> getIncomeVsExpense({String? from, String? to}) =>
      AnalyticsApi.getIncomeVsExpense(from: from, to: to);
  static Future<MonthOverMonth> getMonthOverMonth({String? month}) =>
      AnalyticsApi.getMonthOverMonth(month: month);
  static Future<List<MerchantSpending>> getTopMerchants({
    String? from, String? to, int limit = 15,
  }) => AnalyticsApi.getTopMerchants(from: from, to: to, limit: limit);
  static Future<List<SpendingTrend>> getDailySpending({
    required int year, required int month,
  }) => AnalyticsApi.getDailySpending(year: year, month: month);

  // ── Accounts ──────────────────────────────────────────────

  static Future<List<Account>> getAccounts() => AccountApi.getAccounts();
  static Future<PaginatedResponse<SavingsStatementSummary>> getSavingsStatements({
    String? accountNumber, int limit = 50, int offset = 0,
  }) => AccountApi.getSavingsStatements(accountNumber: accountNumber, limit: limit, offset: offset);
  static Future<PaginatedResponse<CreditCardStatementSummary>> getCreditCardStatements({
    String? cardNumber, int limit = 50, int offset = 0,
  }) => AccountApi.getCreditCardStatements(cardNumber: cardNumber, limit: limit, offset: offset);
  static Future<void> deleteSavingsStatement(int statementId) =>
      AccountApi.deleteSavingsStatement(statementId);
  static Future<void> deleteCreditCardStatement(int statementId) =>
      AccountApi.deleteCreditCardStatement(statementId);
  static Future<void> renameAccount({
    required String accountType, required String identifier, required String name,
  }) => AccountApi.renameAccount(accountType: accountType, identifier: identifier, name: name);

  // ── Budgets ───────────────────────────────────────────────

  static Future<List<BudgetProgress>> getBudgetProgress({int? year, int? month}) =>
      BudgetApi.getBudgetProgress(year: year, month: month);
  static Future<BudgetSummary> getBudgetSummary({int? year, int? month}) =>
      BudgetApi.getBudgetSummary(year: year, month: month);
  static Future<Budget> createBudget({
    required int categoryId, required int year, required int month,
    required double amount, bool rollover = false, String? notes,
  }) => BudgetApi.createBudget(
    categoryId: categoryId, year: year, month: month,
    amount: amount, rollover: rollover, notes: notes,
  );
  static Future<List<Budget>> copyBudgets({
    required int fromYear, required int fromMonth,
    required int toYear, required int toMonth,
  }) => BudgetApi.copyBudgets(
    fromYear: fromYear, fromMonth: fromMonth, toYear: toYear, toMonth: toMonth,
  );
  static Future<Budget> updateBudget(int budgetId, {
    double? amount, bool? rollover, String? notes,
  }) => BudgetApi.updateBudget(budgetId, amount: amount, rollover: rollover, notes: notes);
  static Future<void> deleteBudget(int budgetId) => BudgetApi.deleteBudget(budgetId);

  // ── Goals ─────────────────────────────────────────────────

  static Future<List<SavingsGoal>> getGoals({bool includeCompleted = false}) =>
      BudgetApi.getGoals(includeCompleted: includeCompleted);
  static Future<SavingsGoal> createGoal({
    required String name, required double targetAmount,
    double currentAmount = 0, String? deadline, String? icon, String? color, String? notes,
  }) => BudgetApi.createGoal(
    name: name, targetAmount: targetAmount, currentAmount: currentAmount,
    deadline: deadline, icon: icon, color: color, notes: notes,
  );
  static Future<SavingsGoal> contributeToGoal(int goalId, double amount) =>
      BudgetApi.contributeToGoal(goalId, amount);
  static Future<void> deleteGoal(int goalId) => BudgetApi.deleteGoal(goalId);

  // ── Reminders ─────────────────────────────────────────────

  static Future<List<BillReminder>> getReminders({
    bool includePaid = false, int? upcomingDays,
  }) => BudgetApi.getReminders(includePaid: includePaid, upcomingDays: upcomingDays);
  static Future<BillReminder> createReminder({
    required String name, double? amount, int? categoryId,
    bool isRecurring = true, String? frequency, int? dayOfMonth,
    String? nextDueDate, String? notes,
  }) => BudgetApi.createReminder(
    name: name, amount: amount, categoryId: categoryId,
    isRecurring: isRecurring, frequency: frequency, dayOfMonth: dayOfMonth,
    nextDueDate: nextDueDate, notes: notes,
  );
  static Future<BillReminder> markReminderPaid(int reminderId) =>
      BudgetApi.markReminderPaid(reminderId);
  static Future<void> deleteReminder(int reminderId) => BudgetApi.deleteReminder(reminderId);
  static Future<List<BillReminder>> autoDetectReminders() => BudgetApi.autoDetectReminders();

  // ── Recurring ─────────────────────────────────────────────

  static Future<List<RecurringTransaction>> getRecurring({bool activeOnly = true}) =>
      BudgetApi.getRecurring(activeOnly: activeOnly);
  static Future<List<RecurringTransaction>> detectRecurring() => BudgetApi.detectRecurring();
  static Future<RecurringTransaction> toggleSubscription(int recurringId, bool isSubscription) =>
      BudgetApi.toggleSubscription(recurringId, isSubscription);
  static Future<void> deleteRecurring(int recurringId) => BudgetApi.deleteRecurring(recurringId);

  // ── Export & Data Management ──────────────────────────────

  static String getExportUrl({
    String format = 'csv', String? from, String? to,
    int? categoryId, String? bank, String? sourceType, String? type, String? search,
  }) => ExportApi.getExportUrl(
    format: format, from: from, to: to, categoryId: categoryId,
    bank: bank, sourceType: sourceType, type: type, search: search,
  );
  static Future<Map<String, dynamic>> clearAllData() => ExportApi.clearAllData();

  // ── Google Drive Sync ─────────────────────────────────────

  static Future<Map<String, dynamic>> getGDriveStatus() => ExportApi.getGDriveStatus();
  static Future<Map<String, dynamic>> getGDriveFiles() => ExportApi.getGDriveFiles();
  static Future<Map<String, dynamic>> syncFromGDrive({
    String? bank, String? statementType, List<String>? fileIds, bool force = false,
  }) => ExportApi.syncFromGDrive(bank: bank, statementType: statementType, fileIds: fileIds, force: force);
  static Future<Map<String, dynamic>> resetGDriveSync({List<String>? fileIds}) =>
      ExportApi.resetGDriveSync(fileIds: fileIds);

  // ── Transfers ─────────────────────────────────────────────

  static Future<TransferDetectResult> detectTransfers() =>
      TransfersApi.detectTransfers();
  static Future<TransferPair> linkTransfer({
    required int transactionId1,
    required int transactionId2,
    String transferType = 'INTERNAL_TRANSFER',
  }) => TransfersApi.linkTransfer(
    transactionId1: transactionId1,
    transactionId2: transactionId2,
    transferType: transferType,
  );
  static Future<void> unlinkTransfer(String transferGroupId) =>
      TransfersApi.unlinkTransfer(transferGroupId);
  static Future<List<TransferPair>> listTransfers() =>
      TransfersApi.listTransfers();
  static Future<TransferPair> updateTransferType(
    String transferGroupId,
    String transferType,
  ) => TransfersApi.updateTransferType(transferGroupId, transferType);

  // ── UPI IDs ───────────────────────────────────────────────

  static Future<List<UpiId>> getUpiIds({bool? isOwn, String? accountIdentifier}) =>
      UpiApi.getUpiIds(isOwn: isOwn, accountIdentifier: accountIdentifier);
  static Future<UpiId> createUpiId({
    required String upiHandle, String? label,
    String? accountType, String? accountIdentifier,
    int? categoryId, bool isOwn = false,
  }) => UpiApi.createUpiId(
    upiHandle: upiHandle, label: label,
    accountType: accountType, accountIdentifier: accountIdentifier,
    categoryId: categoryId, isOwn: isOwn,
  );
  static Future<UpiId> updateUpiId(int upiId, {
    String? label, String? accountType, String? accountIdentifier,
    int? categoryId, bool? isOwn,
  }) => UpiApi.updateUpiId(upiId,
    label: label, accountType: accountType,
    accountIdentifier: accountIdentifier,
    categoryId: categoryId, isOwn: isOwn,
  );
  static Future<void> deleteUpiId(int upiId) => UpiApi.deleteUpiId(upiId);
  static Future<UpiRescanResult> rescanUpiTransactions() =>
      UpiApi.rescanTransactions();
}
