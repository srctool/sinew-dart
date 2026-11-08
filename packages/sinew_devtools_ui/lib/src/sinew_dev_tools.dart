import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sinew_devtools/sinew_devtools.dart';

import 'dashboard.dart';
import 'entries.dart';
import 'pages.dart';

/// A string only builds with devtools contain. `SinewDevTools` references it,
/// so CI searches a production build's compiled output for it: if it's
/// there, devtools code survived tree-shaking, and the build fails.
const devToolsMarker = 'sinew-devtools-included-7f3a';

/// devtools' own keys, in its own namespace.
const buttonXKey = 'sinew.devtools.button.x';

/// The floating button's vertical offset key.
const buttonYKey = 'sinew.devtools.button.y';

/// The developer tools around the app: wraps [child] with the launcher, the
/// dashboard and the ribbon. Put it in `main`, behind `DevToolsGate.enabled`,
/// so production builds tree-shake it away:
///
/// ```dart
/// runApp(DevToolsGate.enabled
///     ? SinewDevTools(sections: [productSection], ribbon: BuildRibbon(versionLabel), child: const App())
///     : const App());
/// ```
class SinewDevTools extends StatefulWidget {
  /// Devtools around [child].
  const SinewDevTools({
    required this.child,
    this.sections = const [],
    this.ribbon,
    this.launcher = const FloatingLauncher(),
    this.redaction,
    this.stores = const [],
    this.changelog,
    this.hosts = const [],
    this.showUncaughtErrors,
    this.preferences,
    super.key,
  });

  /// The app.
  final Widget child;

  /// The app's own sections, after Sinew's.
  final List<DevToolSection> sections;

  /// A label in a corner of every screen; the active host and "faults on"
  /// are added to it.
  final BuildRibbon? ribbon;

  /// How the dashboard opens.
  final DevToolsLauncher launcher;

  /// What the recorders hide: extend `Redaction.standard`. `null` keeps the
  /// standard rules.
  final Redaction? redaction;

  /// The stores to inspect: each `KeyValueStore` and `SecureStore` gets its
  /// own page (secure values masked), and any other `InspectableStore` is
  /// listed, read-only, under Local DB.
  final List<InspectableStore> stores;

  /// Text for the Changelog page, or `null` for none.
  final String? changelog;

  /// The API hosts a tester can switch to, as base URLs. Empty: no API Host
  /// page.
  final List<String> hosts;

  /// Whether an uncaught error pops up a card over the app. `null`: on
  /// except in debug, where the framework already shows it. Uncaught errors
  /// are always recorded.
  final bool? showUncaughtErrors;

  /// devtools' own key-value store: the floating button's position and the
  /// chosen API host are remembered there. `null`: nothing is remembered.
  final KeyValueStore? preferences;

  @override
  State<SinewDevTools> createState() => _SinewDevToolsState();
}

class _SinewDevToolsState extends State<SinewDevTools> {
  @override
  void initState() {
    super.initState();
    DevTools.captureUncaughtErrors();
    _apply();
  }

  @override
  void didUpdateWidget(SinewDevTools old) {
    super.didUpdateWidget(old);
    _apply();
  }

