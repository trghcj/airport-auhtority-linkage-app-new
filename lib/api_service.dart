import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class ApiService {
  // ✅ Use your live Flask backend URL here
  static const String baseUrl = "https://web-production-9b0d5.up.railway.app";

  final Dio _dio = Dio();

  /// 🔹 Upload departure Excel files
  Future<Map<String, dynamic>> uploadDepartureFiles(List<File> files) async {
    try {
      FormData formData = FormData();

      for (var file in files) {
        formData.files.add(MapEntry(
          'departure_files[]',
          await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
        ));
      }

      final response = await _dio.post(
        '$baseUrl/upload',
        data: formData,
        options: Options(headers: {
          'Content-Type': 'multipart/form-data',
        }),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error uploading files: $e');
    }
  }

  /// 🔹 Analyze base Excel file
  Future<Map<String, dynamic>> analyzeBaseFile(File file) async {
    try {
      FormData formData = FormData.fromMap({
        'base_file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
      });

      final response = await _dio.post(
        '$baseUrl/analyze',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Analyze failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error analyzing file: $e');
    }
  }

  /// 🔹 Search from Firestore data
  Future<List<dynamic>> searchData(String docId, String query) async {
    try {
      final response = await _dio.get(
        '$baseUrl/search',
        queryParameters: {'doc_id': docId, 'query': query},
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Search failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching data: $e');
    }
  }
}
