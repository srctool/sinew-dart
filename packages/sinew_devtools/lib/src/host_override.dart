import 'package:flutter/foundation.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// The API Host page's choice: which of the app's [hosts] the clients send to
/// instead of their own base URL. The choice is remembered across restarts in
/// devtools' own namespace, and [select] with `null` resets it. Every entry
/// point sits behind `DevToolsGate.enabled`, so production builds never have
/// a host override.
final class HostOverride {
  /// Where the choice is kept, in devtools' own namespace.
  static const key = 'sinew.devtools.apiHost';

  final _hosts = ValueNotifier<List<String>>(const []);
  final _current = ValueNotifier<String?>(null);
  KeyValueStore? _store;

  /// The hosts the app lists, as base URLs
  /// (`https://staging.api.shop.com/v1`).
  ValueListenable<List<String>> get hosts => _hosts;

  /// The chosen host, or `null` for each client's own. The ribbon shows it.
  ValueListenable<String?> get current => _current;

  /// Sets the app's [hosts] and restores the host chosen before the restart
  /// from [store], if it's still listed. A stored host the app no longer
  /// lists is forgotten. Throws an [ArgumentError] for a host that isn't an
  /// `http` or `https` base URL.
  Future<void> configure(List<String> hosts, {KeyValueStore? store}) async {
    for (final host in hosts) {
      final uri = Uri.tryParse(host);
      if (uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https') ||
          uri.host.isEmpty) {
        throw ArgumentError.value(host, 'hosts', 'must be an http(s) base URL');
      }
    }
    _store = store;
    _hosts.value = List.unmodifiable(hosts.toSet());
    final saved = await store?.getString(key);
    _current.value = saved != null && hosts.contains(saved) ? saved : null;
    if (saved != null && !hosts.contains(saved)) await store?.remove(key);
  }

  /// Sends every client to [host] from the next request, or back to its own
  /// with `null`, and remembers it. Throws an [ArgumentError] for a host the
  /// app doesn't list.
  Future<void> select(String? host) async {
    if (host != null && !_hosts.value.contains(host)) {
      throw ArgumentError.value(host, 'host', "isn't a configured host");
    }
    _current.value = host;
    final store = _store;
    if (store == null) return;
    if (host == null) {
      await store.remove(key);
    } else {
      await store.setString(key, host);
    }
  }
}
