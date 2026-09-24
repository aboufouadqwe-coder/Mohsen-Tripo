import 'package:flutter/material.dart';

class MohsenTripoApp extends StatelessWidget {
  const MohsenTripoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mohsen Tripo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7057FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Mohsen Tripo'),
        ),
      ),
    );
  }
}
