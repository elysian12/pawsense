import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsense/app/theme.dart';

class PawSenseApp extends StatelessWidget {
  const new({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'PawSense',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    routerConfig: router,
  );
}
