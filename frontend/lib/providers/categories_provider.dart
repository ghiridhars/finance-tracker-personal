/// Provider for categories and tags.
library;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/category_models.dart';
import '../services/api_service.dart';

// ── Categories ──────────────────────────────────────────────

class CategoriesState {
  final List<Category> categories;
  final bool isLoading;
  final String? error;

  const CategoriesState({
    this.categories = const [],
    this.isLoading = false,
    this.error,
  });

  CategoriesState copyWith({
    List<Category>? categories,
    bool? isLoading,
    String? error,
  }) =>
      CategoriesState(
        categories: categories ?? this.categories,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class CategoriesNotifier extends Notifier<CategoriesState> {
  @override
  CategoriesState build() => const CategoriesState();

  Future<void> loadCategories() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final categories = await ApiService.getCategories();
      state = state.copyWith(categories: categories, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createCategory({
    required String name,
    String? icon,
    String? color,
    List<String> keywords = const [],
  }) async {
    try {
      await ApiService.createCategory(
        name: name,
        icon: icon,
        color: color,
        keywords: keywords,
      );
      await loadCategories();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteCategory(int categoryId) async {
    try {
      await ApiService.deleteCategory(categoryId);
      await loadCategories();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addKeywords(int categoryId, List<String> keywords) async {
    try {
      await ApiService.addCategoryKeywords(categoryId, keywords);
      await loadCategories();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final categoriesProvider =
    NotifierProvider<CategoriesNotifier, CategoriesState>(
        CategoriesNotifier.new);
