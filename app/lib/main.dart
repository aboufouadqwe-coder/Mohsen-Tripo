import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/core/analytics/analytics.dart';
import 'src/core/analytics/posthog_analytics.dart';
import 'src/core/routing/app_router.dart';
import 'src/data/supabase/generation_gateway.dart';
import 'src/data/supabase/project_repository.dart';
import 'src/data/supabase/reference_image_repository.dart';
import 'src/data/supabase/results_repository.dart';
import 'src/data/supabase/supabase_clients.dart';
import 'src/data/supabase/template_repository.dart';
import 'src/features/bootstrap/session_bootstrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = AppConfig.fromEnvironment();

    final analytics = await createConfiguredAnalytics(
      projectToken: config.posthogApiKey,
      host: config.posthogHost,
    );
    AnalyticsBinding.bind(analytics);

    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );

    final client = Supabase.instance.client;
    await SessionBootstrapper(
      SupabaseAuthPort(client),
    ).ensureSession();

    final router = buildAppRouter(
      AppRouterDependencies(
        projectRepository: DefaultProjectRepository(
          dataSource: SupabaseProjectDataSource(client),
          currentUserId: () => requireCurrentSupabaseUserId(client),
        ),
        templateRepository: DefaultTemplateRepository(
          SupabaseTemplateDataSource(client),
        ),
        referenceImageRepository: DefaultReferenceImageRepository(
          SupabaseReferenceStoragePort(client),
        ),
        resultsRepository: DefaultResultsRepository(
          dataSource: SupabaseResultsDataSource(client),
        ),
        generationGateway: DefaultGenerationGateway(
          SupabaseFunctionInvoker(client),
          jobDataSource: SupabaseGenerationJobDataSource(client),
        ),
        currentUserId: () => requireCurrentSupabaseUserId(client),
      ),
    );

    runApp(
      ProviderScope(
        child: MohsenTripoApp(
          key: ValueKey(config.supabaseUrl),
          router: router,
        ),
      ),
    );
  } catch (_) {
    runApp(const _BootstrapFailureApp());
  }
}

final class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 52),
                  SizedBox(height: 16),
                  Text(
                    'تعذر بدء التطبيق',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'تحقق من اتصال الإنترنت وإعداد Anonymous Sign-Ins في Supabase، ثم أغلق التطبيق وافتحه من جديد.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
