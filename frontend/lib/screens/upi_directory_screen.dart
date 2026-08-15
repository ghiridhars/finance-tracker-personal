import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/upi_directory_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/accounts_provider.dart';
import '../models/upi_models.dart';

class UpiDirectoryScreen extends ConsumerStatefulWidget {
  const UpiDirectoryScreen({super.key});

  @override
  ConsumerState<UpiDirectoryScreen> createState() => _UpiDirectoryScreenState();
}

class _UpiDirectoryScreenState extends ConsumerState<UpiDirectoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // ensure dependencies are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoriesProvider.notifier).loadCategories();
      ref.read(accountsProvider.notifier).loadAccounts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(upiDirectoryProvider.notifier).setSearchQuery(query);
  }

  Future<void> _handleRescan() async {
    final result = await ref.read(upiDirectoryProvider.notifier).rescan();
    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${result.transactionsScanned} transactions, updated ${result.categoriesUpdated} categories, flagged ${result.transfersFlagged} transfers.',
          ),
        ),
      );
    }
  }

  void _showMappingDialog({UpiId? mapping, Map<String, dynamic>? unassigned}) {
    showDialog(
      context: context,
      builder: (context) =>
          _MappingDialog(mapping: mapping, unassigned: unassigned),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(upiDirectoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search UPI handles or labels...',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('UPI Directory'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _onSearchChanged('');
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Rescan Transactions',
            onPressed: _handleRescan,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Mappings'),
            Tab(text: 'Unassigned'),
          ],
        ),
      ),
      body: state.isLoading && state.mappings.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _AllMappingsTab(onEdit: (m) => _showMappingDialog(mapping: m)),
                _UnassignedTab(onMap: (u) => _showMappingDialog(unassigned: u)),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showMappingDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Mapping'),
            )
          : null,
    );
  }
}

