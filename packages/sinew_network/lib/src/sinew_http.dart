import 'package:dio/dio.dart';

import 'auth_interceptor.dart';
import 'config.dart';
import 'interceptors.dart';
import 'token_source.dart';

/// The optional preset: a `Dio` with every Sinew interceptor from one
/// [SinewConfig]. Skip it to add only the interceptors an app needs to its own
/// `Dio`: [SinewTimeoutInterceptor], [SinewHeadersInterceptor],
/// [SinewAuthInterceptor], [SinewErrorBodyInterceptor] and
/// [SinewLogInterceptor].
///
/// Redirects are the platform's own: `dart:io` follows `GET` and `HEAD` up to
/// five hops and drops `Authorization` and `Cookie` on a hop to another host
/// or port, and the browser does the same under the Fetch standard. So there's
/// no redirect interceptor.
abstract final class SinewHttp {
  /// A `Dio` for [config]'s backend. API classes use paths **relative** to
  /// `baseUrl` (`get('orders')`): a leading `/` would replace `baseUrl`'s own
  /// path. The auth interceptor attaches [tokenSource]'s token to requests for
  /// `baseUrl`'s host, outside `config.anonymousPaths`, and refreshes once for
  /// any number of concurrent 401s. [extraInterceptors] run after Sinew's and
  /// before the log.
  static Dio dio(
    SinewConfig config,
    TokenSource tokenSource, {
    HttpLogger logger = defaultHttpLogger,
    List<Interceptor> extraInterceptors = const [],
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl.endsWith('/')
            ? config.baseUrl
            : '${config.baseUrl}/',
        connectTimeout: config.connectTimeout,
      ),
    );
    dio.interceptors.addAll([
      SinewTimeoutInterceptor(
        read: config.readTimeout,
        write: config.writeTimeout,
        connect: config.connectTimeout,
      ),
      SinewHeadersInterceptor(
        locale: config.locale,
        defaults: config.defaultHeaders,
      ),
      SinewAuthInterceptor(
        dio,
        tokenSource: tokenSource,
        anonymousPaths: config.anonymousPaths,
      ),
      SinewErrorBodyInterceptor(reader: config.errorBodyReader),
      ...extraInterceptors,
      if (config.logHttp) SinewLogInterceptor(logger: logger),
    ]);
    return dio;
  }

  /// Sign-out: answers requests waiting on [dio]'s running refresh with a 401
  /// at once, so nothing carries into the next session. Call it with
  /// `tokenSource.clear()`, which makes sure a refresh finishing late stores
  /// nothing.
  static void resetAuth(Dio dio) {
    for (final auth in dio.interceptors.whereType<SinewAuthInterceptor>()) {
      auth.reset();
    }
  }
}
