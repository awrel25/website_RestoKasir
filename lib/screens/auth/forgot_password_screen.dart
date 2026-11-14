import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/screens/auth/reset_password_otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  final supabase = Supabase.instance.client;

  static const String recoveryRedirectUrl =
      'https://awrel25.github.io/website_RestoKasir/reset-password.html';

  int selectedMethod = 0; // 0: Link Email, 1: Kode OTP
  bool loading = false;
  bool sentLinkSuccess = false;

  // Timer cooldown untuk pengiriman ulang email
  Timer? _resendTimer;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    emailController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _cooldownSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds > 1) {
        setState(() => _cooldownSeconds--);
      } else {
        setState(() => _cooldownSeconds = 0);
        timer.cancel();
      }
    });
  }

  bool _validateEmail(String email) {
    if (email.isEmpty) {
      showMessage('Silakan masukkan alamat email akun Anda.');
      return false;
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
    );
    if (!emailRegex.hasMatch(email)) {
      showMessage('Format alamat email tidak valid (contoh: kasir@restoran.com).');
      return false;
    }
    return true;
  }

  Future<void> handleAction() async {
    if (_cooldownSeconds > 0) {
      showMessage(
        'Harap tunggu $_cooldownSeconds detik sebelum meminta pengiriman ulang.',
      );
      return;
    }

    final email = emailController.text.trim().toLowerCase();
    if (!_validateEmail(email)) return;

    setState(() => loading = true);

    try {
      if (selectedMethod == 0) {
        // =====================================================================
        // METODE 1: RESET PASSWORD MENGGUNAKAN EMAIL LINK
        // =====================================================================
        await supabase.auth
            .resetPasswordForEmail(
              email,
              redirectTo: recoveryRedirectUrl,
            )
            .timeout(const Duration(seconds: 15));

        if (!mounted) return;
        setState(() => sentLinkSuccess = true);
        _startCooldown(60);
        showMessage('Link pemulihan kata sandi berhasil dikirim ke email Anda.');
      } else {
        // =====================================================================
        // METODE 2: RESET PASSWORD MENGGUNAKAN KODE OTP (Template Magic Link / OTP)
        // Mengirimkan email yang KHUSUS berisi 6-digit kode OTP (tanpa link tombol web)
        // =====================================================================
        await supabase.auth
            .signInWithOtp(
              email: email,
              shouldCreateUser: false,
            )
            .timeout(const Duration(seconds: 15));

        if (!mounted) return;
        showMessage('Kode OTP 6-digit telah dikirimkan ke $email.');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResetPasswordOtpScreen(
              email: email,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('sending recovery email') ||
          msg.contains('sending magic link email') ||
          msg.contains('unexpected_failure') ||
          msg.contains('error sending')) {
        showMessage(
          'Server email Supabase gagal mengirim: Kuota email gratis Supabase (3 email/jam) telah tercapai atau Custom SMTP belum diaktifkan di Supabase Dashboard.',
        );
      } else if (msg.contains('rate limit') || msg.contains('over_email_send_rate_limit')) {
        showMessage(
          'Batas frekuensi pengiriman email tercapai. Silakan tunggu beberapa saat sebelum mencoba kembali.',
        );
      } else if (msg.contains('user not found') || msg.contains('email not found')) {
        showMessage(
          'Alamat email "$email" tidak terdaftar pada sistem RestoKasir.',
        );
      } else {
        showMessage(e.message);
      }
    } catch (e) {
      showMessage('Gagal memproses permintaan reset password: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ResponsiveAuthLayout(
          bannerTitle: 'Lupa Kata Sandi?',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(
                title: 'Reset Kata Sandi',
                subtitle: 'Pilih metode pemulihan akun Anda.',
              ),
              const SizedBox(height: 24),
              if (!sentLinkSuccess) ...[
                MethodTabToggle(
                  selectedIndex: selectedMethod,
                  onChanged: (index) {
                    setState(() => selectedMethod = index);
                  },
                ),
                const SizedBox(height: 20),
                AuthField(
                  controller: emailController,
                  label: 'Email Terdaftar',
                  hint: 'nama@email.com',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  text: selectedMethod == 0
                      ? 'Kirim Link'
                      : 'Kirim Kode OTP',
                  onPressed: loading ? null : handleAction,
                  loading: loading,
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mark_email_read_rounded,
                          color: AppColors.primary,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Email Pemulihan Terkirim',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Link pemulihan telah dikirim ke:\n${emailController.text.trim()}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.muted(context),
                          height: 1.5,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  text: 'Kembali ke Login',
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                    (route) => false,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: (loading || _cooldownSeconds > 0)
                        ? null
                        : handleAction,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      _cooldownSeconds > 0
                          ? 'Kirim Ulang Email (${_cooldownSeconds}s)'
                          : 'Kirim Ulang Email',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
