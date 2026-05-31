/// Local directory sync API calls.
///
/// Provides methods to configure a local directory path, list files,
/// start a batch scan/import, poll scan progress, and reset state.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class LocalSyncApi {
  static String get _base => '${ApiClient.baseUrl}/api/v2/local-sync';

  static Map<String, List<String>> _normalizeBankPasswords(
    Map<String, String>? bankPasswords,
  ) {
    final normalized = <String, List<String>>{};
    if (bankPasswords == null) return normalized;

    bankPasswords.forEach((bank, rawValue) {
      final seen = <String>{};
      final candidates = <String>[];

      for (final part in rawValue.split(RegExp(r'[\r\n,]+'))) {
        final candidate = part.trim();
        if (candidate.isEmpty || seen.contains(candidate)) continue;
        seen.add(candidate);
        candidates.add(candidate);
      }

      if (candidates.isNotEmpty) {
        normalized[bank] = candidates;
      }
    });

    return normalized;
  }

  /// Get current sync status and configuration.
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await http
        .get(Uri.parse('$_base/status'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to get sync status: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Configure the local directory path.
  static Future<Map<String, dynamic>> configurePath(String path) async {
    final response = await http
        .post(
          Uri.parse('$_base/configure'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({'path': path}),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to configure path: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List files in the configured (or specified) directory.
  static Future<Map<String, dynamic>> listFiles({String? path}) async {
    final uri = Uri.parse('$_base/files').replace(
      queryParameters: path != null ? {'path': path} : null,
    );
    final response = await http
        .get(uri, headers: ApiClient.headers)
        .timeout(const Duration(seconds: 60));
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to list files: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Start a scan/import job. Returns immediately with a job_id.
  static Future<Map<String, dynamic>> startScan({
    required List<Map<String, String>> files,
    bool force = false,
    Map<String, String>? bankPasswords,
  }) async {
    final normalizedPasswords = _normalizeBankPasswords(bankPasswords);

    final response = await http
        .post(
          Uri.parse('$_base/scan'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({
            'files': files,
            'force': force,
            if (normalizedPasswords.isNotEmpty)
              'bank_passwords': normalizedPasswords,
          }),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to start scan: $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Poll scan progress by job ID.
  static Future<Map<String, dynamic>> getScanStatus(String jobId) async {
    final response = await http
        .get(
          Uri.parse('$_base/scan/$jobId'),
          headers: ApiClient.headers,
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode == 404) {
      throw Exception('Job not found: $jobId');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to get scan status: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Reset sync state for specific files or all files.
  static Future<Map<String, dynamic>> resetState({
    List<String>? filepaths,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/reset'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({'filepaths': filepaths}),
        )
        .timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to reset state: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
