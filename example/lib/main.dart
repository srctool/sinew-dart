import 'package:camouflage_core/camouflage_core.dart';
import 'package:camouflage_skin_minimal/camouflage_skin_minimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinew_l10n/sinew_l10n.dart';

import 'orders/order_list_screen.dart';

/// The Sinew example: one list screen, through `Pager` → `PagingState` →
/// `toCamo` → `CamoPagedList`.
void main() => runApp(const ProviderScope(child: SinewExampleApp()));

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
