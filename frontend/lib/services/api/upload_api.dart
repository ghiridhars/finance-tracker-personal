/// Upload-related API calls (PDF and CSV statement upload).
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_client.dart';

class UploadApi {
  /// Upload a PDF statement via the unified v2 endpoint.
  static Future<Map<String, dynamic>> uploadStatementV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
  }) async {
    final uri = Uri.parse(
      '${ApiClient.baseUrl}/api/v2/statements/upload'
      '?bank=$bank&type=$statementType&save=$save',
    );
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(ApiClient.headers);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
      contentType: MediaType('application', 'pdf'),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Upload failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Upload a CSV statement via the unified v2 endpoint.
  static Future<Map<String, dynamic>> uploadCsvStatementV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
  }) async {
    final uri = Uri.parse(
      '${ApiClient.baseUrl}/api/v2/statements/upload-csv'
      '?bank=$bank&type=$statementType&save=$save',
    );
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(ApiClient.headers);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
      contentType: MediaType('text', 'csv'),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Upload failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
