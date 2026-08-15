/// API service facade — backward-compatible wrapper.
///
/// This file delegates all calls to domain-specific API modules in api/.
/// Existing imports of 'api_service.dart' continue to work without changes.
/// New code should import from api/ directly.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import "api/investment_rule_api.dart";
import "../models/investment_rule.dart";

// Re-export all domain API modules for barrel-file compatibility
export 'api/api_client.dart';
export 'api/transaction_api.dart';
export 'api/upload_api.dart';
export 'api/analytics_api.dart';
export 'api/account_api.dart';
export 'api/export_api.dart';
export 'api/upi_api.dart';
export 'api/admin_api.dart';
export 'api/local_sync_api.dart';
export 'api/asset_class_api.dart';

import 'api/api_client.dart';
import 'api/transaction_api.dart';
import 'api/upload_api.dart';
import 'api/analytics_api.dart';
import 'api/account_api.dart';
import 'api/export_api.dart';
import 'api/upi_api.dart';
import 'api/local_sync_api.dart';
import 'api/asset_class_api.dart';

import '../models/category_models.dart';
import '../models/unified_transaction_models.dart';
import '../models/analytics_models.dart';
import '../models/account_models.dart';
import '../models/upi_models.dart';
import '../models/asset_class.dart';

/// Backward-compatible facade. All methods delegate to domain-specific API classes.
/// New code should use TransactionApi, UploadApi, AnalyticsApi, etc. directly.
class ApiService {
  // ── Base URL & Auth ───────────────────────────────────────

  static String get baseUrl => ApiClient.baseUrl;
  static void setBaseUrl(String url) => ApiClient.setBaseUrl(url);
  static void setAuthToken(String? token) => ApiClient.setAuthToken(token);

  // ── Health ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> healthCheck() => ExportApi.healthCheck();

