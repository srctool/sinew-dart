## 0.1.0-dev.1

- S3: the Dio interceptors, each installable alone: `SinewTimeoutInterceptor` (a total deadline by method that cancels with `DeadlineExceeded` on the request's own token, a request's `sinewDeadline` winning), `SinewHeadersInterceptor`, `SinewErrorBodyInterceptor` (attaches `HttpStatusError`) and `SinewLogInterceptor` with `HttpLogger`; and the optional `SinewHttp.dio(config)` preset. Redirects are the platform's own (dart:io and the browser drop `Authorization` across hosts), so there's no redirect interceptor.
- S3: `SinewConfig` (validated on construction; `locale` and `defaultHeaders` read per request), `TokenSource` with `RefreshOutcome` (`Refreshed`, `Rejected`, `Unavailable(cause)`) and the `clear()` contract, `ErrorBodyReader.standard` (reads `message` and `errors` from a decoded map or a JSON string) and `ErrorBodyReader.from`, and the unexported `HttpStatusError` with `Retry-After` in seconds or an IMF-fixdate.
- S0: package skeleton.
