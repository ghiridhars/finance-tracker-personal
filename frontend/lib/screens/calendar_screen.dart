import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/unified_transaction_models.dart';
import '../models/enums.dart';
import '../models/analytics_models.dart';
import '../models/category_models.dart';
import '../providers/dashboard_provider.dart';
import '../providers/categories_provider.dart';
import '../services/api_service.dart';

final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Fixed color palette for each bank.
const Map<String, Color> _bankColors = {
  'HDFC': Color(0xFF1565C0),       // blue 800
  'ICICI': Color(0xFFEF6C00),      // orange 800
  'SBI': Color(0xFF2E7D32),        // green 800
  'AXIS': Color(0xFF6A1B9A),       // purple 800
  'KOTAK': Color(0xFF00838F),      // cyan 800
  'YES_BANK': Color(0xFFC62828),   // red 800
  'BOB': Color(0xFFFF8F00),        // amber 800
  'FEDERAL_BANK': Color(0xFF283593), // indigo 800
  'OTHER': Color(0xFF546E7A),      // blue-grey 600
};

Color _colorForBank(String bank) =>
    _bankColors[bank.toUpperCase()] ?? _bankColors['OTHER']!;

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);

    if (dash.isLoading && dash.summary == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (dash.error != null && dash.summary == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('Failed to load calendar data',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(dash.error!,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(dashboardProvider.notifier).loadDashboard(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, size: 28, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Spending Calendar',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.hardEdge,
                child: _SpendingCalendar(
                  data: dash.calendarData,
                  focusedMonth: dash.calendarMonth,
                  onMonthChanged: (m) =>
                      ref.read(dashboardProvider.notifier).setCalendarMonth(m),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpendingCalendar extends StatelessWidget {
  final List<SpendingTrend> data;
  final DateTime focusedMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const _SpendingCalendar({
    required this.data,
    required this.focusedMonth,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build maps from date → total spending and date → account breakdown
    final Map<DateTime, double> spendingByDay = {};
    final Map<DateTime, List<AccountSpending>> accountsByDay = {};
    double maxSpending = 0;
    final Set<String> banksInMonth = {};

    for (final d in data) {
      final parts = d.period.split('-');
      if (parts.length == 3) {
        final dt = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        spendingByDay[dt] = d.spending;
        accountsByDay[dt] = d.byAccount;
        if (d.spending > maxSpending) maxSpending = d.spending;
        for (final a in d.byAccount) {
          banksInMonth.add(a.bank);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TableCalendar<void>(
              shouldFillViewport: true,
              firstDay: DateTime(2020),
              lastDay: DateTime(2030, 12, 31),
              focusedDay: focusedMonth,
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {CalendarFormat.month: 'Month'},
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(fontWeight: FontWeight.w600),
                leftChevronIcon:
                    Icon(Icons.chevron_left, color: cs.primary),
                rightChevronIcon:
                    Icon(Icons.chevron_right, color: cs.primary),
              ),
              daysOfWeekHeight: 28,
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
                weekendStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.error.withValues(alpha: 0.7),
                ),
              ),
              onPageChanged: (focusedDay) => onMonthChanged(focusedDay),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  final key = DateTime(day.year, day.month, day.day);
                  return _CalendarCell(
                    day: day,
                    spending: spendingByDay[key] ?? 0,
                    accounts: accountsByDay[key] ?? const [],
                    maxSpending: maxSpending,
                    isToday: false,
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  final key = DateTime(day.year, day.month, day.day);
                  return _CalendarCell(
                    day: day,
                    spending: spendingByDay[key] ?? 0,
                    accounts: accountsByDay[key] ?? const [],
                    maxSpending: maxSpending,
                    isToday: true,
                  );
                },
                outsideBuilder: (context, day, focusedDay) {
                  return Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                  );
                },
              ),
              calendarStyle: const CalendarStyle(
                cellMargin: EdgeInsets.all(4),
                outsideDaysVisible: true,
              ),
            ),
          ),
          // Bank legend — only show banks present in this month
          if (banksInMonth.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.only(top: 16, bottom: 8),
              child: Wrap(
                spacing: 20,
                runSpacing: 10,
                children: (banksInMonth.toList()..sort())
                    .map((bank) => _BankLegendItem(bank: bank))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _BankLegendItem extends StatelessWidget {
  final String bank;
  const _BankLegendItem({required this.bank});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _colorForBank(bank),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          bank.replaceAll('_', ' '),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final DateTime day;
  final double spending;
  final List<AccountSpending> accounts;
  final double maxSpending;
  final bool isToday;

  const _CalendarCell({
    required this.day,
    required this.spending,
    required this.accounts,
    required this.maxSpending,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final intensity =
        maxSpending > 0 ? (spending / maxSpending).clamp(0.0, 1.0) : 0.0;
    final hasSplits = accounts.length > 1;

    // Build tooltip text with per-bank breakdown
    String tooltipText;
    if (spending > 0) {
      final buf = StringBuffer(
          '${DateFormat.MMMd().format(day)}\nTotal: ${_currencyFmt.format(spending)}\n(Click to view details)');
      if (accounts.isNotEmpty) {
        for (final a in accounts) {
          buf.write('\n${a.bank.replaceAll("_", " ")}: ${_currencyFmt.format(a.spending)}');
        }
      }
      tooltipText = buf.toString();
    } else {
      tooltipText = DateFormat.MMMd().format(day);
    }

    // Compute background color
    Color bgColor;
    if (spending > 0 && hasSplits) {
      // Blend bank colors weighted by spending share
      bgColor = _blendBankColors(accounts, spending, intensity);
    } else if (spending > 0 && accounts.isNotEmpty) {
      bgColor = Color.lerp(
        _colorForBank(accounts.first.bank).withValues(alpha: 0.15),
        _colorForBank(accounts.first.bank),
        intensity,
      )!;
    } else if (spending > 0) {
      bgColor = Color.lerp(
          Colors.red.shade50, Colors.red.shade600, intensity)!;
    } else {
      bgColor = Colors.transparent;
    }

    return Tooltip(
      message: tooltipText,
      child: GestureDetector(
        onTap: () {
          if (spending > 0) {
            _showDailyTransactions(context, day);
          }
        },
        child: MouseRegion(
          cursor: spending > 0 ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: spending > 0 && !hasSplits ? bgColor : null,
              borderRadius: BorderRadius.circular(8),
              border: isToday ? Border.all(color: cs.primary, width: 2.5) : null,
              gradient: spending > 0 && hasSplits
                  ? _buildBankGradient(accounts, spending, intensity)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: spending > 0 && intensity > 0.5
                    ? Colors.white
                    : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build a vertical linear gradient with bank color segments.
  LinearGradient _buildBankGradient(
      List<AccountSpending> accts, double total, double intensity) {
    final sorted = List<AccountSpending>.from(accts)
      ..sort((a, b) => b.spending.compareTo(a.spending));
    final opacity = 0.35 + intensity * 0.65;

    final colors = <Color>[];
    final stops = <double>[];
    double cumulative = 0;
    for (final a in sorted) {
      final fraction = total > 0 ? a.spending / total : 0.0;
      final color = _colorForBank(a.bank).withValues(alpha: opacity);
      colors.add(color);
      stops.add(cumulative);
      cumulative += fraction;
      colors.add(color);
      stops.add(cumulative.clamp(0.0, 1.0));
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    );
  }

  /// Blend bank colors for the overall cell tint.
  Color _blendBankColors(
      List<AccountSpending> accts, double total, double intensity) {
    double r = 0, g = 0, b = 0;
    for (final a in accts) {
      final w = total > 0 ? a.spending / total : 0.0;
      final c = _colorForBank(a.bank);
      r += (c.r * 255.0) * w;
      g += (c.g * 255.0) * w;
      b += (c.b * 255.0) * w;
    }
    return Color.fromRGBO(r.round(), g.round(), b.round(), 0.35 + intensity * 0.65);
  }

  void _showDailyTransactions(BuildContext context, DateTime date) {
    showDialog(
      context: context,
      builder: (context) => _DailyTransactionsPopup(date: date),
    );
  }
}

class _DailyTransactionsPopup extends ConsumerStatefulWidget {
  final DateTime date;

  const _DailyTransactionsPopup({required this.date});

  @override
  ConsumerState<_DailyTransactionsPopup> createState() =>
      _DailyTransactionsPopupState();
}

class _DailyTransactionsPopupState
    extends ConsumerState<_DailyTransactionsPopup> {
  late Future<List<UnifiedTransaction>> _txnFuture;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    // Ensure categories are available
    Future.microtask(() => ref.read(categoriesProvider.notifier).loadCategories());
  }

  void _loadTransactions() {
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    _txnFuture = ApiService.getUnifiedTransactions(
        from: dateStr, to: dateStr, limit: 100);
  }

  void _showCategoryDialog(UnifiedTransaction txn) async {
    final catState = ref.read(categoriesProvider);
    if (catState.categories.isEmpty) {
      await ref.read(categoriesProvider.notifier).loadCategories();
    }
    final categories = ref.read(categoriesProvider).categories;

    if (!mounted) return;

    final selected = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set Category'),
        children: categories
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.id),
                  child: Row(
                    children: [
                      _categoryDot(c),
                      const SizedBox(width: 10),
                      Text(c.name),
                      if (txn.categoryId == c.id) ...[
                        const Spacer(),
                        const Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (selected != null && txn.id != null) {
      await ApiService.updateTransaction(txn.id!, categoryId: selected);
      if (mounted) {
        setState(() => _loadTransactions());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category updated')),
        );
      }
    }
  }

  Widget _categoryDot(Category c) {
    final color = c.color != null ? _parseHexColor(c.color!) : Colors.grey;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.event,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Transactions on ${DateFormat.yMMMd().format(widget.date)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<UnifiedTransaction>>(
                future: _txnFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error loading transactions:\n${snapshot.error}',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final transactions = snapshot.data;
                  if (transactions == null || transactions.isEmpty) {
                    return const Center(
                        child: Text('No transactions recorded on this day.'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, index) {
                      final txn = transactions[index];
                      final isExpense =
                          txn.type == TransactionType.debit;

                      final typeColor = isExpense
                          ? Colors.red.shade600
                          : Colors.green.shade600;
                      final typeIcon = isExpense
                          ? Icons.arrow_outward
                          : Icons.arrow_back_ios_new;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child:
                              Icon(typeIcon, color: typeColor, size: 20),
                        ),
                        title: Text(
                          txn.description ?? 'Unknown',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (txn.bank ?? 'Unknown')
                                      .replaceAll('_', ' '),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (txn.category != null)
                                GestureDetector(
                                  onTap: () =>
                                      _showCategoryDialog(txn),
                                  child: _buildCategoryChip(
                                      context, txn.category!),
                                )
                              else
                                GestureDetector(
                                  onTap: () =>
                                      _showCategoryDialog(txn),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .disabledColor,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+ Category',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .disabledColor,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        trailing: Text(
                          _currencyFmt.format(txn.amount ?? 0),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: typeColor,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(BuildContext context, Category category) {
    final color = category.color != null
        ? _parseHexColor(category.color!)
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        category.name,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

