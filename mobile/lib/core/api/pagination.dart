import 'package:dio/dio.dart';

Future<List<dynamic>> fetchAllPages(
  Dio dio,
  String path, {
  Map<String, dynamic>? queryParameters,
}) async {
  final items = <dynamic>[];
  final visited = <String>{};
  String? next = path;
  Map<String, dynamic>? query = queryParameters;

  while (next != null && visited.add(next)) {
    final response = await dio.get(next, queryParameters: query);
    query = null;
    final data = response.data;
    if (data is List) {
      items.addAll(data);
      break;
    }
    if (data is! Map || data['results'] is! List) {
      break;
    }
    items.addAll(data['results'] as List);
    next = data['next'] as String?;
  }

  return items;
}
