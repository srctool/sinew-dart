import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:sinew_devtools/sinew_devtools.dart';

import 'dashboard.dart';
import 'entries.dart';

const _safeMethods = {'GET', 'HEAD', 'OPTIONS'};

String _path(String url) {
  final uri = Uri.tryParse(url);
  return uri == null || uri.path.isEmpty ? url : uri.path;
}

// Network Monitor

/// The Network Monitor: the redacted records, newest first.
class NetworkMonitorPage extends StatelessWidget {
  /// The page.
  const NetworkMonitorPage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DevTools.network.records,
    builder: (context, records, _) {
      if (records.isEmpty) return const EmptyText('No requests yet');
      return ListView(
        key: const ValueKey('network-list'),
        children: [
          for (final record in records) ...[
            ListTile(
              key: ValueKey('network-record:${record.id}'),
              title: Text(
                '${record.method} ${_path(record.url)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_summary(record)),
                  if (record.isReplay) const _Chip('replay'),
                  if (record.cacheSource != null)
                    _Chip('cache · ${record.cacheSource}'),
                ],
              ),
              onTap: () => pushPage(
                context,
                DevToolPage(
                  name: '${record.method} ${_path(record.url)}',
                  builder: (_) => NetworkDetailPage(record),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      );
    },
  );

  static String _summary(NetworkRecord record) => [
    record.status?.toString() ?? record.errorType ?? 'no response',
    if (record.duration != null) '${record.duration!.inMilliseconds} ms',
    if (Uri.tryParse(record.url)?.host case final host? when host.isNotEmpty)
      host,
  ].join(' · ');
}

/// The Network Monitor's "Clear".
class NetworkMonitorClear extends StatelessWidget {
  /// The button.
  const NetworkMonitorClear({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('network-clear'),
    onPressed: DevTools.network.clear,
    child: const Text('Clear'),
  );
}

/// One record: the redacted exchange, Copy, Copy as cURL, and Replay.
class NetworkDetailPage extends StatefulWidget {
  /// The page for [record].
  const NetworkDetailPage(this.record, {super.key});

  /// The record.
  final NetworkRecord record;

  @override
  State<NetworkDetailPage> createState() => _NetworkDetailPageState();
}

class _NetworkDetailPageState extends State<NetworkDetailPage> {
  String? _note;

  Future<void> _copy(String text, String note) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _note = note);
  }

  Future<void> _replay() async {
    final record = widget.record;
    if (!_safeMethods.contains(record.method) &&
        !await confirmFirst(
          context,
          title: 'Send ${record.method} again?',
          text:
              'Send ${record.method} ${_path(record.url)} again? '
              'It may repeat what it did.',
          confirm: 'Send',
        )) {
      return;
    }
    String note;
    try {
      await DevTools.replay(record);
      note = 'Replayed: the result is at the top of the list';
    } on ArgumentError catch (e) {
      note = '${e.message}';
    } on StateError catch (e) {
      note = e.message;
    }
    if (mounted) setState(() => _note = note);
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final canReplay = DevTools.canReplay(record);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('network-copy'),
                onPressed: () => _copy(record.asText(), 'Copied'),
                child: const Text('Copy'),
              ),
              OutlinedButton(
                key: const ValueKey('network-curl'),
                onPressed: () => _copy(record.asCurl(), 'Copied as cURL'),
                child: const Text('Copy as cURL'),
              ),
              OutlinedButton(
                key: const ValueKey('network-replay'),
                onPressed: canReplay ? _replay : null,
                child: const Text('Replay'),
              ),
            ],
          ),
        ),
        if (!canReplay)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Can't replay: ${whyNotReplayable(record)}",
              key: const ValueKey('network-replay-reason'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_note!, key: const ValueKey('network-note')),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Mono(record.asText()),
          ),
        ),
      ],
    );
  }
}

