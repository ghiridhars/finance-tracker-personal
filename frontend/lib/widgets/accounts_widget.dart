import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/account_models.dart';
import '../providers/accounts_provider.dart';
import '../providers/app_settings_provider.dart';
import 'skeleton_widgets.dart';
import 'ui_system/ui_system.dart';

class AccountsWidget extends ConsumerStatefulWidget {
  const AccountsWidget({super.key});

  @override
  ConsumerState<AccountsWidget> createState() => _AccountsWidgetState();
}

class _AccountsWidgetState extends ConsumerState<AccountsWidget> {
  late final AccountsNotifier _accountsNotifier;

  @override
  void initState() {
    super.initState();
    _accountsNotifier = ref.read(accountsProvider.notifier);
    Future.microtask(() {
      _accountsNotifier.loadAccounts();
    });
  }

  @override
  void dispose() {
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
              onPressed: () => ref.read(accountsProvider.notifier).loadAccounts(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Account',
            onPressed: () => context.push('/accounts/new'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/accounts/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
      body: _AccountsListView(accounts: accountsState.accounts),
    );
  }
}

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
            Text('No accounts yet.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Import a statement or add one manually.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/accounts/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add Account \u2192'),
            ),
          ],
        ),
      );
    }

    final bankAccounts = accounts.where((a) => a.type == 'SAVINGS').toList();
    final creditCards = accounts.where((a) => a.type == 'CREDIT_CARD').toList();
    final loans = accounts.where((a) => a.type == 'LOAN').toList();
    final investments = accounts.where((a) => a.type == 'INVESTMENT').toList();
    final others = accounts.where((a) => !['SAVINGS', 'CREDIT_CARD', 'LOAN', 'INVESTMENT'].contains(a.type)).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(accountsProvider.notifier).loadAccounts(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (bankAccounts.isNotEmpty) ...[
            _SectionHeader(icon: Icons.account_balance, title: 'Bank Accounts', count: bankAccounts.length),
            const SizedBox(height: 8),
            ...bankAccounts.map((a) => _AccountCard(account: a, allAccounts: accounts)),
            const SizedBox(height: 20),
          ],

          if (creditCards.isNotEmpty) ...[
            _SectionHeader(icon: Icons.credit_card, title: 'Credit Cards', count: creditCards.length),
            const SizedBox(height: 8),
            ...creditCards.map((a) => _AccountCard(account: a, allAccounts: accounts)),
            const SizedBox(height: 20),
          ],
          
          if (loans.isNotEmpty) ...[
            _SectionHeader(icon: Icons.real_estate_agent, title: 'Loans', count: loans.length),
            const SizedBox(height: 8),
            ...loans.map((a) => _AccountCard(account: a, allAccounts: accounts)),
            const SizedBox(height: 20),
          ],
          
          if (investments.isNotEmpty) ...[
            _SectionHeader(icon: Icons.trending_up, title: 'Investments', count: investments.length),
            const SizedBox(height: 8),
            ...investments.map((a) => _AccountCard(account: a, allAccounts: accounts)),
            const SizedBox(height: 20),
          ],

          if (others.isNotEmpty) ...[
            _SectionHeader(icon: Icons.category, title: 'Other Accounts', count: others.length),
            const SizedBox(height: 8),
            ...others.map((a) => _AccountCard(account: a, allAccounts: accounts)),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 60), // Space for FAB
        ],
      ),
    );
  }
}

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

class _AccountCard extends ConsumerWidget {
  final Account account;
  final List<Account> allAccounts;
  const _AccountCard({required this.account, required this.allAccounts});

  Color _getTypeColor() {
    switch (account.type) {
      case 'SAVINGS': return Colors.green;
      case 'CREDIT_CARD': return Colors.blue;
      case 'LOAN': return Colors.orange;
      case 'INVESTMENT': return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(appSettingsProvider).currency;
    final currencyFormat = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2);
    final cs = Theme.of(context).colorScheme;

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      accentColor: _getTypeColor(),
      onTap: () {
        if (account.id != null) {
          context.push('/accounts/${account.id}');
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.holderName ?? account.identifier,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (account.bank != null) ...[
                          Text(account.bank!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                        ],
                        Text(account.maskedIdentifier, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        BadgePill(
                          label: account.type,
                          backgroundColor: _getTypeColor().withValues(alpha: 0.15),
                          textColor: _getTypeColor(),
                        ),
                        if (account.accountSubtype != null)
                          BadgePill(
                            label: account.accountSubtype!,
                            backgroundColor: cs.surfaceContainerHighest,
                            textColor: cs.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (account.balance != null)
                    Text(
                      currencyFormat.format(account.balance),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: account.type == 'CREDIT_CARD' || account.type == 'LOAN'
                                ? cs.error
                                : Colors.green.shade700,
                          ),
                    ),
                  const SizedBox(height: 8),
                      IconButton(
                        icon: Icon(Icons.edit, size: 20, color: cs.primary),
                        onPressed: () => context.push('/accounts/${account.id}'),
                        tooltip: 'Edit Account',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.description, size: 14, color: cs.outline),
              const SizedBox(width: 4),
              Text('${account.statementCount} statements', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 16),
              Icon(Icons.receipt_long, size: 14, color: cs.outline),
              const SizedBox(width: 4),
              Text('${account.transactionCount} transactions', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
