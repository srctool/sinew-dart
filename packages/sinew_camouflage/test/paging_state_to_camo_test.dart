import 'package:camouflage_core/camouflage_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_camouflage/sinew_camouflage.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_l10n/sinew_l10n.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';

const _offline = NoInternetConnectionException(
  'ORD',
  ExceptionLayer.repository,
  'GO',
);
const _english = "You're offline. Check your connection and try again.";
const _indonesian = 'Kamu sedang offline. Periksa koneksimu lalu coba lagi.';
const _page = PagingDomain<String>(
  items: ['a', 'b'],
  meta: PagingMetaDomain(hasNextPage: true),
);
const _lastPage = PagingDomain<String>(items: ['a', 'b']);

final class _Formal implements Localizer {
  @override
  String? resolve(String key, Map<String, Object> args) => 'Anda offline.';
}

void _expectState(
  CamoPagedListState<String> actual, {
  List<String> items = const [],
  PagedLoad loading = PagedLoad.none,
  bool endReached = false,
  PagedError? error,
}) {
  expect(actual.items, items);
  expect(actual.loading, loading);
  expect(actual.endReached, endReached);
  expect(actual.error, error);
}

CamoPagedListState<String> _camo(
  ViewState<PagingDomain<String>> view,
  LoadType loadType, [
  Localizer? localizer,
]) => PagingState<String>(view: view, loadType: loadType).toCamo(localizer);

void main() {
  group('the mapping table', () {
    test('Loading + initial is the skeleton, without items', () {
      _expectState(
        _camo(const Loading(_page), LoadType.initial),
        loading: PagedLoad.initial,
      );
    });

    test('Loading + refresh drops the items', () {
      _expectState(
        _camo(const Loading(_page), LoadType.refresh),
        loading: PagedLoad.refresh,
      );
    });

    test('Loading + more keeps the items', () {
      _expectState(
        _camo(const Loading(_page), LoadType.more),
        items: _page.items,
        loading: PagedLoad.more,
      );
    });

    for (final type in LoadType.values) {
      test('Done + ${type.name} with a next page has not reached the end', () {
        _expectState(_camo(const Done(_page), type), items: _page.items);
      });

      test('Done + ${type.name} on the last page has reached the end', () {
        _expectState(
          _camo(const Done(_lastPage), type),
          items: _lastPage.items,
          endReached: true,
        );
      });
    }

    for (final type in [LoadType.initial, LoadType.refresh]) {
      test('Failed + ${type.name} is a first-page error, without items', () {
        _expectState(
          _camo(const Failed(_offline, data: _page), type),
          error: PagedError(
            message: '$_english (${_offline.code})',
            scope: PagedErrorScope.firstPage,
          ),
        );
      });
    }

    test('Failed + more is a next-page error that keeps the items', () {
      _expectState(
        _camo(const Failed(_offline, data: _page), LoadType.more),
        items: _page.items,
        error: PagedError(
          message: '$_english (${_offline.code})',
          scope: PagedErrorScope.nextPage,
        ),
      );
    });
  });

  group('edge cases', () {
    test('a new state starts as the initial skeleton', () {
      _expectState(
        const PagingState<String>().toCamo(null),
        loading: PagedLoad.initial,
      );
    });

    test('an empty first page has reached the end', () {
      _expectState(
        _camo(const Done(PagingDomain<String>()), LoadType.initial),
        endReached: true,
      );
    });

    test('Loading and Failed + more without data have no items', () {
      _expectState(
        _camo(const Loading(), LoadType.more),
        loading: PagedLoad.more,
      );
      expect(_camo(const Failed(_offline), LoadType.more).items, isEmpty);
    });
  });

  group('the error text', () {
    test('uses the localizer', () {
      expect(
        _camo(
          const Failed(_offline),
          LoadType.initial,
          _Formal(),
        ).error!.message,
        'Anda offline. (${_offline.code})',
      );
    });

    test('falls back to English without a localizer', () {
      expect(
        _camo(const Failed(_offline), LoadType.initial).error!.message,
        '$_english (${_offline.code})',
      );
    });
  });

  group('toCamoOf', () {
    Future<CamoPagedListState<String>> build(
      WidgetTester tester,
      Locale locale,
    ) async {
      late CamoPagedListState<String> state;
      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: SinewLocalizations.localizationsDelegates,
          child: Builder(
            builder: (context) {
              state = const PagingState<String>(view: Failed(_offline))
                  .toCamoOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      return state;
    }

    testWidgets('renders English', (tester) async {
      final state = await build(tester, const Locale('en'));
      expect(state.error!.message, '$_english (${_offline.code})');
    });

    testWidgets('renders Indonesian', (tester) async {
      final state = await build(tester, const Locale('id'));
      expect(state.error!.message, '$_indonesian (${_offline.code})');
    });
  });
}
