import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import '../../models/asset_class.dart';

class AssetClassApi {
  static Future<List<AssetClass>> getAssetClasses() async {
    final response = await http
        .get(Uri.parse('${ApiClient.baseUrl}/api/v2/asset-classes'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((j) => AssetClass.fromJson(j)).toList();
    } else {
      throw Exception('Failed to load asset classes: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<AssetClass> createAssetClass(String name, String colorHex, String iconName) async {
    final response = await http
        .post(
          Uri.parse('${ApiClient.baseUrl}/api/v2/asset-classes'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({
            'name': name,
            'color_hex': colorHex,
            'icon_name': iconName,
          }),
        )
        .timeout(ApiClient.timeout);
        
    ApiClient.checkAuth(response);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return AssetClass.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create asset class: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<AssetClass> updateAssetClass(int id, {String? name, String? colorHex, String? iconName}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (colorHex != null) body['color_hex'] = colorHex;
    if (iconName != null) body['icon_name'] = iconName;

    final response = await http
        .put(
          Uri.parse('${ApiClient.baseUrl}/api/v2/asset-classes/$id'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(ApiClient.timeout);
        
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      return AssetClass.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update asset class: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<void> deleteAssetClass(int id) async {
    final response = await http
        .delete(
          Uri.parse('${ApiClient.baseUrl}/api/v2/asset-classes/$id'),
          headers: ApiClient.headers,
        )
        .timeout(ApiClient.timeout);
        
    ApiClient.checkAuth(response);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete asset class: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }
}
