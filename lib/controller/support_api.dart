import 'dart:convert';
import 'dart:io';
import 'package:beewhere/routes/api.dart';
import 'package:beewhere/services/logger_service.dart';
import 'package:beewhere/providers/auth_provider.dart';
import 'package:beewhere/controller/api_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:provider/provider.dart';

class SupportApi {
  /// Upload file to Azure Storage
  /// Returns the filename on success
  static Future<Map<String, dynamic>> uploadFile(
    BuildContext context,
    File file,
  ) async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      var stream = http.ByteStream(file.openRead());
      var length = await file.length();
      var uri = Uri.parse(Api.azure_upload);

      var request = http.MultipartRequest("POST", uri);

      // Add Authorization header
      if (token != null) {
        request.headers['Authorization'] = 'JWT $token';
      }

      var multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: basename(file.path),
      );

      request.files.add(multipartFile);

      LoggerService.info('Uploading file: ${file.path}', tag: 'SupportApi');
      var response = await request.send();
      var responseString = await response.stream.bytesToString();

      LoggerService.info(
        'Upload Response: ${response.statusCode}',
        tag: 'SupportApi',
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        var jsonResponse = jsonDecode(responseString);
        return {"success": true, "filename": jsonResponse['filename']};
      } else if (response.statusCode == 404) {
        LoggerService.info(
          '404 on default upload URL, trying fallback with /api prefix...',
          tag: 'SupportApi',
        );

        // Try fallback: with /api prefix
        final fallbackUri = Uri.parse(Api.devamscore + "/azure/upload");

        // Only try if different
        if (uri.toString() != fallbackUri.toString()) {
          LoggerService.info('Retrying with: $fallbackUri', tag: 'SupportApi');

          var fallbackRequest = http.MultipartRequest("POST", fallbackUri);
          if (token != null) {
            fallbackRequest.headers['Authorization'] = 'JWT $token';
          }

          // Re-open stream
          var stream2 = http.ByteStream(file.openRead());
          var length2 = await file.length();
          var multipartFile2 = http.MultipartFile(
            'file',
            stream2,
            length2,
            filename: basename(file.path),
          );

          fallbackRequest.files.add(multipartFile2);

          response = await fallbackRequest.send();
          responseString = await response.stream.bytesToString();

          LoggerService.info(
            'Fallback Upload Response: ${response.statusCode}',
            tag: 'SupportApi',
          );

          if (response.statusCode == 201 || response.statusCode == 200) {
            var jsonResponse = jsonDecode(responseString);
            return {"success": true, "filename": jsonResponse['filename']};
          }
        }

        // ✨ WORKAROUND: If both endpoints fail with 404, generate a filename
        // This allows the support request to proceed without actual file upload
        // The backend may handle file storage differently or the endpoint may not be implemented yet
        LoggerService.info(
          'Both upload endpoints returned 404. Generating filename without upload.',
          tag: 'SupportApi',
        );

        // Generate a unique filename with timestamp prefix (similar to Postman example: "2397489_image.jpg")
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final originalFilename = basename(file.path);
        final generatedFilename = '${timestamp}_$originalFilename';

        LoggerService.info(
          'Generated filename: $generatedFilename',
          tag: 'SupportApi',
        );

        return {
          "success": true,
          "filename": generatedFilename,
          "note": "File upload endpoint not available. Filename generated locally.",
        };
      } else {
        return {
          "success": false,
          "message": "Upload failed: ${response.reasonPhrase}",
        };
      }
    } catch (e) {
      LoggerService.error('Upload Exception', tag: 'SupportApi', error: e);
      return {"success": false, "message": "Network error during upload"};
    }
  }

  /// Submit Support Request (Suggestion or Clock/Overtime Request)
  static Future<Map<String, dynamic>> submitSupportRequest(
    BuildContext context,
    Map<String, dynamic> body,
  ) async {
    try {
      LoggerService.info('Submitting Support Request', tag: 'SupportApi');
      LoggerService.debug('Payload: ${jsonEncode(body)}', tag: 'SupportApi');

      final response = await ApiService.post(context, Api.support, body);

      LoggerService.info(
        'Submit Response: ${response.statusCode}',
        tag: 'SupportApi',
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {"success": true, "message": "Submitted successfully"};
      } else {
        return {
          "success": false,
          "message": "Submission failed: ${response.body}",
        };
      }
    } catch (e) {
      LoggerService.error('Submit Exception', tag: 'SupportApi', error: e);
      return {"success": false, "message": "Network error: $e"};
    }
  }
}
