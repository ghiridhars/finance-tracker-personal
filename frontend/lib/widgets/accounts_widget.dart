/// Accounts & Statement Management screen (Phase 4).
///
/// Two-level navigation:
///   1. Accounts list — shows all linked savings/CC accounts with summary
///   2. Statement history — shows statements for the selected account
///      with swipe-to-delete support
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/account_models.dart';
import '../providers/accounts_provider.dart';
import '../services/api_service.dart';
import 'skeleton_widgets.dart';

final _currencyFormat = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);

class AccountsWidget extends ConsumerStatefulWidget {
  const AccountsWidget({super.key});

  @override
  ConsumerState<AccountsWidget> createState() => _AccountsWidgetState();
}

class _AccountsWidgetState extends ConsumerState<AccountsWidget> {
  @override
  void initState() {
    super.initState();
    // Load accounts on first build
    Future.microtask(() {
      ref.read(accountsProvider.notifier).loadAccounts();
    });
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
      return _StatementHistoryView(
        accountId: accountsState.selectedAccountId!,
        accountType: accountsState.selectedAccountType!,
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
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            ref.read(accountsProvider.notifier).selectAccount(account),
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
                      _currencyFormat.format(account.balance),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: account.isSavings
                                ? Colors.green.shade700
                                : Colors.red.shade700,
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
                    Text(_currencyFormat.format(account.creditLimit),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 16),
                    Text('Available: ',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      _currencyFormat.format(account.availableCredit ?? 0),
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

// ──────────────────────────────────────────────────────────────
// Statement History View
// ──────────────────────────────────────────────────────────────

class _StatementHistoryView extends ConsumerWidget {
  final String accountId;
  final String accountType;

  const _StatementHistoryView({
    required this.accountId,
    required this.accountType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider);
    final isSavings = accountType == 'SAVINGS';

    return Column(
      children: [
        // Header bar with back button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    ref.read(accountsProvider.notifier).clearSelection(),
                tooltip: 'Back to accounts',
              ),
              Icon(
                isSavings ? Icons.account_balance : Icons.credit_card,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${isSavings ? "Savings" : "Credit Card"} Statements — ****${accountId.length > 4 ? accountId.substring(accountId.length - 4) : accountId}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${isSavings ? accountsState.savingsTotal : accountsState.ccTotal} total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),

        // Loading indicator
        if (accountsState.isLoading)
          const LinearProgressIndicator(),

        // Statement list
        Expanded(
          child: isSavings
              ? _SavingsStatementsList(
                  statements: accountsState.savingsStatements)
              : _CreditCardStatementsList(
                  statements: accountsState.ccStatements),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Savings Statements List
// ──────────────────────────────────────────────────────────────

class _SavingsStatementsList extends ConsumerWidget {
  final List<SavingsStatementSummary> statements;
  const _SavingsStatementsList({required this.statements});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (statements.isEmpty) {
      return const Center(child: Text('No statements found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: statements.length,
      itemBuilder: (context, index) {
        final stmt = statements[index];
        return Dismissible(
          key: ValueKey(stmt.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) => _confirmDelete(context, 'savings statement'),
          onDismissed: (_) {
            ref
                .read(accountsProvider.notifier)
                .deleteSavingsStatement(stmt.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Statement deleted')),
            );
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.description, size: 20),
              ),
              title: Text(
                '${stmt.fromDate ?? "?"} → ${stmt.toDate ?? "?"}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${stmt.transactionCount} transactions'
                '${stmt.openingBalance != null ? " · Opening: ${_currencyFormat.format(stmt.openingBalance)}" : ""}',
              ),
              trailing: stmt.closingBalance != null
                  ? Text(
                      _currencyFormat.format(stmt.closingBalance),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Credit Card Statements List
// ──────────────────────────────────────────────────────────────

class _CreditCardStatementsList extends ConsumerWidget {
  final List<CreditCardStatementSummary> statements;
  const _CreditCardStatementsList({required this.statements});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (statements.isEmpty) {
      return const Center(child: Text('No statements found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: statements.length,
      itemBuilder: (context, index) {
        final stmt = statements[index];
        return Dismissible(
          key: ValueKey(stmt.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) =>
              _confirmDelete(context, 'credit card statement'),
          onDismissed: (_) {
            ref
                .read(accountsProvider.notifier)
                .deleteCreditCardStatement(stmt.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Statement deleted')),
            );
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                child: const Icon(Icons.credit_card, size: 20),
              ),
              title: Text(
                'Statement: ${stmt.statementDate ?? "?"}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${stmt.transactionCount} transactions'
                '${stmt.dueDate != null ? " · Due: ${stmt.dueDate}" : ""}',
              ),
              trailing: stmt.totalDues != null
                  ? Text(
                      _currencyFormat.format(stmt.totalDues),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────

Future<bool?> _confirmDelete(BuildContext context, String itemType) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Statement'),
      content: Text(
        'Are you sure you want to delete this $itemType? '
        'All associated transactions (including unified) will be permanently removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
