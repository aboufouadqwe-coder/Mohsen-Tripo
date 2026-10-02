import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MohsenTripoApp extends StatelessWidget {
  const MohsenTripoApp({
    super.key,
    this.router,
  });

  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    final routerConfig = router ??
        GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: Center(child: Text('Mohsen Tripo')),
              ),
            ),
          ],
        );

    return MaterialApp.router(
      title: 'Mohsen Tripo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7057FF),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7057FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: routerConfig,
    );
  }
}
