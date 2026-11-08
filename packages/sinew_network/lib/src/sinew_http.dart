import 'package:dio/dio.dart';

import 'auth_interceptor.dart';
import 'config.dart';
import 'hooks.dart';
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
  ///
  /// [hooks] are devtools' (`DevTools.httpHooks`), passed from `main` behind
  /// `DevToolsGate.enabled`: a recorder before the auth interceptor, and
  /// faults and the host override after it, so a forced 401 runs the real
  /// refresh. [SinewHttpHooks.none], the default, leaves every request alone.
  static Dio dio(
    SinewConfig config,
    TokenSource tokenSource, {
    HttpLogger logger = defaultHttpLogger,
    SinewHttpHooks hooks = SinewHttpHooks.none,
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
      SinewRecorderInterceptor(
        dio,
        hooks: hooks,
        defaults: config.defaultHeaders,
      ),
      SinewAuthInterceptor(
        dio,
        tokenSource: tokenSource,
        anonymousPaths: config.anonymousPaths,
      ),
      SinewHooksInterceptor(hooks: hooks),
      SinewErrorBodyInterceptor(reader: config.errorBodyReader),
      ...extraInterceptors,
      if (config.logHttp) SinewLogInterceptor(logger: logger),
    ]);
    hooks.attached(dio);
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

  /// Devtools' "Expire access token": the next request from [dio] that
  /// carries a token sends an invalid one instead, so the backend answers 401
  /// and the real refresh runs. Needs [SinewHooksInterceptor] on [dio], which
  /// the preset installs. Only devtools calls it.
  static void debugExpireToken(Dio dio) {
    for (final hooks in dio.interceptors.whereType<SinewHooksInterceptor>()) {
      hooks.expireNextToken();
    }
  }
}
