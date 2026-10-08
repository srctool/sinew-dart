import 'package:flutter/material.dart';

/// The Sinew example app. Until milestone S5 it shows a placeholder; then it becomes the list screen through CamoPagedList.
void main() => runApp(const SinewExampleApp());

/// The example's root widget.
class SinewExampleApp extends StatelessWidget {
  /// Creates the example app.
  const SinewExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(body: Center(child: Text('Sinew example (S0)'))),
      );
}
