import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:my_app/screens/home/home_screen.dart';
import 'package:my_app/screens/auth/business_setup_screen.dart';
import 'package:my_app/screens/auth/register_screen.dart';
import 'package:my_app/screens/auth/forgot_password_screen.dart';
import 'package:my_app/services/auth_onboarding_service.dart';
import 'package:my_app/core/theme/auth_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;
  late final AuthOnboardingService _onboardingService =
      AuthOnboardingService(store: SupabaseOnboardingStore(supabase));

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GoogleSignIn googleSignIn = GoogleSignIn.instance;

  bool isLoading = false;
  bool obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  String? _formError;

  // ============================================================
  // LOGIN EMAIL / USERNAME & PASSWORD
  // ============================================================
  Future<void> login() async {
    final rawInput = emailController.text.trim();
    final password = passwordController.text;

    String? nextEmailErr;
    String? nextPassErr;
    if (rawInput.isEmpty) {
      nextEmailErr = 'Email atau username harus diisi.';
    }
    if (password.isEmpty) {
      nextPassErr = 'Password harus diisi.';
    }

    if (nextEmailErr != null || nextPassErr != null) {
      setState(() {
        _emailError = nextEmailErr;
        _passwordError = nextPassErr;
        _formError = null;
      });
      return;
    }

    if (isLoading) return;

    setState(() {
      isLoading = true;
      _emailError = null;
      _passwordError = null;
      _formError = null;
    });

    try {
      String emailToUse = rawInput.toLowerCase();

      // Jika user memasukkan username (tidak mengandung '@'), cari emailnya di tabel profiles
      if (!rawInput.contains('@')) {
        try {
          final profileMatch = await supabase
              .from('profiles')
              .select('email')
              .ilike('full_name', rawInput)
              .maybeSingle();

          if (profileMatch != null && profileMatch['email'] != null) {
            emailToUse = profileMatch['email'].toString().trim().toLowerCase();
          }
        } catch (_) {
          // Tetap gunakan input asli jika pencarian username gagal
        }
      }

      final response = await supabase.auth.signInWithPassword(
        email: emailToUse,
        password: password,
      );

      if (response.session == null || response.user == null) {
        showMessage('Login gagal. Silakan cek email dan password.');
        return;
      }

      final user = response.user!;

      await _navigateAfterAuth(
        user,
        fallbackEmail: emailToUse,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid email or password')) {
        showMessage('Email/Username atau password salah.');
      } else if (msg.contains('email not confirmed')) {
        showMessage(
            'Email belum diverifikasi. Cek kotak masuk email dan klik tautan konfirmasi.');
      } else if (msg.contains('too many requests')) {
        showMessage('Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.');
      } else {
        showMessage(e.message);
      }
    } catch (e) {
      debugPrint('EMAIL LOGIN ERROR: $e');
      showMessage(
        AuthOnboardingService.formatFriendlyError(
          e,
          fallback: 'Terjadi kesalahan saat masuk: $e',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // LOGIN GOOGLE
  // ============================================================
  Future<void> loginWithGoogle() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      _emailError = null;
      _passwordError = null;
      _formError = null;
    });

    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google ID Token tidak ditemukan.');
      }

      final authorization = await googleUser.authorizationClient
          .authorizeScopes(<String>['email', 'profile']);
      final String? accessToken = authorization.accessToken;

      final AuthResponse response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.session == null || response.user == null) {
        throw Exception('Session Supabase tidak berhasil dibuat.');
      }

      final User user = response.user!;

      // Jangan arahkan ke dashboard sebelum pengecekan identitas restoran selesai
      await _navigateAfterAuth(
        user,
        fallbackEmail: googleUser.email,
        fallbackName: googleUser.displayName,
      );
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      if (e.code == GoogleSignInExceptionCode.canceled) {
        showMessage('Pemilihan akun Google dibatalkan.');
      } else {
        showMessage(
          AuthOnboardingService.formatFriendlyError(
            e,
            fallback: e.description ?? 'Gagal login dengan Google.',
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      showMessage('Supabase: ${e.message}');
    } catch (e) {
      debugPrint('GOOGLE LOGIN ERROR: $e');
      if (!mounted) return;
      showMessage(
        AuthOnboardingService.formatFriendlyError(
          e,
          fallback: 'Login Google gagal: $e',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // POST-AUTH ONBOARDING & ROUTING
  // ============================================================
  Future<void> _navigateAfterAuth(
    User user, {
    String? fallbackEmail,
    String? fallbackName,
  }) async {
    final resolution = await _onboardingService.resolveForSupabaseUser(
      user,
      fallbackEmail: fallbackEmail,
      fallbackName: fallbackName,
    );

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

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _formError = message;
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightSurface,
      body: SafeArea(
        child: ResponsiveAuthLayout(
          bannerTitle: 'RestoKasir POS',
          bannerSubtitle: 'Sistem POS & Kasir Restoran',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(
                title: 'Masuk ke Akun',
                subtitle: 'Silakan masuk ke akun Anda.',
                showLogo: true,
              ),
              const SizedBox(height: 24),
              if (_formError != null) ...[
                AuthErrorBanner(message: _formError!),
                const SizedBox(height: 16),
              ],
              AuthField(
                controller: emailController,
                label: 'Email',
                hint: 'nama@email.com',
                icon: Icons.person_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                errorText: _emailError,
                onChanged: (_) {
                  if (_emailError != null || _formError != null) {
                    setState(() {
                      _emailError = null;
                      _formError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: passwordController,
                label: 'Password',
                hint: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: obscurePassword,
                textInputAction: TextInputAction.done,
                errorText: _passwordError,
                onChanged: (_) {
                  if (_passwordError != null || _formError != null) {
                    setState(() {
                      _passwordError = null;
                      _formError = null;
                    });
                  }
                },
                onSubmitted: (_) {
                  if (!isLoading) login();
                },
                suffix: IconButton(
                  tooltip: obscurePassword
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  onPressed: isLoading
                      ? null
                      : () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.muted(context),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                  child: const Text(
                    'Lupa kata sandi?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                text: 'Masuk',
                onPressed: isLoading ? null : login,
                loading: isLoading,
              ),
              const SizedBox(height: 18),
              const OrDivider(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: isLoading ? null : loginWithGoogle,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    side: const BorderSide(color: AppColors.lightBorder),
                    backgroundColor: AppColors.lightBg,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'G',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Lanjutkan dengan Google',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.lightText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    const Text(
                      'Belum punya akun? ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.lightMuted,
                      ),
                    ),
                    GestureDetector(
                      onTap: isLoading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                      child: const Text(
                        'Daftar sekarang',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
