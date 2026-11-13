import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/core/routing/app_routes.dart';
import 'package:my_app/core/theme/theme_controller.dart';

const _googleClientId =
    '499015940932-1cfpf8iua15eusq2qe72li0c67mca54c.apps.googleusercontent.com';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('id_ID', null);

  await Supabase.initialize(
    url: 'https://uinumtttwkwlurvqvidh.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbnVtdHR0d2t3bHVydnF2aWRoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2OTUxNTcsImV4cCI6MjEwMDI3MTE1N30.eSfjbxge6LA8fIqP9Cnepld7s4PgQgh_Eqi3O58DI1M',
  );

  // Google Sign In
  if (kIsWeb) {
    await GoogleSignIn.instance.initialize(clientId: _googleClientId);
  } else {
    await GoogleSignIn.instance.initialize(serverClientId: _googleClientId);
  }

  // Supabase auth listener
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      navigatorKey.currentState?.pushNamed(AppRoutes.resetPassword);
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'RestoKasir',
      theme: ThemeController.lightTheme,
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.2,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
