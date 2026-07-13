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

class _DatabaseManagerScreenState
    extends ConsumerState<DatabaseManagerScreen> {
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
    final canAddRow = adminState.selectedTable != null &&
        adminState.schema != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Manager'),
        actions: [
          if (canAddRow)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: FilledButton.icon(
                onPressed: () => _showRowDialog(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Row'),
              ),
            ),
          if (adminState.selectedTable != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () {
                notifier.selectTable(adminState.selectedTable!);
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Table selector + search bar ──────────────────
            Row(
              children: [
                // Table dropdown
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: adminState.selectedTable,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Table',
                      prefixIcon: Icon(Icons.table_chart),
                      isDense: true,
                    ),
                    items: adminState.tables.map((t) {
                      return DropdownMenuItem(
                        value: t.name,
                        child: Text(
                          '${t.name}  (${t.rowCount} rows)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _searchController.clear();
                        notifier.selectTable(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Search
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search rows',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                notifier.setSearch(null);
                              },
                            )
                          : null,
                    ),
                    enabled: adminState.selectedTable != null,
                    onChanged: (value) {
                      _searchDebounceTimer?.cancel();
                      _searchDebounceTimer = Timer(
                        const Duration(milliseconds: 400),
                        () => notifier.setSearch(value.isEmpty ? null : value),
                      );
                    },
                    onSubmitted: (value) {
                      _searchDebounceTimer?.cancel();
                      notifier.setSearch(value.isEmpty ? null : value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Error banner ─────────────────────────────────
            if (adminState.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: colorScheme.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            adminState.error!,
                            style: TextStyle(
                                color: colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Data table ───────────────────────────────────
            Expanded(
              child: adminState.isLoading && adminState.rows.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : adminState.selectedTable == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.table_chart_outlined,
                                  size: 64,
                                  color: colorScheme.onSurface
                                      .withAlpha(80)),
                              const SizedBox(height: 16),
                              Text('Select a table to browse',
                                  style: textTheme.titleMedium),
                            ],
                          ),
                        )
                      : adminState.schema == null
                          ? const Center(
                              child: CircularProgressIndicator())
                          : _buildDataTable(
                              context, adminState, notifier),
            ),

            // ── Pagination ───────────────────────────────────
            if (adminState.selectedTable != null &&
                adminState.total > 0)
              _buildPagination(adminState, notifier, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    AdminState adminState,
    AdminNotifier notifier,
  ) {
    final schema = adminState.schema!;
    final colorScheme = Theme.of(context).colorScheme;

    if (adminState.rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48,
                color: colorScheme.onSurface.withAlpha(80)),
            const SizedBox(height: 12),
            const Text('No rows found'),
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
        child: Scrollbar(
          controller: _verticalScrollController,
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            child: DataTable(
              sortColumnIndex: adminState.sortColumn != null
                  ? schema.columns
                      .indexWhere((c) => c.name == adminState.sortColumn)
                  : null,
              sortAscending: adminState.sortOrder == 'asc',
              headingRowColor: WidgetStateProperty.all(
                colorScheme.surfaceContainerHighest.withAlpha(120),
              ),
              columns: [
                // Data columns
                ...schema.columns.map((col) => DataColumn(
                      label: _buildColumnHeader(col),
                      onSort: (_, __) => notifier.setSort(col.name),
                      numeric: col.type == 'integer' || col.type == 'number',
                    )),
                // Actions column
                const DataColumn(label: Text('Actions')),
              ],
              rows: adminState.rows.map((row) {
                return DataRow(
                  onSelectChanged: (_) =>
                      _showRowDialog(context, ref, existingRow: row),
                  cells: [
                    ...schema.columns.map((col) {
                      final value = row[col.name];
                      return DataCell(
                        _buildCellContent(col, value, adminState),
                      );
                    }),
                    // Actions
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              size: 18, color: colorScheme.primary),
                          tooltip: 'Edit',
                          onPressed: () =>
                              _showRowDialog(context, ref, existingRow: row),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: colorScheme.error),
                          tooltip: 'Delete',
                          onPressed: () =>
                              _confirmDelete(context, ref, row),
                        ),
                      ],
                    )),
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
      return Text('NULL',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
              fontStyle: FontStyle.italic));
    }

    // FK column — show resolved label if available
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

    // Boolean
    if (col.type == 'boolean') {
      final boolVal = value == true || value == 1 || value == '1';
      return Icon(
        boolVal ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: boolVal ? Colors.green : Colors.grey,
      );
    }

    // Enum
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
    final end = (start + adminState.rows.length - 1)
        .clamp(start, adminState.total);
    final maxPage = ((adminState.total - 1) / adminState.pageSize).floor();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Page size selector
          Row(
            children: [
              Text('Rows: ', style: textTheme.bodySmall),
              DropdownButton<int>(
                value: adminState.pageSize,
                isDense: true,
                underline: const SizedBox(),
                items: [25, 50, 100, 200]
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text('$s', style: textTheme.bodySmall),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) notifier.setPageSize(v);
                },
              ),
            ],
          ),
          Text(
            'Showing $start–$end of ${adminState.total}',
            style: textTheme.bodySmall,
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                tooltip: 'First page',
                onPressed: adminState.currentPage > 0
                    ? () => notifier.goToPage(0)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: adminState.currentPage > 0
                    ? () => notifier.previousPage()
                    : null,
              ),
              Text('Page ${adminState.currentPage + 1} of ${maxPage + 1}'),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: adminState.currentPage < maxPage
                    ? () => notifier.nextPage()
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                tooltip: 'Last page',
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
            Text(col.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (col.primaryKey) ...[const SizedBox(width: 4), const _ColBadge('PK', Colors.orange)],
            if (col.foreignKey != null) ...[const SizedBox(width: 4), const _ColBadge('FK', Colors.blue)],
            if (!col.nullable && !col.primaryKey) ...[const SizedBox(width: 4), const _ColBadge('REQ', Colors.red)],
          ],
        ),
        Text(
          col.type,
          style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  // ── CRUD Dialogs ─────────────────────────────────────────

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

    // Pre-populate for editing
    if (isEditing) {
      for (final col in schema.columns) {
        formData[col.name] = existingRow[col.name];
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => _RowFormDialog(
        schema: schema,
        tableName: adminState.selectedTable!,
        isEditing: isEditing,
        initialData: formData,
        fkOptionsCache: adminState.fkOptionsCache,
        onSave: (data) async {
          final notifier = ref.read(adminProvider.notifier);
          bool success;
          if (isEditing) {
            final pkCol = schema.columns.firstWhere((c) => c.primaryKey);
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
                  content: Text(isEditing ? 'Row updated' : 'Row created'),
                ),
              );
            }
          } else if (context.mounted) {
            // Show error from state
            final error = ref.read(adminProvider).error;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error ?? 'Operation failed')),
            );
          }
        },
      ),
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
                        success ? 'Row deleted' : 'Failed to delete row'),
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

