import 'package:flutter/widgets.dart';

/// A titled group of entries on the dashboard's first screen. Sinew's built-in
/// inspectors are the first section; the app's own sections follow, in the
/// order given.
@immutable
final class DevToolSection {
  /// A section titled [title].
  const DevToolSection(this.title, this.entries);

  /// The section's title.
  final String title;

  /// Its rows.
  final List<DevToolEntry> entries;
}

/// One row on the dashboard.
sealed class DevToolEntry {
  const DevToolEntry({required this.name, this.description, this.icon});

  /// The row's title.
  final String name;

  /// A line under the title, or `null`.
  final String? description;

  /// The row's icon, or `null` for a monogram of [name].
  final IconData? icon;
}

/// Opens a page built by [builder], under an app bar with [name] and
/// [actions]. The page runs in the dashboard's own theme and navigator, never
/// the app's.
final class DevToolPage extends DevToolEntry {
  /// A page entry.
  const DevToolPage({
    required super.name,
    required this.builder,
    super.description,
    super.icon,
    this.color,
    this.actions = const [],
  });

  /// The page's content.
  final WidgetBuilder builder;

  /// The row's color, or `null` for the theme's.
  final Color? color;

  /// Widgets in the page's app bar.
  final List<Widget> actions;
}

/// Opens a sub-list of [children].
final class DevToolGroup extends DevToolEntry {
  /// A group entry.
  const DevToolGroup({
    required super.name,
    required this.children,
    super.description,
    super.icon,
    this.color,
  });

  /// The entries in the group.
  final List<DevToolEntry> children;

  /// The row's color, or `null` for the theme's.
  final Color? color;
}

/// A switch shown inline: [value] is read when the row builds, [onChanged]
/// called when it's flipped.
final class DevToolToggle extends DevToolEntry {
  /// A toggle entry.
  const DevToolToggle({
    required super.name,
    required this.value,
    required this.onChanged,
    super.description,
    super.icon,
  });

  /// The switch's current value.
  final bool Function() value;

  /// Called with the new value.
  final ValueChanged<bool> onChanged;
}

/// Runs [run] on tap. With [confirm], a dialog with that text asks first.
final class DevToolAction extends DevToolEntry {
  /// An action entry.
  const DevToolAction({
    required super.name,
    required this.run,
    super.description,
    super.icon,
    this.confirm,
  });

  /// What a tap does.
  final Future<void> Function() run;

  /// The question asked first, or `null` to run at once.
  final String? confirm;
}

/// A label in a corner of every screen, such as `1.4.0 (212) · staging`. The
/// active host and faults are added to it.
@immutable
final class BuildRibbon {
  /// A ribbon reading [label].
  const BuildRibbon(this.label);

  /// The label.
  final String label;
}

/// How the dashboard opens. Whichever is chosen, the dashboard, its theme and
/// its navigator are the same, and recording, fault rules and the ribbon work
/// the same.
sealed class DevToolsLauncher {
  const DevToolsLauncher();
}

/// A floating button, draggable, that opens the dashboard on tap; a drag
/// never opens it. It starts at [initialAlignment], and where it's dragged to
/// is remembered in `SinewDevTools`' `preferences`.
final class FloatingLauncher extends DevToolsLauncher {
  /// The floating button.
  const FloatingLauncher({this.initialAlignment = Alignment.bottomRight});

  /// Where the button starts.
  final Alignment initialAlignment;
}

/// No floating button: the app places `DevToolsMenuItem` where it wants, in
/// a settings page or a drawer.
final class MenuLauncher extends DevToolsLauncher {
  /// The menu launcher.
  const MenuLauncher();
}

/// No UI from devtools: the app calls `DevTools.open()` and
/// `DevTools.close()` from its own trigger.
final class CustomLauncher extends DevToolsLauncher {
  /// The custom launcher.
  const CustomLauncher();
}
