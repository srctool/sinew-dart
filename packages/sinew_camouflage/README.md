# sinew_camouflage

[![pub package](https://img.shields.io/pub/v/sinew_camouflage.svg)](https://pub.dev/packages/sinew_camouflage)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**`PagingState.toCamo()` for Camouflage's `CamoPagedList`.**

The glue between Sinew's paging and [Camouflage](https://pub.dev/packages/camouflage_core), the component library. One call turns a `PagingState` into what `CamoPagedList` shows: the skeleton, the items, load more, retry, refresh and the end of the list.

## Features

- `PagingState.toCamo(localizer)` and `toCamoOf(context)`, with every `PagingState` mapped by the rules in the Guide
- Error text rendered at build time with Sinew's localizer, so it follows the current language
- The only Sinew package that depends on Camouflage

## Getting started

```sh
flutter pub add sinew_camouflage
```

## Usage

```dart
CamoPagedList<Order>(
  state: state.orders.toCamoOf(context),
  itemKey: (order) => order.id,
  onLoadMore: () => onEvent(const OrderListEndReached()),
  onRetry: () => onEvent(const OrderListRetryTapped()),
  onRefresh: () async => onEvent(const OrderListRefreshed()),
  itemBuilder: (context, order, _) => CamoListItem(
    headline: order.title,
    supporting: order.status,
  ),
)
```

Only a next-page load or failure keeps the items: a refresh drops them, so the list shows its skeleton.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_paging`](https://pub.dev/packages/sinew_paging)
- [`sinew_l10n`](https://pub.dev/packages/sinew_l10n)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_camouflage](https://pub.dev/documentation/sinew_camouflage/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
