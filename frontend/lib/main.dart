import 'package:flutter/material.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  runApp(const FuelApp());
}
