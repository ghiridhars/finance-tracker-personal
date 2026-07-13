import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_class.dart';
import '../services/api_service.dart';

final assetClassesProvider =
    AsyncNotifierProvider<AssetClassesNotifier, List<AssetClass>>(
  AssetClassesNotifier.new,
);

class AssetClassesNotifier extends AsyncNotifier<List<AssetClass>> {
  @override
  Future<List<AssetClass>> build() async {
    return await ApiService.getAssetClasses();
  }

  Future<void> addClass(String name, String colorHex, String iconName) async {
    try {
      final newClass = await ApiService.createAssetClass(name, colorHex, iconName);
      if (state.hasValue) {
        state = AsyncValue.data([...state.value!, newClass]);
      } else {
        ref.invalidateSelf();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateClass(int id, String name, String colorHex, String iconName) async {
    try {
      final updated = await ApiService.updateAssetClass(
        id, 
        name: name, 
        colorHex: colorHex, 
        iconName: iconName,
      );
      if (state.hasValue) {
        state = AsyncValue.data([
          for (final c in state.value!)
            if (c.id == id) updated else c
        ]);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteClass(int id) async {
    try {
      await ApiService.deleteAssetClass(id);
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.where((c) => c.id != id).toList());
      }
    } catch (e) {
      rethrow;
    }
  }
}
