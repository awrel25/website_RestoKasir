import 'package:flutter/material.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/auth_onboarding_service.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/screens/admin/admin_screen.dart';
import 'package:my_app/screens/cashier/cashier_screen.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/screens/auth/business_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _posService = PosService();
  late final AuthOnboardingService _onboardingService = AuthOnboardingService(
    store: SupabaseOnboardingStore(_posService.supabase),
  );

  UserProfile? _userProfile;
  String _restaurantName = 'Resto Saya';
  bool _isLoading = true;
  bool _adminViewingPos = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initRoleAndData();
  }

  Future<void> _initRoleAndData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final user = _posService.supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    try {
      final resolution = await _onboardingService.resolveForSupabaseUser(user);
      if (!mounted) return;

      if (!resolution.hasRestaurant || resolution.profile == null) {
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

      final restoName = await _posService.fetchRestaurantName();
      if (!mounted) return;

      setState(() {
        _userProfile = resolution.profile;
        _restaurantName = restoName;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing profile: $e');
      if (mounted) {
        setState(() {
          _errorMessage = AuthOnboardingService.formatFriendlyError(
            e,
            fallback: 'Gagal memeriksa identitas restoran. Silakan coba lagi.',
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOutToLogin() async {
    await _posService.supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Memverifikasi Hak Akses Sistem...',
                style: TextStyle(
                  fontSize: 14,
                  color: ThemeController.isDark(context)
                      ? AppColors.darkMuted
                      : AppColors.lightMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: AppColors.statusCancelled,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _initRoleAndData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Coba Lagi'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _signOutToLogin,
                        child: const Text('Keluar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final profile = _userProfile;
    if (profile == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              const Text('Profil tidak ditemukan. Silakan login kembali.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _signOutToLogin,
                child: const Text('Ke Halaman Login'),
              ),
            ],
          ),
        ),
      );
    }

    // ROLE BASED ROUTING & RESTRICTION:
    // 1. Kasir: strictly gets CashierScreen. No access to Admin features.
    // 2. Admin / Owner: gets AdminScreen by default, but can preview/help with Cashier POS if desired.
    if (profile.isAdmin) {
      if (_adminViewingPos) {
        return CashierScreen(
          userProfile: profile,
          restaurantName: _restaurantName,
          onBackToAdmin: () => setState(() => _adminViewingPos = false),
        );
      }
      return AdminScreen(
        userProfile: profile,
        restaurantName: _restaurantName,
        onOpenPos: () => setState(() => _adminViewingPos = true),
      );
    }

    // Role is 'kasir': Kasir CANNOT access AdminScreen
    return CashierScreen(
      userProfile: profile,
      restaurantName: _restaurantName,
      onBackToAdmin: null, // Kasir cannot switch to admin
    );
  }
}
