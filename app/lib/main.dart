import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/data/supabase/supabase_clients.dart';
import 'src/features/bootstrap/session_bootstrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
  );

  await SessionBootstrapper(
    SupabaseAuthPort(Supabase.instance.client),
  ).ensureSession();

  runApp(
    ProviderScope(
      child: MohsenTripoApp(
        key: ValueKey(config.supabaseUrl),
      ),
    ),
  );
}
