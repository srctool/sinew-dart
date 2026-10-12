import 'package:dio/dio.dart';

import 'config.dart';
import 'interceptors.dart';

/// The optional preset: a `Dio` with every Sinew interceptor from one
/// [SinewConfig]. Skip it to add only the interceptors an app needs to its own
/// `Dio`: [SinewTimeoutInterceptor], [SinewHeadersInterceptor],
/// [SinewErrorBodyInterceptor] and [SinewLogInterceptor].
///
/// Redirects are the platform's own: `dart:io` follows `GET` and `HEAD` up to
/// five hops and drops `Authorization` and `Cookie` on a hop to another host
/// or port, and the browser does the same under the Fetch standard. So there's
/// no redirect interceptor.
abstract final class SinewHttp {
  /// A `Dio` for [config]'s backend. API classes use paths **relative** to
  /// `baseUrl` (`get('orders')`): a leading `/` would replace `baseUrl`'s own
  /// path. [extraInterceptors] run after Sinew's and before the log.
  static Dio dio(
    SinewConfig config, {
    HttpLogger logger = defaultHttpLogger,
    List<Interceptor> extraInterceptors = const [],
  }) =>
      Dio(
          BaseOptions(
            baseUrl: config.baseUrl.endsWith('/')
                ? config.baseUrl
                : '${config.baseUrl}/',
            connectTimeout: config.connectTimeout,
          ),
        )
        ..interceptors.addAll([
          SinewTimeoutInterceptor(
            read: config.readTimeout,
            write: config.writeTimeout,
            connect: config.connectTimeout,
          ),
          SinewHeadersInterceptor(
            locale: config.locale,
            defaults: config.defaultHeaders,
          ),
          SinewErrorBodyInterceptor(reader: config.errorBodyReader),
          ...extraInterceptors,
          if (config.logHttp) SinewLogInterceptor(logger: logger),
        ]);
}