/// Why a record can't be sent again, in the page's words.
String whyNotReplayable(NetworkRecord record) {
  final body = record.requestBody;
  if (record.fromCache) return 'it was served from the cache';
  if (!record.replayable &&
      (body is BinaryBody || (body is TextBody && body.truncated))) {
    return "its body wasn't kept whole";
  }
  if (!record.replayable) return 'a secret in it was hidden';
  return 'the record was cleared';
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

// Exception Log

/// The Exception Log: rows newest first, repeats merged.
class ExceptionLogPage extends StatelessWidget {
  /// The page.
  const ExceptionLogPage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DevTools.exceptions.records,
    builder: (context, rows, _) {
      if (rows.isEmpty) return const EmptyText('No exceptions yet');
      return ListView(
        key: const ValueKey('exception-list'),
        children: [
          for (final row in rows) ...[
            ListTile(
              key: ValueKey('exception-row:${row.id}'),
              title: Text(
                row.count > 1 ? '${row.type} ×${row.count}' : row.type,
              ),
              subtitle: Text(
                [
                  ?row.code,
                  if (row.message.isNotEmpty) row.message,
                ].join(' · '),
                maxLines: 2,
              ),
              trailing: Text(row.source.name),
              onTap: () => pushPage(
                context,
                DevToolPage(
                  name: row.type,
                  builder: (_) => _ExceptionDetailPage(row),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      );
    },
  );
}

/// The Exception Log's "Clear".
class ExceptionLogClear extends StatelessWidget {
  /// The button.
  const ExceptionLogClear({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('exception-clear'),
    onPressed: DevTools.exceptions.clear,
    child: const Text('Clear'),
  );
}

class _ExceptionDetailPage extends StatefulWidget {
  const _ExceptionDetailPage(this.row);

  final ExceptionRecord row;

  @override
  State<_ExceptionDetailPage> createState() => _ExceptionDetailPageState();
}

class _ExceptionDetailPageState extends State<_ExceptionDetailPage> {
  var _copied = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            OutlinedButton(
              key: const ValueKey('exception-copy'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: widget.row.asText()),
                );
                if (mounted) setState(() => _copied = true);
              },
              child: const Text('Copy'),
            ),
            if (_copied)
              const Padding(padding: EdgeInsets.all(8), child: Text('Copied')),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Mono(widget.row.asText()),
        ),
      ),
    ],
  );
}

// Stores

typedef _Row = ({String key, String? value});

/// A store's rows, loaded from [load], with [row] for each.
class _StoreList extends StatelessWidget {
  const _StoreList({
    required this.rows,
    required this.empty,
    required this.row,
  });

  final List<_Row>? rows;
  final String empty;
  final Widget Function(_Row row) row;

  @override
  Widget build(BuildContext context) {
    final rows = this.rows;
    if (rows == null) return const EmptyText('Loading…');
    if (rows.isEmpty) return EmptyText(empty);
    return ListView(
      children: [
        for (final r in rows) ...[row(r), const Divider(height: 1)],
      ],
    );
  }
}

Future<List<_Row>> _load(
  InspectableStore store, [
  String? Function(String?)? show,
]) async => [
  for (final key in await store.keys())
    (key: key, value: (show ?? (v) => v)(await store.read(key))),
];

/// The Key-Value Store page: values shown; editing and deleting ask first.
class KeyValueStorePage extends StatefulWidget {
  /// The page for [store].
  const KeyValueStorePage(this.store, {super.key});

  /// The store.
  final KeyValueStore store;

  @override
  State<KeyValueStorePage> createState() => _KeyValueStorePageState();
}

class _KeyValueStorePageState extends State<KeyValueStorePage> {
  List<_Row>? _rows;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await _load(widget.store);
    if (mounted) setState(() => _rows = rows);
  }

  /// Writes [text] to [key] as the type it already has, or returns why it
  /// can't.
  Future<String?> _writeAs(String key, String text) async {
    final store = widget.store;
    if (await store.getInt(key) != null) {
      final v = int.tryParse(text);
      if (v == null) return 'Not a whole number';
      await store.setInt(key, v);
    } else if (await store.getBool(key) != null) {
      final v = bool.tryParse(text);
      if (v == null) return 'Not true or false';
      await store.setBool(key, v);
    } else if (await store.getDouble(key) != null) {
      final v = double.tryParse(text);
      if (v == null) return 'Not a number';
      await store.setDouble(key, v);
    } else {
      await store.setString(key, text);
    }
    return null;
  }

  Future<void> _edit(_Row row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDialog(row: row, write: _writeAs),
    );
    if (saved ?? false) await _reload();
  }

  Future<void> _delete(_Row row) async {
    if (!await confirmFirst(
      context,
      title: 'Delete ${row.key}?',
      text:
          'This removes it from ${widget.store.name}. The app may behave as '
          'if it were never set.',
      confirm: 'Delete',
    )) {
      return;
    }
    await widget.store.remove(row.key);
    await _reload();
  }

  @override
  Widget build(BuildContext context) => _StoreList(
    rows: _rows,
    empty: '${widget.store.name} is empty',
    row: (row) => ListTile(
      key: ValueKey('kv-row:${row.key}'),
      title: Text(row.key),
      subtitle: Mono(row.value ?? 'null'),
      trailing: TextButton(
        key: ValueKey('kv-delete:${row.key}'),
        onPressed: () => _delete(row),
        child: const Text('Delete'),
      ),
      onTap: () => _edit(row),
    ),
  );
}

