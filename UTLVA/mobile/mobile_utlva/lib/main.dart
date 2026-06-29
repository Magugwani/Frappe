import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/timetable/services/confirmation_retry_service.dart';

// SRS §3.12: Global retry service — starts on app launch, runs every 30 s
final _retryService = ConfirmationRetryService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _retryService.startPolling(); // offline confirmation retry
  runApp(const UTLVAApp());
}

class UTLVAApp extends StatelessWidget {
  const UTLVAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const _AppWithRouter(),
    );
  }
}

class _AppWithRouter extends StatelessWidget {
  const _AppWithRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return MaterialApp.router(
      title: 'UTLVA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: AppRouter.router(auth),
    );
  }
}
