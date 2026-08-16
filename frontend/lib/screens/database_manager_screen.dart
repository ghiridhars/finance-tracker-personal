/// Database Manager screen — browse and edit database tables.
///
/// Accessed from Settings → Advanced → Database Manager.
/// Provides table selection, paginated row browsing, search, sort,
/// and full CRUD via dynamically generated forms.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_models.dart';
import '../providers/admin_provider.dart';

class DatabaseManagerScreen extends ConsumerStatefulWidget {
  const DatabaseManagerScreen({super.key});

  @override
  ConsumerState<DatabaseManagerScreen> createState() =>
      _DatabaseManagerScreenState();
}

class _DatabaseManagerScreenState extends ConsumerState<DatabaseManagerScreen> {
  final _searchController = TextEditingController();
  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(adminProvider.notifier).loadTables();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adminState = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar
          _buildSidebar(context, adminState, notifier, textTheme, colorScheme),
          // Main Content
          Expanded(
            child: _buildMainContent(
              context,
              adminState,
              notifier,
              textTheme,
              colorScheme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    AdminState adminState,
    AdminNotifier notifier,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 16, right: 24, bottom: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.storage_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Database',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          if (adminState.tables.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: adminState.tables.length,
                itemBuilder: (context, index) {
                  final t = adminState.tables[index];
                  final isSelected = t.name == adminState.selectedTable;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: isSelected,
                      selectedTileColor: colorScheme.primaryContainer.withAlpha(
                        150,
                      ),
                      title: Text(
                        t.name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${t.rowCount} rows',
                        style: textTheme.bodySmall?.copyWith(
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () {
                        _searchController.clear();
                        notifier.selectTable(t.name);
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

  Widget _buildMainContent(
    BuildContext context,
    AdminState adminState,
    AdminNotifier notifier,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    final canAddRow =
        adminState.selectedTable != null && adminState.schema != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                adminState.selectedTable ?? 'Select a Table',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (adminState.selectedTable != null) ...[
                if (adminState.schema != null) ...[
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      value: adminState.searchColumn,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withAlpha(120),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        isDense: true,
                      ),
                      hint: const Text('All columns'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All columns')),
                        ...adminState.schema!.columns.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (val) {
                        notifier.setSearch(_searchController.text.isEmpty ? null : _searchController.text, column: val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search records...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withAlpha(
                        120,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      isDense: true,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                notifier.setSearch(null, column: adminState.searchColumn);
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      _searchDebounceTimer?.cancel();
                      _searchDebounceTimer = Timer(
                        const Duration(milliseconds: 400),
                        () => notifier.setSearch(value.isEmpty ? null : value, column: adminState.searchColumn),
                      );
                    },
                    onSubmitted: (value) {
                      _searchDebounceTimer?.cancel();
                      notifier.setSearch(value.isEmpty ? null : value, column: adminState.searchColumn);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () =>
                      notifier.selectTable(adminState.selectedTable!),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: canAddRow
                      ? () => _showRowDialog(context, ref)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('New Row'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Error Banner
        if (adminState.error != null)
          Padding(
            padding: const EdgeInsets.all(32).copyWith(bottom: 0),
            child: Material(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        adminState.error!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Data table
        Expanded(
          child: adminState.isLoading && adminState.rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : adminState.selectedTable == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_chart_rounded,
                        size: 80,
                        color: colorScheme.onSurface.withAlpha(40),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Select a table to browse',
                        style: textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                    ],
                  ),
                )
              : adminState.schema == null
              ? const Center(child: CircularProgressIndicator())
              : _buildDataTable(context, adminState, notifier),
        ),

        // Pagination
        if (adminState.selectedTable != null && adminState.total > 0)
          _buildPagination(adminState, notifier, textTheme),
      ],
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    AdminState adminState,
    AdminNotifier notifier,
  ) {
    final schema = adminState.schema!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (adminState.rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 64,
              color: colorScheme.onSurface.withAlpha(60),
            ),
            const SizedBox(height: 16),
            Text(
              'No rows found',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(32),
        child: Scrollbar(
          controller: _verticalScrollController,
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            child: DataTable(
              headingRowHeight: 56,
              dataRowMinHeight: 64,
              dataRowMaxHeight: 64,
              horizontalMargin: 24,
              columnSpacing: 40,
              dividerThickness: 0,
              headingTextStyle: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              sortColumnIndex: adminState.sortColumn != null
                  ? schema.columns.indexWhere(
                      (c) => c.name == adminState.sortColumn,
                    )
                  : null,
              sortAscending: adminState.sortOrder == 'asc',
              columns: [
                ...schema.columns.map(
                  (col) => DataColumn(
                    label: _buildColumnHeader(col),
                    onSort: (_, __) => notifier.setSort(col.name),
                    numeric: col.type == 'integer' || col.type == 'number',
                  ),
                ),
                const DataColumn(label: Text('')),
              ],
              rows: adminState.rows.map((row) {
                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>((
                    Set<WidgetState> states,
                  ) {
                    if (states.contains(WidgetState.hovered)) {
                      return colorScheme.surfaceContainerHighest.withAlpha(100);
                    }
                    return null;
                  }),
                  cells: [
                    ...schema.columns.map((col) {
                      return DataCell(
                        _buildCellContent(col, row[col.name], adminState),
                      );
                    }),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Edit',
                            onPressed: () =>
                                _showRowDialog(context, ref, existingRow: row),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCellContent(
    ColumnInfo col,
    dynamic value,
    AdminState adminState,
  ) {
    if (value == null) {
      return Text(
        'NULL',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (col.foreignKey != null) {
      final cacheKey = '${adminState.selectedTable}.${col.name}';
      final options = adminState.fkOptionsCache[cacheKey];
      if (options != null) {
        final match = options.where((o) => o.id.toString() == value.toString());
        if (match.isNotEmpty) {
          return Tooltip(
            message: 'ID: $value',
            child: Text(match.first.label, overflow: TextOverflow.ellipsis),
          );
        }
      }
    }

    if (col.type == 'boolean') {
      final boolVal = value == true || value == 1 || value == '1';
      return Icon(
        boolVal ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: boolVal ? Colors.green : Colors.grey,
      );
    }

    if (col.type == 'enum') {
      return Chip(
        label: Text(value.toString(), style: const TextStyle(fontSize: 12)),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    }

    final text = value.toString();
    return Tooltip(
      message: text.length > 40 ? text : '',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: Text(text, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildPagination(
    AdminState adminState,
    AdminNotifier notifier,
    TextTheme textTheme,
  ) {
    final start = adminState.currentPage * adminState.pageSize + 1;
    final end = (start + adminState.rows.length - 1).clamp(
      start,
      adminState.total,
    );
    final maxPage = ((adminState.total - 1) / adminState.pageSize).floor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Rows per page: ',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: adminState.pageSize,
                isDense: true,
                underline: const SizedBox(),
                items: [25, 50, 100, 200]
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text('$s', style: textTheme.bodyMedium),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) notifier.setPageSize(v);
                },
              ),
            ],
          ),
          Text(
            '$start – $end of ${adminState.total}',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                onPressed: adminState.currentPage > 0
                    ? () => notifier.goToPage(0)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: adminState.currentPage > 0
                    ? () => notifier.previousPage()
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Page ${adminState.currentPage + 1} of ${maxPage + 1}',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: adminState.currentPage < maxPage
                    ? () => notifier.nextPage()
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                onPressed: adminState.currentPage < maxPage
                    ? () => notifier.goToPage(maxPage)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(ColumnInfo col) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(col.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (col.primaryKey) ...[
              const SizedBox(width: 4),
              const _ColBadge('PK', Colors.orange),
            ],
            if (col.foreignKey != null) ...[
              const SizedBox(width: 4),
              const _ColBadge('FK', Colors.blue),
            ],
            if (!col.nullable && !col.primaryKey) ...[
              const SizedBox(width: 4),
              const _ColBadge('REQ', Colors.red),
            ],
          ],
        ),
        Text(
          col.type,
          style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  void _showRowDialog(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? existingRow,
  }) {
    final adminState = ref.read(adminProvider);
    final schema = adminState.schema;
    if (schema == null) return;

    final isEditing = existingRow != null;
    final formData = <String, dynamic>{};

    if (isEditing) {
      for (final col in schema.columns) {
        formData[col.name] = existingRow[col.name];
      }
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withAlpha(100),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 24,
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              width: 500,
              height: double.infinity,
              child: _RowFormDialog(
                schema: schema,
                tableName: adminState.selectedTable!,
                isEditing: isEditing,
                initialData: formData,
                fkOptionsCache: adminState.fkOptionsCache,
                onDelete: isEditing
                    ? () {
                        Navigator.of(dialogContext).pop();
                        _confirmDelete(context, ref, existingRow);
                      }
                    : null,
                onClose: () => Navigator.of(dialogContext).pop(),
                onSave: (data) async {
                  final notifier = ref.read(adminProvider.notifier);
                  bool success;
                  if (isEditing) {
                    final pkCol = schema.columns.firstWhere(
                      (c) => c.primaryKey,
                    );
                    final rowId = existingRow[pkCol.name];
                    success = await notifier.updateRow(rowId as int, data);
                  } else {
                    success = await notifier.createRow(data);
                  }
                  if (success && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isEditing ? 'Row updated' : 'Row created',
                          ),
                        ),
                      );
                    }
                  } else if (context.mounted) {
                    final error = ref.read(adminProvider).error;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error ?? 'Operation failed')),
                    );
                  }
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slideTween =
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: slideTween, child: child);
      },
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) {
    final adminState = ref.read(adminProvider);
    final schema = adminState.schema;
    if (schema == null) return;

    final pkCol = schema.columns.firstWhere((c) => c.primaryKey);
    final rowId = row[pkCol.name];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 40),
        title: const Text('Delete Row'),
        content: Text(
          'Delete row with ${pkCol.name} = $rowId from '
          '${adminState.selectedTable}?\n\n'
          'This action cannot be undone. Rows in other tables that '
          'reference this row may also be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final success = await ref
                  .read(adminProvider.notifier)
                  .deleteRow(rowId as int);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Row deleted' : 'Failed to delete row',
                    ),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _RowFormDialog extends StatefulWidget {
  final TableSchemaModel schema;
  final String tableName;
  final bool isEditing;
  final Map<String, dynamic> initialData;
  final Map<String, List<FKOption>> fkOptionsCache;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  final VoidCallback? onDelete;
  final VoidCallback onClose;

  const _RowFormDialog({
    required this.schema,
    required this.tableName,
    required this.isEditing,
    required this.initialData,
    required this.fkOptionsCache,
    required this.onSave,
    this.onDelete,
    required this.onClose,
  });

  @override
  State<_RowFormDialog> createState() => _RowFormDialogState();
}

class _RowFormDialogState extends State<_RowFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> _data;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _data = Map.from(widget.initialData);
    // Pre-seed boolean columns to false so non-nullable bool fields
    // are never null in the payload for new rows.
    for (final col in widget.schema.columns) {
      if (col.type == 'boolean' && !_data.containsKey(col.name)) {
        _data[col.name] = false;
      }
    }
  }

  static const _systemColumns = {
    'created_at',
    'updated_at',
    'source_type',
    'source_transaction_id',
    'statement_audit_id',
    'transfer_group_id',
  };

  List<ColumnInfo> get _editableColumns {
    return widget.schema.columns.where((col) {
      if (!widget.isEditing && col.primaryKey && col.autoincrement)
        return false;
      if (widget.isEditing && col.primaryKey) return false;
      if (_systemColumns.contains(col.name)) return false;
      return true;
    }).toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);

    final payload = <String, dynamic>{};
    for (final col in _editableColumns) {
      payload[col.name] = _data[col.name];
    }

    await widget.onSave(payload);

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = _editableColumns;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
            ),
            color: colorScheme.surfaceContainerLowest,
          ),
          child: Row(
            children: [
              Text(
                widget.isEditing ? 'Edit Row' : 'New Row',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),

        // Form
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(32),
              children: columns
                  .map(
                    (col) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildField(col),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),

        // Footer Actions
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
            ),
            color: colorScheme.surfaceContainerLowest,
          ),
          child: Row(
            children: [
              if (widget.isEditing && widget.onDelete != null)
                TextButton.icon(
                  onPressed: _isSaving ? null : widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: _isSaving ? null : widget.onClose,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.isEditing ? 'Save Changes' : 'Create Record'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildField(ColumnInfo col) {
    if (col.foreignKey != null) {
      return _buildFKDropdown(col);
    }
    if (col.type == 'enum' && col.enumValues != null) {
      return _buildEnumDropdown(col);
    }
    if (col.type == 'boolean') {
      return _buildBoolSwitch(col);
    }
    if (col.type == 'datetime') {
      return _buildDateTimeField(col);
    }
    if (col.type == 'date') {
      return _buildDateField(col);
    }
    if (col.type == 'integer' || col.type == 'number') {
      return _buildNumberField(col);
    }
    return _buildTextField(col);
  }

  Widget _buildTextField(ColumnInfo col) {
    return TextFormField(
      initialValue: _data[col.name]?.toString(),
      decoration: InputDecoration(
        labelText: col.name,
        hintText: col.nullable ? 'Optional' : 'Required',
      ),
      maxLines: col.type == 'text' ? 3 : 1,
      maxLength: col.maxLength,
      validator: (v) {
        if (!col.nullable && (v == null || v.isEmpty)) {
          return '${col.name} is required';
        }
        return null;
      },
      onSaved: (v) {
        _data[col.name] = (v == null || v.isEmpty) ? null : v;
      },
    );
  }

  Widget _buildNumberField(ColumnInfo col) {
    return TextFormField(
      initialValue: _data[col.name]?.toString(),
      decoration: InputDecoration(
        labelText: col.name,
        hintText: col.nullable ? 'Optional' : 'Required',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: col.type == 'integer'
          ? [FilteringTextInputFormatter.digitsOnly]
          : [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      validator: (v) {
        if (!col.nullable && (v == null || v.isEmpty)) {
          return '${col.name} is required';
        }
        if (v != null && v.isNotEmpty) {
          if (col.type == 'integer' && int.tryParse(v) == null) {
            return 'Must be an integer';
          }
          if (col.type == 'number' && double.tryParse(v) == null) {
            return 'Must be a number';
          }
        }
        return null;
      },
      onSaved: (v) {
        if (v == null || v.isEmpty) {
          _data[col.name] = null;
        } else if (col.type == 'integer') {
          _data[col.name] = int.parse(v);
        } else {
          _data[col.name] = double.parse(v);
        }
      },
    );
  }

  Widget _buildBoolSwitch(ColumnInfo col) {
    // Wrap in FormField so _formKey.currentState!.save() captures the value.
    return FormField<bool>(
      initialValue: _data[col.name] == true ||
          _data[col.name] == 1 ||
          _data[col.name] == '1',
      onSaved: (v) => _data[col.name] = v ?? false,
      builder: (field) {
        return SwitchListTile(
          title: Text(col.name),
          value: field.value ?? false,
          onChanged: (v) {
            field.didChange(v);
            setState(() => _data[col.name] = v);
          },
          contentPadding: EdgeInsets.zero,
        );
      },
    );
  }

  Widget _buildDateField(ColumnInfo col) {
    final currentVal = _data[col.name]?.toString() ?? '';
    return TextFormField(
      initialValue: currentVal,
      decoration: InputDecoration(
        labelText: col.name,
        hintText: 'YYYY-MM-DD',
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() {
                _data[col.name] = picked.toIso8601String().split('T')[0];
              });
            }
          },
        ),
      ),
      validator: (v) {
        if (!col.nullable && (v == null || v.isEmpty)) {
          return '${col.name} is required';
        }
        return null;
      },
      onSaved: (v) => _data[col.name] = (v == null || v.isEmpty) ? null : v,
    );
  }

  Widget _buildDateTimeField(ColumnInfo col) {
    final currentVal = _data[col.name]?.toString() ?? '';
    return TextFormField(
      initialValue: currentVal,
      decoration: InputDecoration(
        labelText: col.name,
        hintText: 'YYYY-MM-DD HH:MM:SS',
      ),
      validator: (v) {
        if (!col.nullable && (v == null || v.isEmpty)) {
          return '${col.name} is required';
        }
        return null;
      },
      onSaved: (v) => _data[col.name] = (v == null || v.isEmpty) ? null : v,
    );
  }

  Widget _buildEnumDropdown(ColumnInfo col) {
    return DropdownButtonFormField<String>(
      initialValue: _data[col.name]?.toString(),
      decoration: InputDecoration(labelText: col.name),
      items: [
        if (col.nullable)
          const DropdownMenuItem<String>(value: null, child: Text('— None —')),
        ...col.enumValues!.map(
          (v) => DropdownMenuItem(value: v, child: Text(v)),
        ),
      ],
      validator: (v) {
        if (!col.nullable && v == null) return '${col.name} is required';
        return null;
      },
      onChanged: (v) => setState(() => _data[col.name] = v),
      onSaved: (v) => _data[col.name] = v,
    );
  }

  Widget _buildFKDropdown(ColumnInfo col) {
    final cacheKey = '${widget.tableName}.${col.name}';
    final options = widget.fkOptionsCache[cacheKey] ?? [];

    final currentVal = _data[col.name] is int
        ? _data[col.name] as int
        : int.tryParse(_data[col.name]?.toString() ?? '');

    return DropdownButtonFormField<int?>(
      initialValue: currentVal,
      decoration: InputDecoration(labelText: col.name),
      isExpanded: true,
      items: [
        if (col.nullable)
          const DropdownMenuItem<int?>(value: null, child: Text('— None —')),
        ...options.map(
          (o) => DropdownMenuItem<int?>(
            value: o.id is int ? o.id as int : int.tryParse(o.id.toString()),
            child: Text(
              '${o.label} (${o.id})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      validator: (v) {
        if (!col.nullable && v == null) return '${col.name} is required';
        return null;
      },
      onChanged: (v) => setState(() => _data[col.name] = v),
      onSaved: (v) => _data[col.name] = v,
    );
  }
}

class _ColBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ColBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withAlpha(120), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