/// Edits one value; owns its text controller, so it outlives the dialog's
/// closing animation.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.row, required this.write});

  final _Row row;
  final Future<String?> Function(String key, String text) write;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: widget.row.value ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.row.key}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('kv-edit-field'),
          controller: _controller,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        key: const ValueKey('sinew-devtools-dismiss'),
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const ValueKey('sinew-devtools-confirm'),
        onPressed: () async {
          final problem = await widget.write(widget.row.key, _controller.text);
          if (!context.mounted) return;
          if (problem == null) {
            Navigator.of(context).pop(true);
          } else {
            setState(() => _error = problem);
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

/// The Secure Store page: every value **masked** to its last 4 characters
/// and its length, and never copyable, since QA devices get shared and
/// screens get recorded. "Clear all" asks first.
class SecureStorePage extends StatefulWidget {
  /// The page for [store].
  const SecureStorePage(this.store, {super.key});

  /// The store.
  final SecureStore store;

  @override
  State<SecureStorePage> createState() => _SecureStorePageState();
}

class _SecureStorePageState extends State<SecureStorePage> {
  List<_Row>? _rows;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await _load(
      widget.store,
      (v) => v == null ? null : Redaction.maskSecret(v),
    );
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _clear() async {
    if (!await confirmFirst(
      context,
      title: 'Clear ${widget.store.name}?',
      text:
          "This deletes every value in it, the session included. It can't be "
          'undone.',
      confirm: 'Clear all',
    )) {
      return;
    }
    await widget.store.clearUserData();
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Masked: last 4 characters and length. Never copyable.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              key: const ValueKey('secure-clear'),
              onPressed: (_rows?.isNotEmpty ?? false) ? _clear : null,
              child: const Text('Clear all'),
            ),
          ],
        ),
      ),
      Expanded(
        child: _StoreList(
          rows: _rows,
          empty: '${widget.store.name} is empty',
          row: (row) => ListTile(
            key: ValueKey('secure-row:${row.key}'),
            title: Text(row.key),
            subtitle: Mono(row.value ?? 'null'),
          ),
        ),
      ),
    ],
  );
}

/// A store the app registered for the Local DB group: read-only.
class InspectableStorePage extends StatefulWidget {
  /// The page for [store].
  const InspectableStorePage(this.store, {super.key});

  /// The store.
  final InspectableStore store;

  @override
  State<InspectableStorePage> createState() => _InspectableStorePageState();
}

class _InspectableStorePageState extends State<InspectableStorePage> {
  List<_Row>? _rows;

  @override
  void initState() {
    super.initState();
    _load(widget.store).then((rows) {
      if (mounted) setState(() => _rows = rows);
    });
  }

  @override
  Widget build(BuildContext context) => _StoreList(
    rows: _rows,
    empty: '${widget.store.name} is empty',
    row: (row) =>
        ListTile(title: Text(row.key), subtitle: Mono(row.value ?? 'null')),
  );
}

// Fault Injection

enum _FaultKind { status, drop, delay }

/// The active rules, each removable, and a form to add one. Rules live in
/// memory only.
class FaultInjectionPage extends StatefulWidget {
  /// The page.
  const FaultInjectionPage({super.key});

  @override
  State<FaultInjectionPage> createState() => _FaultInjectionPageState();
}

