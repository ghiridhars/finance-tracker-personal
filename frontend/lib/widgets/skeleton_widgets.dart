/// Skeleton loading widgets — shimmer placeholders for loading states.
///
/// Reusable across dashboard, transaction list, accounts, and budget screens.
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer wrapper that applies loading animation to children.
class SkeletonShimmer extends StatelessWidget {
  final Widget child;
  const SkeletonShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
      child: child,
    );
  }
}

/// Skeleton placeholder line/rectangle.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton placeholder for a single transaction tile.
class SkeletonTransactionTile extends StatelessWidget {
  const SkeletonTransactionTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: const CircleAvatar(radius: 16, backgroundColor: Colors.white),
        title: const SkeletonBox(width: 160, height: 14),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(height: 4),
            SkeletonBox(width: 100, height: 11),
            SizedBox(height: 4),
            Row(
              children: [
                SkeletonBox(width: 70, height: 11),
                SizedBox(width: 8),
                SkeletonBox(width: 50, height: 16, borderRadius: 4),
              ],
            ),
          ],
        ),
        trailing: const SkeletonBox(width: 60, height: 14),
      ),
    );
  }
}

/// Skeleton for a list of transaction tiles.
class SkeletonTransactionList extends StatelessWidget {
  final int count;
  const SkeletonTransactionList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonTransactionTile(),
      ),
    );
  }
}

/// Skeleton placeholder for a summary card.
class SkeletonSummaryCard extends StatelessWidget {
  const SkeletonSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: 80, height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 120, height: 24),
            SizedBox(height: 4),
            SkeletonBox(width: 60, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Full dashboard skeleton with summary cards and chart placeholders.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Preset chips placeholder
          const Row(
            children: [
              SkeletonBox(width: 80, height: 32, borderRadius: 16),
              SizedBox(width: 6),
              SkeletonBox(width: 100, height: 32, borderRadius: 16),
              SizedBox(width: 6),
              SkeletonBox(width: 90, height: 32, borderRadius: 16),
            ],
          ),
          const SizedBox(height: 16),

          // Summary cards grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: List.generate(4, (_) => const SkeletonSummaryCard()),
          ),
          const SizedBox(height: 24),

          // Chart placeholder
          const SkeletonBox(width: double.infinity, height: 16),
          const SizedBox(height: 8),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 24),

          // Another chart
          const SkeletonBox(width: 140, height: 16),
          const SizedBox(height: 8),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for accounts list.
class SkeletonAccountsList extends StatelessWidget {
  final int count;
  const SkeletonAccountsList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    CircleAvatar(radius: 20, backgroundColor: Colors.white),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120, height: 14),
                        SizedBox(height: 4),
                        SkeletonBox(width: 80, height: 12),
                      ],
                    ),
                    Spacer(),
                    SkeletonBox(width: 80, height: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton for budget/goals section.
class SkeletonBudgetGoals extends StatelessWidget {
  const SkeletonBudgetGoals({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Month selector placeholder
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(width: 32, height: 32, borderRadius: 16),
              SizedBox(width: 16),
              SkeletonBox(width: 120, height: 20),
              SizedBox(width: 16),
              SkeletonBox(width: 32, height: 32, borderRadius: 16),
            ],
          ),
          const SizedBox(height: 16),

          // Budget progress bars
          ...List.generate(
            4,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          SkeletonBox(width: 100, height: 14),
                          Spacer(),
                          SkeletonBox(width: 70, height: 14),
                        ],
                      ),
                      SizedBox(height: 8),
                      SkeletonBox(
                          width: double.infinity,
                          height: 8,
                          borderRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
