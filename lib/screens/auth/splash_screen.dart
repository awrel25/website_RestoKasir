import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/auth/business_setup_screen.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/screens/home/home_screen.dart';
import 'package:my_app/services/auth_onboarding_service.dart';
import 'package:my_app/core/theme/auth_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  Timer? _timer;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _animController.forward();
    _timer = Timer(const Duration(milliseconds: 2200), checkSession);
  }

  Future<void> checkSession() async {
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    try {
      final onboarding = AuthOnboardingService();
      final resolution = await onboarding.resolveForSupabaseUser(session.user);
      if (!mounted) return;

      if (!resolution.hasRestaurant) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BusinessSetupScreen(
              initialOwnerName: resolution.ownerName,
            ),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Splash onboarding check fallback to HomeScreen guard: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgCol = AppColors.bg(context);
    final cardCol = AppColors.card(context);
    final borderCol = AppColors.border(context);
    final textCol = AppColors.text(context);
    final mutedCol = AppColors.muted(context);

    return Scaffold(
      backgroundColor: bgCol,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;
            final isTablet =
                constraints.maxWidth >= 600 && constraints.maxWidth < 900;
            final logoSize = isDesktop ? 112.0 : (isTablet ? 96.0 : 80.0);

            return Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: isDesktop ? 460 : (isTablet ? 400 : 340),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 40 : 28,
                        vertical: isDesktop ? 44 : 32,
                      ),
                      decoration: isDesktop || isTablet
                          ? BoxDecoration(
                              color: cardCol,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: borderCol),
                            )
                          : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppLogo(
                            size: logoSize,
                            borderRadius: logoSize * 0.28,
                            showShadow: false,
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'RestoKasir',
                            style: AppFonts.display(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: textCol,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Aplikasi kasir dan pengelolaan restoran',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isDesktop ? 15 : 13,
                              color: mutedCol,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 36),
                          SizedBox(
                            width: 140,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                backgroundColor: AppColors.surface(context),
                                color: AppColors.primary,
                                minHeight: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Memuat aplikasi...',
                            style: TextStyle(
                              fontSize: 12,
                              color: mutedCol,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
