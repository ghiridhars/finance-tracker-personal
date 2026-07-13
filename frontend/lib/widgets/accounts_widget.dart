/// Accounts & Statement Management screen (Phase 4).
///
/// Two-level navigation:
///   1. Accounts list — shows all linked savings/CC accounts with summary
///   2. Statement history — shows statements for the selected account
///      with swipe-to-delete support
library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/account_models.dart';
import '../providers/accounts_provider.dart';
import '../services/api_service.dart';
import 'skeleton_widgets.dart';
import 'unified_transaction_list_widget.dart';
import '../providers/transactions_provider.dart';
import '../providers/app_settings_provider.dart';
import 'upi_management_widget.dart';

class AccountsWidget extends ConsumerStatefulWidget {
  const AccountsWidget({super.key});

  @override
  ConsumerState<AccountsWidget> createState() => _AccountsWidgetState();
}

class _AccountsWidgetState extends ConsumerState<AccountsWidget> {
  // Eagerly cached in initState so dispose() never touches ref.
  late final AccountsNotifier _accountsNotifier;
  late final UnifiedTransactionsNotifier _transactionsNotifier;

  @override
  void initState() {
    super.initState();
    _accountsNotifier = ref.read(accountsProvider.notifier);
    _transactionsNotifier = ref.read(unifiedTransactionsProvider.notifier);
    // Load accounts on first build
    Future.microtask(() {
      _accountsNotifier.loadAccounts();
    });
  }

  @override
  void dispose() {
    // Defer provider mutations past the widget tree finalization phase.
    Future(() {
      _accountsNotifier.clearSelection();
      _transactionsNotifier.resetToDefaults();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsState = ref.watch(accountsProvider);

    if (accountsState.isLoading && accountsState.accounts.isEmpty) {
      return const SkeletonAccountsList();
    }

    if (accountsState.error != null && accountsState.accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Error loading accounts',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(accountsState.error!,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(accountsProvider.notifier).loadAccounts(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // If an account is selected, show statement history
    if (accountsState.selectedAccountId != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    ref.read(accountsProvider.notifier).clearSelection();
                    // Fix #4: reset all filters and date range on back nav
                    ref.read(unifiedTransactionsProvider.notifier).resetToDefaults();
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Account Transactions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const Expanded(child: UnifiedTransactionListWidget()),
        ],
      );
    }

    // Otherwise show accounts list
    return _AccountsListView(accounts: accountsState.accounts);
  }
}

// ──────────────────────────────────────────────────────────────
// Accounts List View
// ──────────────────────────────────────────────────────────────

class _AccountsListView extends ConsumerWidget {
  final List<Account> accounts;
  const _AccountsListView({required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No accounts found',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Upload a bank statement to get started',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/import'),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload a statement \u2192'),
            ),
          ],
        ),
      );
    }

    final savings = accounts.where((a) => a.isSavings).toList();
    final creditCards = accounts.where((a) => a.isCreditCard).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(accountsProvider.notifier).loadAccounts(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary cards
          _SummaryRow(accounts: accounts),
          const SizedBox(height: 20),

          if (savings.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.account_balance,
              title: 'Savings Accounts',
              count: savings.length,
            ),
            const SizedBox(height: 8),
            ...savings.map((a) => _AccountCard(account: a)),
            const SizedBox(height: 20),
          ],

          if (creditCards.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.credit_card,
              title: 'Credit Cards',
              count: creditCards.length,
            ),
            const SizedBox(height: 8),
            ...creditCards.map((a) => _AccountCard(account: a)),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Summary Row
// ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final List<Account> accounts;
  const _SummaryRow({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final totalAccounts = accounts.length;
    final totalStatements =
        accounts.fold<int>(0, (sum, a) => sum + a.statementCount);
    final totalTransactions =
        accounts.fold<int>(0, (sum, a) => sum + a.transactionCount);

    return Row(
      children: [
        Expanded(
          child: _MiniSummaryCard(
            icon: Icons.account_balance_wallet,
            label: 'Accounts',
            value: totalAccounts.toString(),
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniSummaryCard(
            icon: Icons.description,
            label: 'Statements',
            value: totalStatements.toString(),
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniSummaryCard(
            icon: Icons.receipt_long,
            label: 'Transactions',
            value: totalTransactions.toString(),
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
      ],
    );
  }
}

class _MiniSummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Section Header
// ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer)),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Account Card
// ──────────────────────────────────────────────────────────────

class _AccountCard extends ConsumerWidget {
  final Account account;
  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(appSettingsProvider).currency;
    final currencyFormat = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ref.read(accountsProvider.notifier).selectAccount(account);
          // Fix #2: use 'all' preset so date range doesn't silently limit results
          // Fix #3: set sourceType to match the account type
          ref.read(unifiedTransactionsProvider.notifier).setFilters(
            bankAccountId: account.id,
            accountIdentifier: account.identifier.isNotEmpty ? account.identifier : null,
            sourceType: account.type,
            clearCategory: true,
            clearBank: true,
            clearBankAccountId: account.id == null,
            clearIsTransfer: true,
            clearType: true,
            clearSearch: true,
            preset: DateRangePreset.all,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: icon + identifier + bank badge
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: account.isSavings
                        ? cs.primaryContainer
                        : cs.secondaryContainer,
                    child: Icon(
                      account.isSavings
                          ? Icons.account_balance
                          : Icons.credit_card,
                      color: account.isSavings
                          ? cs.onPrimaryContainer
                          : cs.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.holderName ?? 'Unknown',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${account.isSavings ? "A/C" : "Card"}: ${account.maskedIdentifier}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (account.bank != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        account.bank!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.edit, size: 18, color: cs.outline),
                    tooltip: 'Rename account',
                    onPressed: () => _showRenameDialog(
                      context,
                      ref,
                      account,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Bottom row: stats
              Row(
                children: [
                  _StatChip(
                    icon: Icons.description,
                    label: '${account.statementCount} statements',
                  ),
                  const SizedBox(width: 16),
                  _StatChip(
                    icon: Icons.receipt_long,
                    label: '${account.transactionCount} txns',
                  ),
                  const Spacer(),
                  if (account.balance != null)
                    Text(
                      currencyFormat.format(account.balance),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: account.isSavings
                                ? (Theme.of(context).brightness == Brightness.dark ? Colors.green.shade400 : Colors.green.shade700)
                                : Theme.of(context).colorScheme.error,
                          ),
                    ),
                ],
              ),
              if (account.isCreditCard &&
                  account.creditLimit != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Credit Limit: ',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(currencyFormat.format(account.creditLimit),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 16),
                    Text('Available: ',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      currencyFormat.format(account.availableCredit ?? 0),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700),
                    ),
                  ],
                ),
              ],
              if (account.lastStatementDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last statement: ${account.lastStatementDate}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ],
              // UPI IDs linked to this account
              AccountUpiSection(
                accountType: account.type,
                accountIdentifier: account.identifier,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) {
    final controller = TextEditingController(text: account.holderName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Account'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Account Name',
            hintText: 'e.g. My Savings Account',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(
              account.isSavings ? Icons.account_balance : Icons.credit_card,
            ),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _submitRename(ctx, ref, account, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _submitRename(ctx, ref, account, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRename(
    BuildContext dialogContext,
    WidgetRef ref,
    Account account,
    String newName,
  ) async {
    final name = newName.trim();
    if (name.isEmpty) return;
    Navigator.of(dialogContext).pop();
    try {
      await ApiService.renameAccount(
        accountType: account.type,
        identifier: account.identifier,
        name: name,
      );
      ref.read(accountsProvider.notifier).loadAccounts();
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Account renamed')),
        );
      }
    } catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// Removed Statement History Views
