/// Provider for Database Manager state.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_models.dart';
import '../services/api/admin_api.dart';

// ── State ───────────────────────────────────────────────────

class AdminState {
  final List<TableInfo> tables;
  final String? selectedTable;
  final TableSchemaModel? schema;
  final List<Map<String, dynamic>> rows;
  final int total;
  final int currentPage;
  final int pageSize;
  final String? searchQuery;
  final String? searchColumn;
  final String? sortColumn;
  final String sortOrder;
  final bool isLoading;
  final String? error;
  final Map<String, List<FKOption>> fkOptionsCache;

  const AdminState({
    this.tables = const [],
    this.selectedTable,
    this.schema,
    this.rows = const [],
    this.total = 0,
    this.currentPage = 0,
    this.pageSize = 50,
    this.searchQuery,
    this.searchColumn,
    this.sortColumn,
    this.sortOrder = 'desc',
    this.isLoading = false,
    this.error,
    this.fkOptionsCache = const {},
  });

  AdminState copyWith({
    List<TableInfo>? tables,
    String? selectedTable,
    TableSchemaModel? schema,
    List<Map<String, dynamic>>? rows,
    int? total,
    int? currentPage,
    int? pageSize,
    String? searchQuery,
    String? searchColumn,
    String? sortColumn,
    String? sortOrder,
    bool? isLoading,
    String? error,
    Map<String, List<FKOption>>? fkOptionsCache,
    bool clearSearch = false,
    bool clearError = false,
    bool clearSchema = false,
  }) =>
      AdminState(
        tables: tables ?? this.tables,
        selectedTable: selectedTable ?? this.selectedTable,
        schema: clearSchema ? null : (schema ?? this.schema),
        rows: rows ?? this.rows,
        total: total ?? this.total,
        currentPage: currentPage ?? this.currentPage,
        pageSize: pageSize ?? this.pageSize,
        searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
        searchColumn: clearSearch ? null : (searchColumn ?? this.searchColumn),
        sortColumn: sortColumn ?? this.sortColumn,
        sortOrder: sortOrder ?? this.sortOrder,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        fkOptionsCache: fkOptionsCache ?? this.fkOptionsCache,
      );
}

// ── Notifier ────────────────────────────────────────────────

class AdminNotifier extends Notifier<AdminState> {
  @override
  AdminState build() => const AdminState();

  Future<void> loadTables() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tables = await AdminApi.getTables();
      state = state.copyWith(tables: tables, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> selectTable(String tableName) async {
    state = state.copyWith(
      selectedTable: tableName,
      currentPage: 0,
      clearSearch: true,
      clearSchema: true,
      rows: [],
      total: 0,
      sortColumn: null,
      sortOrder: 'desc',
      isLoading: true,
      clearError: true,
    );
    try {
      final schema = await AdminApi.getTableSchema(tableName);
      state = state.copyWith(schema: schema);

      // Pre-load FK options for columns that have foreign keys
      for (final col in schema.columns) {
        if (col.foreignKey != null) {
          await loadFKOptions(tableName, col.name);
        }
      }

      await _fetchRows();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadRows({int? page, String? search, String? sort, String? order}) async {
    state = state.copyWith(
      currentPage: page ?? state.currentPage,
      searchQuery: search,
      sortColumn: sort ?? state.sortColumn,
      sortOrder: order ?? state.sortOrder,
      isLoading: true,
      clearError: true,
    );
    await _fetchRows();
  }

  Future<void> setSearch(String? query, {String? column}) async {
    if (query == state.searchQuery && column == state.searchColumn) return;
    state = state.copyWith(searchQuery: query, searchColumn: column, currentPage: 0, isLoading: true, clearError: true);
    await _fetchRows();
  }

  Future<void> setSort(String column) async {
    final newOrder = (state.sortColumn == column && state.sortOrder == 'asc') ? 'desc' : 'asc';
    state = state.copyWith(sortColumn: column, sortOrder: newOrder, currentPage: 0, isLoading: true);
    await _fetchRows();
  }

  Future<void> nextPage() async {
    final maxPage = ((state.total - 1) / state.pageSize).floor();
    if (state.currentPage >= maxPage) return;
    state = state.copyWith(currentPage: state.currentPage + 1, isLoading: true);
    await _fetchRows();
  }

  Future<void> previousPage() async {
    if (state.currentPage <= 0) return;
    state = state.copyWith(currentPage: state.currentPage - 1, isLoading: true);
    await _fetchRows();
  }

  Future<void> goToPage(int page) async {
    if (page == state.currentPage) return;
    state = state.copyWith(currentPage: page, isLoading: true);
    await _fetchRows();
  }

  Future<void> setPageSize(int size) async {
    if (size == state.pageSize) return;
    state = state.copyWith(pageSize: size, currentPage: 0, isLoading: true);
    await _fetchRows();
  }

  Future<void> _fetchRows() async {
    final tableName = state.selectedTable;
    if (tableName == null) return;
    try {
      final response = await AdminApi.getRows(
        tableName,
        limit: state.pageSize,
        offset: state.currentPage * state.pageSize,
        sort: state.sortColumn,
        order: state.sortOrder,
        search: state.searchQuery,
        searchColumn: state.searchColumn,
      );
      state = state.copyWith(
        rows: response.rows,
        total: response.total,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> createRow(Map<String, dynamic> data) async {
    final tableName = state.selectedTable;
    if (tableName == null) return false;
    try {
      await AdminApi.createRow(tableName, data);
      await loadTables(); // refresh row counts
      await _fetchRows();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateRow(int rowId, Map<String, dynamic> data) async {
    final tableName = state.selectedTable;
    if (tableName == null) return false;
    try {
      await AdminApi.updateRow(tableName, rowId, data);
      await _fetchRows();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> deleteRow(int rowId) async {
    final tableName = state.selectedTable;
    if (tableName == null) return false;
    try {
      await AdminApi.deleteRow(tableName, rowId);
      await loadTables(); // refresh row counts
      await _fetchRows();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> loadFKOptions(String tableName, String columnName) async {
    final cacheKey = '$tableName.$columnName';
    if (state.fkOptionsCache.containsKey(cacheKey)) return;
    try {
      final options = await AdminApi.getFKOptions(tableName, columnName);
      final cache = Map<String, List<FKOption>>.from(state.fkOptionsCache);
      cache[cacheKey] = options;
      state = state.copyWith(fkOptionsCache: cache);
    } catch (_) {
      // Non-critical — FK dropdown will fall back to raw IDs
    }
  }
}

// ── Provider ────────────────────────────────────────────────

final adminProvider =
    NotifierProvider<AdminNotifier, AdminState>(AdminNotifier.new);
