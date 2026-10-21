import 'package:dio/dio.dart';

/// What Dio's browser adapter throws when a request fails to connect.
Object droppedConnection(RequestOptions options) =>
    DioException.connectionError(
      requestOptions: options,
      reason: 'The XMLHttpRequest onError callback was called',
    );
