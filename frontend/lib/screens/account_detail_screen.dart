import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/category_models.dart';
import '../models/enums.dart';
import '../models/unified_transaction_models.dart';
import '../providers/accounts_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/api_service.dart';

class AccountDetailScreen extends ConsumerStatefulWidget {
  final int? accountId;
  const AccountDetailScreen({super.key, this.accountId});

  @override
  ConsumerState<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  bool _isSaving = false;

  List<UnifiedTransaction> _transactions = [];
  bool _isLoadingTransactions = false;
  String? _transactionsError;

  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _holderNameController = TextEditingController();
  final _ifscCodeController = TextEditingController();
  final _notesController = TextEditingController();
  
  final _loanPrincipalController = TextEditingController();
  final _loanInterestRateController = TextEditingController();
  final _loanEmiAmountController = TextEditingController();
  final _loanStartDateController = TextEditingController();
  final _loanEndDateController = TextEditingController();
  
  final _creditLimitController = TextEditingController();
  final _billingCycleDayController = TextEditingController();
  
  final _investedAmountController = TextEditingController();
  final _currentValueController = TextEditingController();

  String? _bankName;
  String? _accountType;
  String? _accountSubtype;

  final List<String> _banks = [
    'HDFC', 'ICICI', 'SBI', 'AXIS', 'KOTAK', 'YES_BANK', 'BOB', 'FEDERAL_BANK', 'OTHER'
  ];