// ── Row Form Dialog ─────────────────────────────────────────

class _RowFormDialog extends StatefulWidget {
  final TableSchemaModel schema;
  final String tableName;
  final bool isEditing;
  final Map<String, dynamic> initialData;
  final Map<String, List<FKOption>> fkOptionsCache;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const _RowFormDialog({
    required this.schema,
    required this.tableName,
    required this.isEditing,
    required this.initialData,
    required this.fkOptionsCache,
    required this.onSave,
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
  }

  // System/audit columns that should not be user-editable
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
      // Skip autoincrement PKs in create mode
      if (!widget.isEditing && col.primaryKey && col.autoincrement) {
        return false;
      }
      // Always skip PK in edit mode
      if (widget.isEditing && col.primaryKey) return false;
      // Skip internal/system columns
      if (_systemColumns.contains(col.name)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final columns = _editableColumns;

    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Row' : 'Add Row'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: columns.map((col) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildField(col),
              )).toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.isEditing ? 'Update' : 'Create'),
        ),
      ],
    );
  }

  Widget _buildField(ColumnInfo col) {
    // FK column — dropdown
    if (col.foreignKey != null) {
      return _buildFKDropdown(col);
    }

    // Enum column — dropdown
    if (col.type == 'enum' && col.enumValues != null) {
      return _buildEnumDropdown(col);
    }

    // Boolean — switch
    if (col.type == 'boolean') {
      return _buildBoolSwitch(col);
    }

    // Datetime
    if (col.type == 'datetime') {
      return _buildDateTimeField(col);
    }

    // Date
    if (col.type == 'date') {
      return _buildDateField(col);
    }

    // Number / Integer
    if (col.type == 'integer' || col.type == 'number') {
      return _buildNumberField(col);
    }

    // String / Text — text field
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
    final currentVal =
        _data[col.name] == true || _data[col.name] == 1 || _data[col.name] == '1';
    return SwitchListTile(
      title: Text(col.name),
      value: currentVal,
      onChanged: (v) => setState(() => _data[col.name] = v),
      contentPadding: EdgeInsets.zero,
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
              initialDate: DateTime.tryParse(currentVal) ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              final formatted =
                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              setState(() => _data[col.name] = formatted);
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
      onSaved: (v) {
        _data[col.name] = (v == null || v.isEmpty) ? null : v;
      },
    );
  }

  Widget _buildDateTimeField(ColumnInfo col) {
    final currentVal = _data[col.name]?.toString() ?? '';
    return TextFormField(
      key: ValueKey('${col.name}_$currentVal'),
      initialValue: currentVal,
      decoration: InputDecoration(
        labelText: col.name,
        hintText: 'YYYY-MM-DDTHH:MM:SS',
        suffixIcon: IconButton(
          icon: const Icon(Icons.access_time),
          tooltip: 'Pick date & time',
          onPressed: () async {
            final parsed = DateTime.tryParse(currentVal);
            final picked = await showDatePicker(
              context: context,
              initialDate: parsed ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null || !mounted) return;
            final pickedTime = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(parsed ?? DateTime.now()),
            );
            if (!mounted) return;
            final combined = DateTime(
              picked.year, picked.month, picked.day,
              pickedTime?.hour ?? 0, pickedTime?.minute ?? 0,
            );
            setState(() => _data[col.name] = combined.toIso8601String());
          },
        ),
      ),
      validator: (v) {
        if (!col.nullable && (v == null || v.isEmpty)) {
          return '${col.name} is required';
        }
        return null;
      },
      onSaved: (v) =>
          _data[col.name] = (v == null || v.isEmpty) ? null : v,
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

    // Current value as int for matching
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
            child: Text('${o.label} (${o.id})',
                overflow: TextOverflow.ellipsis),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);

    // Build payload — only include changed/non-null fields for updates
    final payload = <String, dynamic>{};
    for (final col in _editableColumns) {
      payload[col.name] = _data[col.name];
    }

    await widget.onSave(payload);

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }
}

// ── Column badge chip ───────────────────────────────────────

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
            fontSize: 9, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
