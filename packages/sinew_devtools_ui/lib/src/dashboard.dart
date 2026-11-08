import 'package:flutter/material.dart';

import 'entries.dart';

/// Forces light (`false`) or dark (`true`) instead of the system's setting:
/// golden images must not depend on the machine.
@visibleForTesting
bool? debugDevToolsDark;

/// The dashboard: its own `MaterialApp`, so its own theme and navigator,
/// never the app's. The sections are its first screen.
class Dashboard extends StatelessWidget {
  /// The dashboard over [sections].
  const Dashboard({
    required this.sections,
    required this.onClose,
    this.initial,
    super.key,
  });

  /// Sinew's section first, then the app's.
  final List<DevToolSection> sections;

  /// Closes the dashboard.
  final VoidCallback onClose;

  /// A page to start on instead of the sections, for golden tests.
  final DevToolPage? initial;

  @override
  Widget build(BuildContext context) {
    final dark = debugDevToolsDark;
    return MaterialApp(
      key: const ValueKey('sinew-devtools-dashboard'),
      debugShowCheckedModeBanner: false,
      title: 'Developer tools',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: dark == null
          ? ThemeMode.system
          : (dark ? ThemeMode.dark : ThemeMode.light),
      home: initial == null
          ? _Home(sections: sections, onClose: onClose)
          : PageScaffold(page: initial!),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({required this.sections, required this.onClose});

  final List<DevToolSection> sections;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      // System back on the first screen closes the dashboard, not the app.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Scaffold(
        key: const ValueKey('sinew-devtools-home'),
        appBar: AppBar(
          leading: TextButton(
            key: const ValueKey('sinew-devtools-back'),
            onPressed: onClose,
            child: const Text('Close'),
          ),
          leadingWidth: 80,
          title: const Text('Developer tools'),
        ),
        body: ListView(
          children: [
            for (final section in sections) ...[
              Padding(
                key: ValueKey('section:${section.title}'),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  section.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final entry in section.entries) EntryRow(entry),
            ],
          ],
        ),
      ),
    );
  }
}

/// A page's scaffold: its title, its actions and a back button.
class PageScaffold extends StatelessWidget {
  /// The scaffold for [page].
  const PageScaffold({required this.page, super.key});

  /// The page.
  final DevToolPage page;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: TextButton(
        key: const ValueKey('sinew-devtools-back'),
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back'),
      ),
      leadingWidth: 80,
      title: Text(page.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: page.actions,
    ),
    body: Builder(builder: page.builder),
  );
}

/// Pushes [page] on the dashboard's own navigator.
void pushPage(BuildContext context, DevToolPage page) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => PageScaffold(page: page)));

/// One row for [entry].
class EntryRow extends StatefulWidget {
  /// The row.
  const EntryRow(this.entry, {super.key});

  /// What the row shows.
  final DevToolEntry entry;

  @override
  State<EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<EntryRow> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final subtitle = entry.description == null
        ? null
        : Text(entry.description!);
    final leading = _EntryIcon(entry);
    final key = ValueKey('entry:${entry.name}');
    final tile = switch (entry) {
      DevToolPage() => ListTile(
        key: key,
        leading: leading,
        title: Text(entry.name),
        subtitle: subtitle,
        onTap: () => pushPage(context, entry),
      ),
      DevToolGroup(:final children) => ListTile(
        key: key,
        leading: leading,
        title: Text(entry.name),
        subtitle: subtitle,
        trailing: Text('${children.length}'),
        onTap: () => pushPage(
          context,
          DevToolPage(
            name: entry.name,
            builder: (_) =>
                ListView(children: [for (final c in children) EntryRow(c)]),
          ),
        ),
      ),
      DevToolToggle(:final value, :final onChanged) => SwitchListTile(
        key: key,
        secondary: leading,
        title: Text(entry.name),
        subtitle: subtitle,
        value: value(),
        onChanged: (v) => setState(() => onChanged(v)),
      ),
      DevToolAction(:final run, :final confirm) => ListTile(
        key: key,
        leading: leading,
        title: Text(entry.name),
        subtitle: subtitle,
        onTap: () async {
          if (confirm != null &&
              !await confirmFirst(
                context,
                title: entry.name,
                text: confirm,
                confirm: 'Run',
              )) {
            return;
          }
          await run();
        },
      ),
    };
    return Column(children: [tile, const Divider(height: 1)]);
  }
}

class _EntryIcon extends StatelessWidget {
  const _EntryIcon(this.entry);

  final DevToolEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry) {
      DevToolPage(:final color) || DevToolGroup(:final color) => color,
      _ => null,
    };
    final icon = entry.icon;
    return CircleAvatar(
      radius: 18,
      backgroundColor: color ?? scheme.secondaryContainer,
      child: icon != null
          ? Icon(icon, size: 20)
          : Text(
              entry.name.isEmpty ? '?' : entry.name[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onSecondaryContainer,
              ),
            ),
    );
  }
}

/// Asks before anything destructive: `true` when confirmed.
Future<bool> confirmFirst(
  BuildContext context, {
  required String title,
  required String text,
  required String confirm,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            key: const ValueKey('sinew-devtools-dismiss'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('sinew-devtools-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

/// Monospaced text, for records and stack traces.
class Mono extends StatelessWidget {
  /// [text] in a monospaced font.
  const Mono(this.text, {super.key});

  /// The text.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace'),
  );
}

/// A one-line message for an empty list.
class EmptyText extends StatelessWidget {
  /// The message.
  const EmptyText(this.text, {super.key});

  /// What it says.
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
