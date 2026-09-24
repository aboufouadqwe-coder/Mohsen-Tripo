import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  runApp(
    ProviderScope(
      child: MohsenTripoApp(
        key: ValueKey(config.supabaseUrl),
      ),
    ),
  );
}