  final List<String> _accountTypes = [
    'SAVINGS', 'CREDIT_CARD', 'LOAN', 'INVESTMENT', 'OTHER'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoriesProvider.notifier).loadCategories();
    });
    if (widget.accountId != null) {
      _loadAccountDetails();
      _loadTransactions();
    }
  }

  Future<void> _loadTransactions() async {
    if (widget.accountId == null) return;
    setState(() => _isLoadingTransactions = true);
    try {
      final txs = await ApiService.getUnifiedTransactions(
        bankAccountId: widget.accountId,
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _transactions = txs;
          _isLoadingTransactions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transactionsError = e.toString();
          _isLoadingTransactions = false;
        });
      }
    }
  }

  Future<void> _loadAccountDetails() async {
    setState(() => _isLoading = true);
    try {
      final summary = await ApiService.getAccountSummary(widget.accountId!);
      final accountData = summary['account'] ?? summary;
      
      _nameController.text = accountData['name'] ?? '';
      _accountNumberController.text = accountData['account_number'] ?? '';
      _holderNameController.text = accountData['holder_name'] ?? '';
      _ifscCodeController.text = accountData['ifsc_code'] ?? '';
      _notesController.text = accountData['notes'] ?? '';
      
      if (accountData['loan_principal'] != null) {
        _loanPrincipalController.text = accountData['loan_principal'].toString();
      }
      if (accountData['loan_interest_rate'] != null) {
        _loanInterestRateController.text = accountData['loan_interest_rate'].toString();
      }
      if (accountData['loan_emi_amount'] != null) {
        _loanEmiAmountController.text = accountData['loan_emi_amount'].toString();
      }
      _loanStartDateController.text = accountData['loan_start_date'] ?? '';
      _loanEndDateController.text = accountData['loan_end_date'] ?? '';
      
      if (accountData['credit_limit'] != null) {
        _creditLimitController.text = accountData['credit_limit'].toString();
      }
      if (accountData['billing_cycle_day'] != null) {
        _billingCycleDayController.text = accountData['billing_cycle_day'].toString();
      }
      if (accountData['invested_amount'] != null) {
        _investedAmountController.text = accountData['invested_amount'].toString();
      }
      if (accountData['current_value'] != null) {
        _currentValueController.text = accountData['current_value'].toString();
      }

      setState(() {
        _bankName = accountData['bank_name'];
        if (!_banks.contains(_bankName)) {
           if (_bankName != null && _bankName!.isNotEmpty) {
             _banks.add(_bankName!);
           }
        }
        _accountType = accountData['account_type'];
        _accountSubtype = accountData['account_subtype'];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load account: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final params = <String, dynamic>{
      'bank_name': _bankName,
      'account_type': _accountType,
      'name': _nameController.text.trim(),
      'account_number': _accountNumberController.text.trim().isNotEmpty ? _accountNumberController.text.trim() : null,
      'holder_name': _holderNameController.text.trim().isNotEmpty ? _holderNameController.text.trim() : null,
      'ifsc_code': _ifscCodeController.text.trim().isNotEmpty ? _ifscCodeController.text.trim() : null,
      'account_subtype': _accountSubtype,
      'notes': _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      'loan_principal': double.tryParse(_loanPrincipalController.text),
      'loan_interest_rate': double.tryParse(_loanInterestRateController.text),
      'loan_emi_amount': double.tryParse(_loanEmiAmountController.text),
      'loan_start_date': _loanStartDateController.text.trim().isNotEmpty ? _loanStartDateController.text.trim() : null,
      'loan_end_date': _loanEndDateController.text.trim().isNotEmpty ? _loanEndDateController.text.trim() : null,
      'credit_limit': double.tryParse(_creditLimitController.text),
      'billing_cycle_day': int.tryParse(_billingCycleDayController.text),
      'invested_amount': double.tryParse(_investedAmountController.text),
      'current_value': double.tryParse(_currentValueController.text),
    };

    try {
      if (widget.accountId == null) {
        await ref.read(accountsProvider.notifier).createAccount(params);
      } else {
        await ref.read(accountsProvider.notifier).updateAccount(widget.accountId!, params);
      }
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save account: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  List<String> _getSubtypesForType(String? type) {
    switch (type) {
      case 'SAVINGS':
        return ['SAVINGS', 'SALARY', 'CURRENT'];
      case 'CREDIT_CARD':
        return ['CREDIT_CARD'];
      case 'LOAN':
        return ['LOAN_HOME', 'LOAN_PERSONAL', 'LOAN_VEHICLE', 'LOAN_EDUCATION', 'LOAN_OTHER'];
      case 'INVESTMENT':
        return ['FD', 'RD', 'MF', 'DEMAT', 'PPF', 'NPS'];
      default:
        return ['OTHER'];
    }
  }

  Future<void> _showEditTransactionDialog(UnifiedTransaction tx) async {
    final categories = ref.read(categoriesProvider).categories;
    final allAccounts = ref.read(accountsProvider).accounts;
    int? selectedCategoryId = tx.categoryId;
    final isDebit = tx.type == TransactionType.debit;
    int? selectedTransferAccountId = isDebit ? tx.toAccountId : tx.fromAccountId;
    final merchantCtrl = TextEditingController(text: tx.merchantName ?? '');
    final notesCtrl = TextEditingController(text: tx.notes ?? '');
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedCategory = categories.firstWhere(
              (c) => c.id == selectedCategoryId,
              orElse: () => Category(id: -1, name: '', isSystem: false),
            );
            final isSelfTransfer = tx.isTransfer || selectedCategory.name == 'Self Transfer';

            return AlertDialog(
              title: const Text('Edit Transaction'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description ?? 'Transaction',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tx.date ?? ''} • ₹${tx.amount?.toStringAsFixed(2) ?? '0.00'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((c) {
                        return DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(c.name),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedCategoryId = val),
                    ),
                    if (isSelfTransfer && allAccounts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: selectedTransferAccountId,
                        decoration: InputDecoration(
                          labelText: isDebit ? 'Transfer Destination (To Account)' : 'Transfer Origin (From Account)',
                          border: const OutlineInputBorder(),
                        ),
                        items: allAccounts
                            .where((a) => a.id != widget.accountId)
                            .map((a) => DropdownMenuItem<int>(
                                  value: a.id,
                                  child: Text('${a.bank ?? 'Account'} ${a.maskedIdentifier} (${a.type})'),
                                ))
                            .toList(),
                        onChanged: (val) => setDialogState(() => selectedTransferAccountId = val),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: merchantCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Merchant Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            await ApiService.updateTransaction(
                              tx.id!,
                              categoryId: selectedCategoryId,
                              merchantName: merchantCtrl.text.trim().isNotEmpty ? merchantCtrl.text.trim() : null,
                              notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                              fromAccountId: isDebit ? null : selectedTransferAccountId,
                              toAccountId: isDebit ? selectedTransferAccountId : null,
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Failed to update: $e')),
                              );
                            }
                          } finally {
                            if (ctx.mounted) setDialogState(() => isSubmitting = false);
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    ).then((saved) {
      if (saved == true) {
        _loadTransactions();
        ref.invalidate(unifiedTransactionsProvider);
      }
    });
  }

  void _showEditAccountBottomSheet(List<String> subtypes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Edit Account Info'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: _buildEditFormTab(subtypes),
        );
      },
    );
  }

  Widget _buildTransactionsTab() {
    final cs = Theme.of(context).colorScheme;
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    if (_isLoadingTransactions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_transactionsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Failed to load transactions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_transactionsError!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadTransactions,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text('No transactions found', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('No transactions associated with this account yet.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final tx = _transactions[index];
          final isCredit = tx.type == TransactionType.credit;
          final color = isCredit ? Colors.green.shade600 : cs.error;

          final catName = tx.category?.name;

          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              onTap: () => _showEditTransactionDialog(tx),
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(
                  isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                  color: color,
                  size: 20,
                ),
              ),
              title: Text(
                tx.merchantName ?? tx.description ?? 'Transaction',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Builder(
                builder: (context) {
                  String sub = tx.date ?? '';
                  if (catName != null) sub += ' • $catName';
                  if (tx.isTransfer) {
                    final otherAcc = isCredit ? tx.fromAccountName : tx.toAccountName;
                    if (otherAcc != null) {
                      sub += isCredit ? ' (from $otherAcc)' : ' (to $otherAcc)';
                    }
                  }
                  return Text(
                    sub,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  );
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currencyFormat.format(tx.amount ?? 0.0),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
                    onPressed: () => _showEditTransactionDialog(tx),
                    tooltip: 'Edit Transaction',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditFormTab(List<String> subtypes) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Basic Info', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _bankName,
              decoration: const InputDecoration(
                labelText: 'Bank *',
                border: OutlineInputBorder(),
              ),
              items: _banks.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() => _bankName = val),
              validator: (value) => value == null || value.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _accountType,
                    decoration: const InputDecoration(
                      labelText: 'Account Type *',
                      border: OutlineInputBorder(),
                    ),
                    items: _accountTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() {
                      _accountType = val;
                      _accountSubtype = null;
                    }),
                    validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _accountSubtype,
                    decoration: const InputDecoration(
                      labelText: 'Subtype',
                      border: OutlineInputBorder(),
                    ),
                    items: subtypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() => _accountSubtype = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountNumberController,
              decoration: const InputDecoration(
                labelText: 'Account Number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _holderNameController,
                    decoration: const InputDecoration(
                      labelText: 'Holder Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _ifscCodeController,
                    decoration: const InputDecoration(
                      labelText: 'IFSC Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            
            if (_accountType == 'LOAN') ...[
              const SizedBox(height: 24),
              Text('Loan Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _loanPrincipalController,
                      decoration: const InputDecoration(
                        labelText: 'Principal Amount',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _loanInterestRateController,
                      decoration: const InputDecoration(
                        labelText: 'Interest Rate (%)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _loanEmiAmountController,
                decoration: const InputDecoration(
                  labelText: 'EMI Amount',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _loanStartDateController,
                      decoration: const InputDecoration(
                        labelText: 'Start Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () => _selectDate(_loanStartDateController),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _loanEndDateController,
                      decoration: const InputDecoration(
                        labelText: 'End Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () => _selectDate(_loanEndDateController),
                    ),
                  ),
                ],
              ),
            ],
            
            if (_accountType == 'CREDIT_CARD') ...[
              const SizedBox(height: 24),
              Text('Credit Card Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _creditLimitController,
                      decoration: const InputDecoration(
                        labelText: 'Credit Limit',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _billingCycleDayController,
                      decoration: const InputDecoration(
                        labelText: 'Billing Day (1-31)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
            
            if (_accountType == 'INVESTMENT') ...[
              const SizedBox(height: 24),
              Text('Investment Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _investedAmountController,
                      readOnly: true,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Invested Amount',
                        border: OutlineInputBorder(),
                        helperText: 'Auto-calculated',
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _currentValueController,
                      readOnly: true,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Current Value',
                        border: OutlineInputBorder(),
                        helperText: 'Auto-calculated',
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 24),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _saveAccount,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _isSaving 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Account', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final subtypes = _getSubtypesForType(_accountType);
    if (_accountSubtype != null && !subtypes.contains(_accountSubtype)) {
      _accountSubtype = null;
    }

    if (widget.accountId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Add Account'),
        ),
        body: _buildEditFormTab(subtypes),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_nameController.text.isNotEmpty ? _nameController.text : 'Account Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Account Info',
            onPressed: () => _showEditAccountBottomSheet(subtypes),
          ),
        ],
      ),
      body: _buildTransactionsTab(),
    );
  }
}
