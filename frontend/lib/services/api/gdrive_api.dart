/// Google Drive sync API calls.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class GDriveApi {
  static String get _base => '${ApiClient.baseUrl}/api/v2/gdrive';

  /// Get Google Drive connection status.
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await http
        .get(Uri.parse('$_base/status'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to get Google Drive connection status: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Get the Google Drive OAuth2 authorization URL.
  static Future<String> getAuthUrl() async {
    final response = await http
        .get(Uri.parse('$_base/auth-url'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to get auth URL: $detail');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['auth_url'] as String;
  }

  /// Revoke credentials / disconnect Google Drive.
  static Future<Map<String, dynamic>> disconnect() async {
    final response = await http
        .post(Uri.parse('$_base/disconnect'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to disconnect Google Drive: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List folders inside a Google Drive folder (default is root).
  static Future<Map<String, dynamic>> listFolders({String? parentId}) async {
    final uri = Uri.parse('$_base/folders').replace(
      queryParameters: parentId != null ? {'parent_id': parentId} : null,
    );
    final response = await http
        .get(uri, headers: ApiClient.headers)
        .timeout(const Duration(seconds: 45));
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to list folders: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List PDF/CSV files in a specific Google Drive folder.
  static Future<Map<String, dynamic>> listFiles({required String folderId}) async {
    final uri = Uri.parse('$_base/files').replace(
      queryParameters: {'folder_id': folderId},
    );
    final response = await http
        .get(uri, headers: ApiClient.headers)
        .timeout(const Duration(seconds: 45));
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to list files: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Start a download/import background job.
  static Future<Map<String, dynamic>> startImport({
    required List<Map<String, String>> files,
    bool force = false,
    Map<String, String>? bankPasswords,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/import'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({
            'files': files,
            'force': force,
            if (bankPasswords != null && bankPasswords.isNotEmpty)
              'bank_passwords': bankPasswords,
          }),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to start import: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Poll progress of a background import job.
  static Future<Map<String, dynamic>> getImportStatus(String jobId) async {
    final response = await http
        .get(
          Uri.parse('$_base/import/$jobId'),
          headers: ApiClient.headers,
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode == 404) {
      throw Exception('Import job not found: $jobId');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to get import status: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Reset parsed state cache for specific file IDs or all files.
  static Future<Map<String, dynamic>> resetState({
    List<String>? fileIds,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/reset'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({'file_ids': fileIds}),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to reset state: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── Folder Configuration ──────────────────────────────────

  /// Fetch all saved folder → bank/type mappings.
  static Future<List<dynamic>> getFolderConfigs() async {
    final response = await http
        .get(Uri.parse('$_base/folder-configs'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch folder configs: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['configs'] as List<dynamic>;
  }

  /// Save or update the bank/type mapping for a folder.
  static Future<Map<String, dynamic>> setFolderConfig({
    required String folderId,
    required String folderName,
    required String bank,
    required String type,
    String label = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/folder-configs/$folderId'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({
            'folder_name': folderName,
            'bank': bank,
            'type': type,
            'label': label,
          }),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to save folder config: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Remove the bank/type mapping for a folder.
  static Future<void> deleteFolderConfig(String folderId) async {
    final response = await http
        .delete(
          Uri.parse('$_base/folder-configs/$folderId'),
          headers: ApiClient.headers,
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete folder config: ${response.statusCode}');
    }
  }
}
