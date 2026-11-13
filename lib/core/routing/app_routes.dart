import 'package:flutter/material.dart';
import 'package:my_app/screens/admin/add_product_screen.dart';
import 'package:my_app/screens/auth/forgot_password_screen.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/screens/auth/register_screen.dart';
import 'package:my_app/screens/auth/reset_password_screen.dart';
import 'package:my_app/screens/auth/splash_screen.dart';
import 'package:my_app/screens/home/home_screen.dart';

/// Declarative route table for the application shell.
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String home = '/home';
  static const String addProduct = '/add-product';

  static Map<String, WidgetBuilder> get routes => {
        splash: (_) => const SplashScreen(),
        login: (_) => const LoginScreen(),
        register: (_) => const RegisterScreen(),
        forgotPassword: (_) => const ForgotPasswordScreen(),
        resetPassword: (_) => const ResetPasswordScreen(),
        home: (_) => const HomeScreen(),
        addProduct: (_) => const AddProductScreen(),
      };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = routes[settings.name];
    if (builder != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: builder,
      );
    }
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const SplashScreen(),
    );
  }
}

