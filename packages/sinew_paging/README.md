# sinew_paging

[![pub package](https://img.shields.io/pub/v/sinew_paging.svg)](https://pub.dev/packages/sinew_paging)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**`Pager`, `PagingState` and `LoadType`: the paging rules in one place.**

A list needs the same rules in every screen: load the first page once per query, load more only when there is a next page, retry the load that failed, and let a refresh replace what is running. `Pager` holds those rules, and holds no UI state: it reads the current state and writes the next one.

## Features

- Four strategies for four backends: `Pager.offset`, `Pager.offsetByTotal`, `Pager.cursor` and `Pager.lastItem`
- `PagingState` with `canLoadMore` and `retryType`, so the UI never decides "may I load more" itself
- `LoadType` (`initial`, `refresh`, `more`) stays set after a load, so the UI can tell a first-page failure from a next-page failure
- Stale loads are dropped: a newer load, or a refresh, supersedes whatever is running

## Getting started

```sh
dart pub add sinew_paging
```

## Usage

```dart
final pager = Pager<Order>.offset(
  (page, query) => repository.orders(page),
  itemKey: (order) => order.id,
);
var state = const PagingState<Order>();

await pager.load(LoadType.initial, state, update: (next) => state = next);
while (state.canLoadMore) {
  await pager.load(LoadType.more, state, update: (next) => state = next);
}
```

In a real page, `update` writes the state your notifier or view model owns. The full program is in [example/main.dart](example/main.dart).

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_models`](https://pub.dev/packages/sinew_models)
- [`sinew_camouflage`](https://pub.dev/packages/sinew_camouflage)
- [`sinew_testing`](https://pub.dev/packages/sinew_testing)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_paging](https://pub.dev/documentation/sinew_paging/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