  void _apply() {
    final redaction = widget.redaction ?? Redaction.standard;
    DevTools.network.redaction = redaction;
    DevTools.exceptions.redaction = redaction;
    DevTools.hosts.configure(widget.hosts, store: widget.preferences);
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      sinewSection(
        stores: widget.stores,
        changelog: widget.changelog,
        hasHosts: widget.hosts.isNotEmpty,
      ),
      ...widget.sections,
    ];
    final showUncaught = widget.showUncaughtErrors ?? !kDebugMode;
    // Above MaterialApp, there's no Directionality or MediaQuery yet.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery.fromView(
        view: View.of(context),
        child: ValueListenableBuilder(
          valueListenable: DevTools.isOpen,
          builder: (context, open, _) => Stack(
            // The marker, kept in every build that contains devtools.
            key: const ValueKey(devToolsMarker),
            children: [
              Positioned.fill(child: widget.child),
              _Ribbon(widget.ribbon),
              if (widget.launcher is FloatingLauncher && !open)
                _FloatingButton(
                  (widget.launcher as FloatingLauncher).initialAlignment,
                  widget.preferences,
                ),
              if (showUncaught && !open) const _UncaughtErrorCard(),
              if (open)
                Positioned.fill(
                  child: Dashboard(sections: sections, onClose: DevTools.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sinew's own section, always first.
DevToolSection sinewSection({
  required List<InspectableStore> stores,
  required String? changelog,
  required bool hasHosts,
}) {
  final keyValue = stores.whereType<KeyValueStore>();
  final secure = stores.whereType<SecureStore>();
  final other = stores
      .where((s) => s is! KeyValueStore && s is! SecureStore)
      .toList();
  return DevToolSection('Sinew', [
    DevToolPage(
      name: 'Network Monitor',
      description: 'Requests, redacted when recorded',
      actions: const [NetworkMonitorClear()],
      builder: (_) => const NetworkMonitorPage(),
    ),
    DevToolPage(
      name: 'Exception Log',
      description: 'Reported and uncaught errors',
      actions: const [ExceptionLogClear()],
      builder: (_) => const ExceptionLogPage(),
    ),
    for (final store in keyValue)
      DevToolPage(
        name: 'Key-Value Store',
        description: store.name,
        builder: (_) => KeyValueStorePage(store),
      ),
    for (final store in secure)
      DevToolPage(
        name: 'Secure Store',
        description: store.name,
        builder: (_) => SecureStorePage(store),
      ),
    if (other.isNotEmpty)
      DevToolGroup(
        name: 'Local DB',
        description: 'Read-only',
        children: [
          for (final store in other)
            DevToolPage(
              name: store.name,
              builder: (_) => InspectableStorePage(store),
            ),
        ],
      ),
    DevToolAction(
      name: 'Expire Access Token',
      description: 'The next request sends an invalid token',
      confirm:
          'The next request that carries a token sends an invalid one, so '
          'the real refresh runs.',
      run: () async => DevTools.expireAccessToken(),
    ),
    DevToolPage(
      name: 'Fault Injection',
      description: 'Force errors, delays and dropped connections',
      builder: (_) => const FaultInjectionPage(),
    ),
    if (hasHosts)
      DevToolPage(
        name: 'API Host',
        description: 'Send every client to another backend',
        builder: (_) => const ApiHostPage(),
      ),
    if (changelog != null)
      DevToolPage(name: 'Changelog', builder: (_) => ChangelogPage(changelog)),
  ]);
}

/// A ready menu row that opens the dashboard, for [MenuLauncher]: place it
/// in a settings page or a drawer, behind `DevToolsGate.enabled`.
class DevToolsMenuItem extends StatelessWidget {
  /// The row.
  const DevToolsMenuItem({super.key});

  @override
  Widget build(BuildContext context) => const ListTile(
    key: ValueKey('sinew-devtools-menu-item'),
    leading: CircleAvatar(child: Text('D')),
    title: Text('Developer tools'),
    subtitle: Text('Network, exceptions, stores, faults'),
    onTap: DevTools.open,
  );
}

/// The build label, the active host and "faults on", in the top-right
/// corner of every screen.
class _Ribbon extends StatelessWidget {
  const _Ribbon(this.ribbon);

  final BuildRibbon? ribbon;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DevTools.hosts.current,
    builder: (context, host, _) => ValueListenableBuilder(
      valueListenable: DevTools.faults.active,
      builder: (context, faults, _) {
        final parts = [
          ?ribbon?.label,
          if (host != null) Uri.tryParse(host)?.host ?? host,
          if (faults.isNotEmpty) 'faults on',
        ];
        if (parts.isEmpty) return const SizedBox.shrink();
        return Positioned(
          top: MediaQuery.paddingOf(context).top + 4,
          right: 4,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('sinew-devtools-ribbon'),
              decoration: BoxDecoration(
                color: faults.isNotEmpty
                    ? const Color(0xCCB3261E)
                    : const Color(0xAA000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  parts.join(' · '),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Draggable; a tap opens the dashboard and a drag never does. Its position
/// is remembered in [preferences].
class _FloatingButton extends StatefulWidget {
  const _FloatingButton(this.alignment, this.preferences);

  final Alignment alignment;
  final KeyValueStore? preferences;

  @override
  State<_FloatingButton> createState() => _FloatingButtonState();
}

class _FloatingButtonState extends State<_FloatingButton> {
  var _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = widget.preferences;
    if (prefs == null) return;
    final x = await prefs.getDouble(buttonXKey);
    final y = await prefs.getDouble(buttonYKey);
    if (x != null && y != null && mounted) {
      setState(() => _offset = Offset(x, y));
    }
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: widget.alignment,
          child: Transform.translate(
            offset: _offset,
            child: GestureDetector(
              key: const ValueKey('sinew-devtools-button'),
              onTap: DevTools.open,
              onPanUpdate: (d) => setState(() => _offset += d.delta),
              onPanEnd: (_) {
                widget.preferences?.setDouble(buttonXKey, _offset.dx);
                widget.preferences?.setDouble(buttonYKey, _offset.dy);
              },
              child: const SizedBox.square(
                dimension: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF3D3D3D),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(blurRadius: 6, color: Color(0x55000000)),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'DEV',
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A card over the app when an uncaught error is recorded, until it's
/// dismissed.
class _UncaughtErrorCard extends StatefulWidget {
  const _UncaughtErrorCard();

  @override
  State<_UncaughtErrorCard> createState() => _UncaughtErrorCardState();
}

class _UncaughtErrorCardState extends State<_UncaughtErrorCard> {
  (int, int)? _dismissed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DevTools.exceptions.records,
    builder: (context, rows, _) {
      ExceptionRecord? latest;
      for (final row in rows) {
        if (row.source == ExceptionSource.uncaught) {
          latest = row;
          break;
        }
      }
      if (latest == null || _dismissed == (latest.id, latest.count)) {
        return const SizedBox.shrink();
      }
      final row = latest;
      return Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
        child: Material(
          key: const ValueKey('sinew-devtools-uncaught'),
          color: const Color(0xFFF9DEDC),
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uncaught ${row.type}${row.count > 1 ? ' ×${row.count}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (row.message.isNotEmpty) Text(row.message, maxLines: 3),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() => _dismissed = (row.id, row.count));
                        DevTools.open();
                      },
                      child: const Text('Open log'),
                    ),
                    TextButton(
                      key: const ValueKey('uncaught-dismiss'),
                      onPressed: () =>
                          setState(() => _dismissed = (row.id, row.count)),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
