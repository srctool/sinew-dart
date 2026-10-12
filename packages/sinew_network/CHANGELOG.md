## 0.1.0-dev.1

- S3: `SinewConfig` (validated on construction; `locale` and `defaultHeaders` read per request), `TokenSource` with `RefreshOutcome` (`Refreshed`, `Rejected`, `Unavailable(cause)`) and the `clear()` contract, `ErrorBodyReader.standard` (reads `message` and `errors` from a decoded map or a JSON string) and `ErrorBodyReader.from`, and the unexported `HttpStatusError` with `Retry-After` in seconds or an IMF-fixdate.
- S0: package skeleton.