class _FaultInjectionPageState extends State<FaultInjectionPage> {
  String? _method;
  var _kind = _FaultKind.status;
  final _path = TextEditingController();
  final _status = TextEditingController(text: '503');
  final _delay = TextEditingController();
  final _body = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_path, _status, _delay, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  void _add() {
    try {
      final delayText = _delay.text.trim();
      final status = _kind == _FaultKind.status
          ? (int.tryParse(_status.text.trim()) ??
                (throw ArgumentError('Status must be a number')))
          : null;
      DevTools.faults.add(
        FaultRule(
          method: _method,
          pathPattern: _path.text.trim(),
          status: status,
          delay: delayText.isEmpty
              ? null
              : Duration(
                  milliseconds:
                      int.tryParse(delayText) ??
                      (throw ArgumentError('Delay must be a number')),
                ),
          drop: _kind == _FaultKind.drop,
          body: _kind == _FaultKind.status && _body.text.trim().isNotEmpty
              ? _body.text
              : null,
        ),
      );
      setState(() {
        _error = null;
        _path.clear();
      });
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DevTools.faults.active,
    builder: (context, rules, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Rules live in memory only and are gone after a restart.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No rules'),
          ),
        for (final rule in rules)
          Row(
            key: ValueKey('fault-rule:${rule.pathPattern}'),
            children: [
              Expanded(child: Text(_describe(rule))),
              TextButton(
                key: ValueKey('fault-remove:${rule.pathPattern}'),
                onPressed: () => DevTools.faults.remove(rule),
                child: const Text('Remove'),
              ),
            ],
          ),
        const Divider(height: 24),
        Text('Add a rule', style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 4,
          children: [
            for (final m in [null, 'GET', 'POST', 'PUT', 'PATCH', 'DELETE'])
              ChoiceChip(
                label: Text(m ?? 'Any'),
                selected: _method == m,
                onSelected: (_) => setState(() => _method = m),
              ),
          ],
        ),
        TextField(
          key: const ValueKey('fault-path'),
          controller: _path,
          decoration: const InputDecoration(
            labelText: 'Path, such as /orders or /orders/*',
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            for (final (kind, label) in [
              (_FaultKind.status, 'Status'),
              (_FaultKind.drop, 'Drop'),
              (_FaultKind.delay, 'Delay only'),
            ])
              ChoiceChip(
                key: ValueKey('fault-kind:${kind.name}'),
                label: Text(label),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        if (_kind == _FaultKind.status) ...[
          TextField(
            key: const ValueKey('fault-status'),
            controller: _status,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Status'),
          ),
          TextField(
            controller: _body,
            decoration: const InputDecoration(labelText: 'Body (optional)'),
          ),
        ],
        TextField(
          key: const ValueKey('fault-delay'),
          controller: _delay,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Delay in ms (optional)',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            key: const ValueKey('fault-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              key: const ValueKey('fault-add'),
              onPressed: _add,
              child: const Text('Add rule'),
            ),
          ),
        ),
      ],
    ),
  );

  static String _describe(FaultRule rule) =>
      '${rule.method ?? 'Any'} ${rule.pathPattern} → ${[if (rule.status != null) '${rule.status}', if (rule.drop) 'drop', if (rule.delay != null) 'after ${rule.delay!.inMilliseconds} ms'].join(', ')}';
}

// API Host

/// The app's hosts, one chosen at a time, with the app's own as the reset.
/// Remembered across restarts.
class ApiHostPage extends StatelessWidget {
  /// The page.
  const ApiHostPage({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: DevTools.hosts.hosts,
    builder: (context, hosts, _) => ValueListenableBuilder(
      valueListenable: DevTools.hosts.current,
      builder: (context, current, _) => RadioGroup<String?>(
        groupValue: current,
        onChanged: DevTools.hosts.select,
        child: ListView(
          children: [
            for (final host in [null, ...hosts])
              RadioListTile<String?>(
                key: ValueKey('host:${host ?? 'own'}'),
                value: host,
                title: Text(host ?? "The app's own"),
                subtitle: host == null
                    ? const Text("Each client's base URL from its config")
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}

// Changelog

/// The app's changelog text.
class ChangelogPage extends StatelessWidget {
  /// The page showing [text].
  const ChangelogPage(this.text, {super.key});

  /// The changelog.
  final String text;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('changelog'),
    padding: const EdgeInsets.all(16),
    child: Text(text),
  );
}
