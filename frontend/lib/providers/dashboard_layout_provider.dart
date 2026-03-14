/// Dashboard grid-layout configuration — 12-column grid with per-tile
/// column span, row height, ordering, and visibility. Persisted to SharedPreferences.
library;

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Tile identifiers ────────────────────────────────────────

enum DashboardTileId {
  summary,
  calendar,
  trends,
  categories,
  incomeExpense,
  monthOverMonth,
  topMerchants,
}

extension DashboardTileLabel on DashboardTileId {
  String get label => switch (this) {
        DashboardTileId.summary => 'Summary Cards',
        DashboardTileId.calendar => 'Spending Calendar',
        DashboardTileId.trends => 'Spending Trends',
        DashboardTileId.categories => 'Category Breakdown',
        DashboardTileId.incomeExpense => 'Income vs Expense',
        DashboardTileId.monthOverMonth => 'Month-over-Month',
        DashboardTileId.topMerchants => 'Top Merchants',
      };
}

// ── Grid constants ──────────────────────────────────────────

const int kGridColumns = 12;
const int kMinColSpan = 4;
const double kMinTileHeight = 120;
const double kMaxTileHeight = 800;

/// Height adjustment step in pixels for +/- buttons.
const double kHeightStep = 40;

/// Allowed column-span stops (snap points).
const List<int> kColSpanStops = [4, 6, 8, 12];

// ── Responsive breakpoints ──────────────────────────────────

enum ScreenTier { compact, medium, expanded }

ScreenTier screenTierFor(double width) {
  if (width < 600) return ScreenTier.compact;
  if (width < 1200) return ScreenTier.medium;
  return ScreenTier.expanded;
}

/// On compact screens every tile is full-width regardless of saved colSpan.
int effectiveColSpan(TileConfig tile, ScreenTier tier) {
  if (tier == ScreenTier.compact) return kGridColumns;
  return tile.colSpan;
}

// ── Per-tile config ─────────────────────────────────────────

class TileConfig {
  final DashboardTileId id;
  final bool visible;
  final int colSpan;
  final double height;

  const TileConfig({
    required this.id,
    this.visible = true,
    this.colSpan = kGridColumns,
    this.height = 300,
  });

  TileConfig copyWith({bool? visible, int? colSpan, double? height}) {
    return TileConfig(
      id: id,
      visible: visible ?? this.visible,
      colSpan: colSpan ?? this.colSpan,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id.name,
        'visible': visible,
        'colSpan': colSpan,
        'height': height,
      };

  factory TileConfig.fromJson(Map<String, dynamic> json) {
    return TileConfig(
      id: DashboardTileId.values.firstWhere(
        (e) => e.name == json['id'],
        orElse: () => DashboardTileId.summary,
      ),
      visible: json['visible'] ?? true,
      colSpan: (json['colSpan'] as int?) ?? kGridColumns,
      height: (json['height'] as num?)?.toDouble() ?? 300,
    );
  }
}

// ── Layout state ────────────────────────────────────────────

class DashboardLayoutState {
  final List<TileConfig> tiles;
  final bool isEditMode;

  const DashboardLayoutState({
    required this.tiles,
    this.isEditMode = false,
  });

  DashboardLayoutState copyWith({List<TileConfig>? tiles, bool? isEditMode}) {
    return DashboardLayoutState(
      tiles: tiles ?? this.tiles,
      isEditMode: isEditMode ?? this.isEditMode,
    );
  }
}

// ── Default order ───────────────────────────────────────────

const List<TileConfig> _defaultTiles = [
  TileConfig(id: DashboardTileId.summary, height: 200, colSpan: 12),
  TileConfig(id: DashboardTileId.calendar, height: 440, colSpan: 12),
  TileConfig(id: DashboardTileId.trends, height: 320, colSpan: 12),
  TileConfig(id: DashboardTileId.categories, height: 340, colSpan: 6),
  TileConfig(id: DashboardTileId.incomeExpense, height: 340, colSpan: 6),
  TileConfig(id: DashboardTileId.monthOverMonth, height: 280, colSpan: 6),
  TileConfig(id: DashboardTileId.topMerchants, height: 420, colSpan: 6),
];

// ── Notifier ────────────────────────────────────────────────

class DashboardLayoutNotifier extends Notifier<DashboardLayoutState> {
  static const _prefsKey = 'dashboard_layout';

  @override
  DashboardLayoutState build() {
    _loadFromPrefs();
    return const DashboardLayoutState(tiles: _defaultTiles);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final List<dynamic> list = jsonDecode(raw);
      final loaded = list.map((j) => TileConfig.fromJson(j)).toList();
      final seenIds = loaded.map((t) => t.id).toSet();
      final merged = [
        ...loaded,
        for (final d in _defaultTiles)
          if (!seenIds.contains(d.id)) d,
      ];
      state = state.copyWith(tiles: merged);
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = state.tiles.map((t) => t.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(json));
  }

  void toggleEditMode() =>
      state = state.copyWith(isEditMode: !state.isEditMode);

  void exitEditMode() {
    state = state.copyWith(isEditMode: false);
    _save();
  }

  void reorder(int oldIndex, int newIndex) {
    final tiles = List<TileConfig>.from(state.tiles);
    if (newIndex > oldIndex) newIndex--;
    final item = tiles.removeAt(oldIndex);
    tiles.insert(newIndex, item);
    state = state.copyWith(tiles: tiles);
  }

  void toggleVisibility(DashboardTileId id) {
    final tiles = state.tiles.map((t) {
      if (t.id == id) return t.copyWith(visible: !t.visible);
      return t;
    }).toList();
    state = state.copyWith(tiles: tiles);
  }

  void resizeTile(DashboardTileId id, {int? colSpan, double? height}) {
    final tiles = state.tiles.map((t) {
      if (t.id != id) return t;
      return t.copyWith(
        colSpan: colSpan?.clamp(kMinColSpan, kGridColumns),
        height: height?.clamp(kMinTileHeight, kMaxTileHeight),
      );
    }).toList();
    state = state.copyWith(tiles: tiles);
  }

  /// Cycle colSpan to the next snap stop.
  void widenTile(DashboardTileId id) {
    final tile = state.tiles.firstWhere((t) => t.id == id);
    final idx = kColSpanStops.indexWhere((s) => s > tile.colSpan);
    if (idx == -1) return; // already max
    resizeTile(id, colSpan: kColSpanStops[idx]);
  }

  /// Cycle colSpan to the previous snap stop.
  void narrowTile(DashboardTileId id) {
    final tile = state.tiles.firstWhere((t) => t.id == id);
    final idx = kColSpanStops.lastIndexWhere((s) => s < tile.colSpan);
    if (idx == -1) return; // already min
    resizeTile(id, colSpan: kColSpanStops[idx]);
  }

  /// Increase height by one step.
  void tallerTile(DashboardTileId id) {
    final tile = state.tiles.firstWhere((t) => t.id == id);
    resizeTile(id, height: tile.height + kHeightStep);
  }

  /// Decrease height by one step.
  void shorterTile(DashboardTileId id) {
    final tile = state.tiles.firstWhere((t) => t.id == id);
    resizeTile(id, height: tile.height - kHeightStep);
  }

  void resetToDefaults() {
    state = state.copyWith(tiles: _defaultTiles);
    _save();
  }
}

// ── Provider ────────────────────────────────────────────────

final dashboardLayoutProvider =
    NotifierProvider<DashboardLayoutNotifier, DashboardLayoutState>(
  DashboardLayoutNotifier.new,
);