class _AllMappingsTab extends ConsumerWidget {
  final Function(UpiId) onEdit;
  const _AllMappingsTab({required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(upiDirectoryProvider);
    final categoriesState = ref.watch(categoriesProvider);

    List<UpiId> filteredMappings = state.mappings.where((m) {
      if (state.searchQuery.isNotEmpty) {
        final query = state.searchQuery.toLowerCase();
        final matchHandle = m.upiHandle.toLowerCase().contains(query);
        final matchLabel = (m.label ?? '').toLowerCase().contains(query);
        if (!matchHandle && !matchLabel) return false;
      }
      if (state.filter == UpiFilter.own && !m.isOwn) return false;
      if (state.filter == UpiFilter.thirdParty && m.isOwn) return false;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SegmentedButton<UpiFilter>(
            segments: const [
              ButtonSegment(value: UpiFilter.all, label: Text('All')),
              ButtonSegment(value: UpiFilter.own, label: Text('Own Accounts')),
              ButtonSegment(
                value: UpiFilter.thirdParty,
                label: Text('Third-party'),
              ),
            ],
            selected: {state.filter},
            onSelectionChanged: (set) {
              ref.read(upiDirectoryProvider.notifier).setFilter(set.first);
            },
          ),
        ),
        Expanded(
          child: filteredMappings.isEmpty
              ? const Center(child: Text('No mappings found.'))
              : ListView.builder(
                  itemCount: filteredMappings.length,
                  itemBuilder: (context, index) {
                    final m = filteredMappings[index];
                    final category = m.categoryId != null
                        ? categoriesState.categories
                              .where((c) => c.id == m.categoryId)
                              .firstOrNull
                        : null;

                    return ListTile(
                      title: Text(m.upiHandle),
                      subtitle: Text(m.label ?? 'No label'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (category != null)
                            Chip(
                              label: Text(
                                category.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: category.color != null
                                  ? Color(
                                      int.parse(
                                        category.color!.replaceFirst(
                                          '#',
                                          '0xFF',
                                        ),
                                      ),
                                    ).withValues(alpha: 0.2)
                                  : null,
                            ),
                          const SizedBox(width: 8),
                          if (m.isOwn) const Chip(label: Text('Own')),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => onEdit(m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Delete Mapping?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                ref
                                    .read(upiDirectoryProvider.notifier)
                                    .deleteMapping(m.id!);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _UnassignedTab extends ConsumerWidget {
  final Function(Map<String, dynamic>) onMap;
  const _UnassignedTab({required this.onMap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(upiDirectoryProvider);

    List<Map<String, dynamic>> filtered = state.unassignedHandles;
    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      filtered = filtered.where((u) {
        final handle = (u['upi_handle'] as String? ?? '').toLowerCase();
        return handle.contains(query);
      }).toList();
    }

    if (filtered.isEmpty) {
      return const Center(child: Text('No unassigned handles found.'));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final u = filtered[index];
        return ListTile(
          title: Text(u['upi_handle'] ?? 'Unknown'),
          subtitle: Text(
            'Seen ${u['transaction_count']} times\nSample: ${u['sample_description']}',
          ),
          isThreeLine: true,
          trailing: FilledButton(
            onPressed: () => onMap(u),
            child: const Text('Map'),
          ),
        );
      },
    );
  }
}

class _MappingDialog extends ConsumerStatefulWidget {
  final UpiId? mapping;
  final Map<String, dynamic>? unassigned;

  const _MappingDialog({this.mapping, this.unassigned});

  @override
  ConsumerState<_MappingDialog> createState() => _MappingDialogState();
}

class _MappingDialogState extends ConsumerState<_MappingDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _handleController;
  late TextEditingController _labelController;
  int? _categoryId;
  bool _isOwn = false;
  String? _accountType;
  String? _accountIdentifier;

  @override
  void initState() {
    super.initState();
    final handle =
        widget.mapping?.upiHandle ?? widget.unassigned?['upi_handle'] ?? '';
    _handleController = TextEditingController(text: handle);
    _labelController = TextEditingController(text: widget.mapping?.label ?? '');
    _categoryId = widget.mapping?.categoryId;
    _isOwn = widget.mapping?.isOwn ?? false;
    _accountType = widget.mapping?.accountType;
    _accountIdentifier = widget.mapping?.accountIdentifier;
  }

  @override
  void dispose() {
    _handleController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).categories;
    final accounts = ref.watch(accountsProvider).accounts;

    final isEdit = widget.mapping != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Mapping' : 'Add Mapping'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _handleController,
                decoration: const InputDecoration(labelText: 'UPI Handle'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (Optional)',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Category'),
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...categories.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Is Own Account?'),
                value: _isOwn,
                onChanged: (v) => setState(() {
                  _isOwn = v;
                  if (!v) {
                    _accountType = null;
                    _accountIdentifier = null;
                  }
                }),
              ),
              if (_isOwn) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final accountItems = <DropdownMenuItem<String>>[];
                    final seenValues = <String>{};
                    String? selectedVal;

                    for (final a in accounts) {
                      final String val = (a.identifier.isNotEmpty)
                          ? a.identifier
                          : (a.id != null ? 'ACCT_${a.id}' : '');

                      if (val.isEmpty || seenValues.contains(val)) continue;
                      seenValues.add(val);

                      if (_accountIdentifier != null &&
                          _accountIdentifier!.isNotEmpty &&
                          (_accountIdentifier == val || _accountIdentifier == a.identifier)) {
                        selectedVal = val;
                      }

                      final bankName = a.bank ?? '';
                      final nameOrIdent = (a.holderName != null && a.holderName!.isNotEmpty)
                          ? a.holderName!
                          : a.maskedIdentifier;
                      final display = bankName.isNotEmpty ? '$bankName - $nameOrIdent' : nameOrIdent;

                      accountItems.add(
                        DropdownMenuItem<String>(
                          value: val,
                          child: Text('$display (${a.type})'),
                        ),
                      );
                    }

                    return DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Linked Account',
                      ),
                      initialValue: selectedVal,
                      items: accountItems,
                      onChanged: (v) {
                        setState(() {
                          _accountIdentifier = v;
                          if (v != null) {
                            final match = accounts.firstWhere(
                              (a) => (a.identifier.isNotEmpty ? a.identifier : 'ACCT_${a.id}') == v,
                              orElse: () => accounts.first,
                            );
                            _accountType = match.type;
                          } else {
                            _accountType = null;
                          }
                        });
                      },
                      validator: (v) =>
                          _isOwn && (v == null || v.isEmpty) ? 'Select an account' : null,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final notifier = ref.read(upiDirectoryProvider.notifier);
            bool success;
            if (isEdit) {
              success = await notifier.updateMapping(
                widget.mapping!.id!,
                upiHandle: _handleController.text.trim(),
                label: _labelController.text.trim().isEmpty
                    ? null
                    : _labelController.text.trim(),
                categoryId: _categoryId,
                isOwn: _isOwn,
                accountType: _accountType,
                accountIdentifier: _accountIdentifier,
              );
            } else {
              success = await notifier.createMapping(
                upiHandle: _handleController.text.trim(),
                label: _labelController.text.trim().isEmpty
                    ? null
                    : _labelController.text.trim(),
                categoryId: _categoryId,
                isOwn: _isOwn,
                accountType: _accountType,
                accountIdentifier: _accountIdentifier,
              );
            }
            if (success && context.mounted) {
              Navigator.pop(context);
            } else if (context.mounted) {
              final err = ref.read(upiDirectoryProvider).error;
              if (err != null && err.isNotEmpty) {
                final cleanMsg = err.replaceFirst(RegExp(r'^Exception:\s*'), '');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(cleanMsg),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
