import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/pagination.dart';

void main() {
  test('fetchAllPages follows the API next link', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final page = options.uri.queryParameters['page'];
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: page == '2'
                  ? {
                      'count': 2,
                      'next': null,
                      'results': [
                        {'id': 2},
                      ],
                    }
                  : {
                      'count': 2,
                      'next': 'https://api.example.test/items/?page=2',
                      'results': [
                        {'id': 1},
                      ],
                    },
            ),
          );
        },
      ),
    );

    final items = await fetchAllPages(dio, '/items/');

    expect(items.map((item) => item['id']), [1, 2]);
  });
}