  // ── V2 Upload ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadStatementV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
    String? password,
  }) => UploadApi.uploadStatementV2(
    fileBytes: fileBytes,
    fileName: fileName,
    bank: bank,
    statementType: statementType,
    save: save,
    password: password,
  );

  static Future<Map<String, dynamic>> uploadCsvStatementV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
  }) => UploadApi.uploadCsvStatementV2(
    fileBytes: fileBytes,
    fileName: fileName,
    bank: bank,
    statementType: statementType,
    save: save,
  );

  // ── V2 Categories ─────────────────────────────────────────

  static Future<List<Category>> getCategories() => ExportApi.getCategories();
  static Future<Category> createCategory({
    required String name,
    String? icon,
    String? color,
    List<String> keywords = const [],
  }) => ExportApi.createCategory(
    name: name,
    icon: icon,
    color: color,
    keywords: keywords,
  );
  static Future<void> deleteCategory(int categoryId) =>
      ExportApi.deleteCategory(categoryId);

  // ── V2 Transactions ───────────────────────────────────────

  static Future<List<UnifiedTransaction>> getUnifiedTransactions({
    String? from,
    String? to,
    int? categoryId,
    String? bank,
    int? bankAccountId,
    String? accountIdentifier,
    String? sourceType,
    bool? isTransfer,
    String? type,
    String? reviewStatus,
    String? search,
    double? minAmount,
    double? maxAmount,
    int limit = 100,
    int offset = 0,
  }) => TransactionApi.getUnifiedTransactions(
    from: from,
    to: to,
    categoryId: categoryId,
    bank: bank,
    bankAccountId: bankAccountId,
    accountIdentifier: accountIdentifier,
    sourceType: sourceType,
    isTransfer: isTransfer,
    type: type,
    reviewStatus: reviewStatus,
    search: search,
    minAmount: minAmount,
    maxAmount: maxAmount,
    limit: limit,
    offset: offset,
  );

  static Future<UnifiedTransaction> updateTransaction(
    int transactionId, {
    int? categoryId,
    String? merchantName,
    String? notes,
    List<int>? tagIds,
    int? fromAccountId,
    int? toAccountId,
  }) => TransactionApi.updateTransaction(
    transactionId,
    categoryId: categoryId,
    merchantName: merchantName,
    notes: notes,
    tagIds: tagIds,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
  );

  static Future<int> recategorizeAll() => TransactionApi.recategorizeAll();
  static Future<void> deleteTransaction(int transactionId) =>
      TransactionApi.deleteTransaction(transactionId);
  static Future<BulkUpdateResult> bulkUpdateTransactions(
    List<Map<String, dynamic>> updates,
  ) => TransactionApi.bulkUpdateTransactions(updates);
  static Future<int> countTransactions({String? reviewStatus}) =>
      TransactionApi.countTransactions(reviewStatus: reviewStatus);

  // ── V2 Analytics ──────────────────────────────────────────

  static Future<DashboardSummary> getDashboardSummary({
    String? from,
    String? to,
  }) => AnalyticsApi.getDashboardSummary(from: from, to: to);
  static Future<InvestmentAnalytics> getInvestmentAnalytics() =>
      AnalyticsApi.getInvestmentAnalytics();
  static Future<List<CategorySpending>> getSpendingByCategory({
    String? from,
    String? to,
  }) => AnalyticsApi.getSpendingByCategory(from: from, to: to);
  static Future<List<SpendingTrend>> getSpendingTrends({
    String? from,
    String? to,
    String granularity = 'daily',
  }) => AnalyticsApi.getSpendingTrends(
    from: from,
    to: to,
    granularity: granularity,
  );
  static Future<List<IncomeVsExpense>> getIncomeVsExpense({
    String? from,
    String? to,
  }) => AnalyticsApi.getIncomeVsExpense(from: from, to: to);
  static Future<MonthOverMonth> getMonthOverMonth({String? month}) =>
      AnalyticsApi.getMonthOverMonth(month: month);
  static Future<List<MerchantSpending>> getTopMerchants({
    String? from,
    String? to,
    int limit = 15,
  }) => AnalyticsApi.getTopMerchants(from: from, to: to, limit: limit);
  static Future<List<SpendingTrend>> getDailySpending({
    required int year,
    required int month,
  }) => AnalyticsApi.getDailySpending(year: year, month: month);
  static Future<List<UnifiedTransaction>> getUnmappedInvestments() =>
      AnalyticsApi.getUnmappedInvestments();
  static Future<Map<String, dynamic>> getNetWorth() =>
      AnalyticsApi.getNetWorth();

  // ── Accounts ──────────────────────────────────────────────

  static Future<List<Account>> getAccounts() => AccountApi.getAccounts();


  static Future<Map<String, dynamic>> createAccount({
    required String bankName,
    required String accountType,
    required String name,
    String? accountNumber,
    String? holderName,
    String? ifscCode,
    String? accountSubtype,
    String? notes,
    double? loanPrincipal,
    double? loanInterestRate,
    double? loanEmiAmount,
    String? loanStartDate,
    String? loanEndDate,
    double? creditLimit,
    int? billingCycleDay,
    double? investedAmount,
    double? currentValue,
  }) => AccountApi.createAccount(
    bankName: bankName,
    accountType: accountType,
    name: name,
    accountNumber: accountNumber,
    holderName: holderName,
    ifscCode: ifscCode,
    accountSubtype: accountSubtype,
    notes: notes,
    loanPrincipal: loanPrincipal,
    loanInterestRate: loanInterestRate,
    loanEmiAmount: loanEmiAmount,
    loanStartDate: loanStartDate,
    loanEndDate: loanEndDate,
    creditLimit: creditLimit,
    billingCycleDay: billingCycleDay,
    investedAmount: investedAmount,
    currentValue: currentValue,
  );

  static Future<Map<String, dynamic>> updateAccount(
    int accountId,
    Map<String, dynamic> updates,
  ) => AccountApi.updateAccount(accountId, updates);

  static Future<void> mergeAccounts(int sourceId, int targetId) =>
      AccountApi.mergeAccounts(sourceId, targetId);

  static Future<void> deleteAccount(int accountId) =>
      AccountApi.deleteAccount(accountId);

  static Future<Map<String, dynamic>> getAccountSummary(int accountId) =>
      AccountApi.getAccountSummary(accountId);

  // ── Export & Data Management ──────────────────────────────

  static String getExportUrl({
    String format = 'csv',
    String? from,
    String? to,
    int? categoryId,
    String? bank,
    String? sourceType,
    String? type,
    String? search,
  }) => ExportApi.getExportUrl(
    format: format,
    from: from,
    to: to,
    categoryId: categoryId,
    bank: bank,
    sourceType: sourceType,
    type: type,
    search: search,
  );
  static Future<Map<String, dynamic>> clearAllData() =>
      ExportApi.clearAllData();

  // ── Google Drive Sync ─────────────────────────────────────

  static Future<Map<String, dynamic>> getGDriveStatus() =>
      ExportApi.getGDriveStatus();
  static Future<Map<String, dynamic>> getGDriveFiles() =>
      ExportApi.getGDriveFiles();
  static Future<Map<String, dynamic>> syncFromGDrive({
    String? bank,
    String? statementType,
    List<String>? fileIds,
    bool force = false,
  }) => ExportApi.syncFromGDrive(
    bank: bank,
    statementType: statementType,
    fileIds: fileIds,
    force: force,
  );
  static Future<Map<String, dynamic>> resetGDriveSync({
    List<String>? fileIds,
  }) => ExportApi.resetGDriveSync(fileIds: fileIds);

  // ── UPI IDs ───────────────────────────────────────────────

  static Future<List<UpiId>> getUpiIds({
    bool? isOwn,
    String? accountIdentifier,
  }) => UpiApi.getUpiIds(isOwn: isOwn, accountIdentifier: accountIdentifier);
  static Future<UpiId> createUpiId({
    required String upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool isOwn = false,
  }) => UpiApi.createUpiId(
    upiHandle: upiHandle,
    label: label,
    accountType: accountType,
    accountIdentifier: accountIdentifier,
    categoryId: categoryId,
    isOwn: isOwn,
  );
  static Future<UpiId> updateUpiId(
    int upiId, {
    String? upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool? isOwn,
  }) => UpiApi.updateUpiId(
    upiId,
    upiHandle: upiHandle,
    label: label,
    accountType: accountType,
    accountIdentifier: accountIdentifier,
    categoryId: categoryId,
    isOwn: isOwn,
  );
  static Future<void> deleteUpiId(int upiId) => UpiApi.deleteUpiId(upiId);
  static Future<UpiRescanResult> rescanUpiTransactions() =>
      UpiApi.rescanTransactions();
  static Future<List<Map<String, dynamic>>> getUnassignedUpiHandles({
    int limit = 100,
  }) => UpiApi.getUnassignedUpiHandles(limit: limit);

  // ── Local Directory Sync ──────────────────────────────────

  static Future<Map<String, dynamic>> getLocalSyncStatus() =>
      LocalSyncApi.getStatus();
  static Future<Map<String, dynamic>> configureLocalSyncPath(String path) =>
      LocalSyncApi.configurePath(path);
  static Future<Map<String, dynamic>> getLocalSyncFiles({String? path}) =>
      LocalSyncApi.listFiles(path: path);
  static Future<Map<String, dynamic>> startLocalScan({
    required List<Map<String, String>> files,
    bool force = false,
  }) => LocalSyncApi.startScan(files: files, force: force);
  static Future<Map<String, dynamic>> getLocalScanStatus(String jobId) =>
      LocalSyncApi.getScanStatus(jobId);
  static Future<Map<String, dynamic>> resetLocalSyncState({
    List<String>? filepaths,
  }) => LocalSyncApi.resetState(filepaths: filepaths);

  // ── Asset Classes ─────────────────────────────────────────

  static Future<List<AssetClass>> getAssetClasses() =>
      AssetClassApi.getAssetClasses();
  static Future<AssetClass> createAssetClass(
    String name,
    String colorHex,
    String iconName,
  ) => AssetClassApi.createAssetClass(name, colorHex, iconName);
  static Future<AssetClass> updateAssetClass(
    int id, {
    String? name,
    String? colorHex,
    String? iconName,
  }) => AssetClassApi.updateAssetClass(
    id,
    name: name,
    colorHex: colorHex,
    iconName: iconName,
  );
  static Future<void> deleteAssetClass(int id) =>
      AssetClassApi.deleteAssetClass(id);

  // ── Investment Rules ──────────────────────────────────────

  static Future<List<InvestmentRule>> getInvestmentRules() =>
      InvestmentRuleApi.getInvestmentRules();

  static Future<InvestmentRule> createInvestmentRule(
    String platformName,
    int assetClassId,
    String keywords,
  ) => InvestmentRuleApi.createInvestmentRule(
    platformName,
    assetClassId,
    keywords,
  );

  static Future<InvestmentRule> updateInvestmentRule(
    int id, {
    String? platformName,
    int? assetClassId,
    String? keywords,
  }) => InvestmentRuleApi.updateInvestmentRule(
    id,
    platformName: platformName,
    assetClassId: assetClassId,
    keywords: keywords,
  );

  static Future<void> deleteInvestmentRule(int id) =>
      InvestmentRuleApi.deleteInvestmentRule(id);

  // ── Classification Rules ──────────────────────────────────

  static Future<void> createClassificationRule({
    required String name,
    String? pattern,
    int? targetCategoryId,
    String? targetMerchant,
  }) async {
    final body = <String, dynamic>{'name': name};
    if (pattern != null) body['pattern'] = pattern;
    if (targetCategoryId != null) body['target_category_id'] = targetCategoryId;
    if (targetMerchant != null) body['target_merchant'] = targetMerchant;

    final response = await http
        .post(
          Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create classification rule: ${response.body}');
    }
  }

  static Future<void> excludeTransaction(int txId) async {
    final response = await http
        .patch(
          Uri.parse('${ApiClient.baseUrl}/api/v2/transactions/$txId'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({'is_excluded': true}),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to exclude transaction: ${response.body}');
    }
  }
}
