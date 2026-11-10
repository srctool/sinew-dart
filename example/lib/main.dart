import 'package:camouflage_core/camouflage_core.dart';
import 'package:camouflage_skin_minimal/camouflage_skin_minimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools_ui/sinew_devtools_ui.dart';
import 'package:sinew_l10n/sinew_l10n.dart';

import 'orders/order_list_screen.dart';

/// The Sinew example: one list screen, through `Pager` → `PagingState` →
/// `toCamo` → `CamoPagedList`, with devtools in debug and non-production
/// builds (`--dart-define=SINEW_FLAVOR=staging`). A production build
/// (`SINEW_FLAVOR=production`, or none) compiles them out.
// region devtools-entry
void main() {
  DevToolsGate.assertMatchesFlavor();
  const app = ProviderScope(child: SinewExampleApp());
  runApp(
    DevToolsGate.enabled
        ? const SinewDevTools(ribbon: BuildRibbon('Sinew example'), child: app)
        : app,
  );
}
// endregion

/// The example's root widget.
class SinewExampleApp extends StatelessWidget {
  /// Creates the example app.
  const SinewExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sinew',
    localizationsDelegates: SinewLocalizations.localizationsDelegates,
    supportedLocales: SinewLocalizations.supportedLocales,
    builder: (context, child) => CamouflageProvider(
      skin: minimalSkin,
      theme: MediaQuery.platformBrightnessOf(context) == Brightness.dark
          ? minimalDark
          : minimalLight,
      child: child!,
    ),
    home: const Scaffold(body: OrderListScreen()),
  );
}
