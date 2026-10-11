## 0.1.0-dev.1

- S2: `LoadType`, `PagingState` (`canLoadMore`, `retryType`), the strategies behind `Pager.offset`, `offsetByTotal`, `cursor` and `lastItem`, and `Pager.load` (stale responses dropped by request id, `initial` once per query, a `CancelException` leaves the state unchanged, `itemKey` de-duplication) and `cancel()`.
- S0: package skeleton.
