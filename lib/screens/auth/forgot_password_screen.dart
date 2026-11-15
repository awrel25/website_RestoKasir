import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/screens/auth/reset_password_otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  final supabase = Supabase.instance.client;

  bool loading = false;

  // Timer cooldown untuk permintaan OTP baru
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
      showMessage('Masukkan email Anda');
      return false;
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
    );
    if (!emailRegex.hasMatch(email)) {
      showMessage('Format email tidak valid');
      return false;
    }
    return true;
  }

  Future<void> sendOtpCode() async {
    if (_cooldownSeconds > 0) {
      showMessage(
        'Tunggu $_cooldownSeconds detik',
      );
      return;
    }

    final email = emailController.text.trim().toLowerCase();
    if (!_validateEmail(email)) return;

    setState(() => loading = true);

    try {
      // Mengirimkan kode verifikasi OTP 6 digit resmi ke email pengguna via Supabase Auth
      try {
        await supabase.auth
            .resetPasswordForEmail(email)
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        // Fallback jika project Supabase mengarahkan OTP via signInWithOtp
        await supabase.auth
            .signInWithOtp(
              email: email,
              shouldCreateUser: false,
            )
            .timeout(const Duration(seconds: 15));
      }

      if (!mounted) return;
      _startCooldown(60);
      showMessage('OTP dikirim ke $email');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordOtpScreen(
            email: email,
          ),
        ),
      );
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
          'Batas frekuensi pengiriman OTP tercapai. Silakan tunggu beberapa saat sebelum mencoba kembali.',
        );
      } else if (msg.contains('user not found') || msg.contains('email not found')) {
        showMessage(
          'Alamat email "$email" tidak terdaftar pada sistem RestoKasir.',
        );
      } else {
        showMessage(e.message);
      }
    } catch (e) {
      showMessage('Gagal memproses permintaan OTP: $e');
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
                title: 'Reset Password',
                subtitle: 'Masukkan email untuk menerima kode OTP.',
              ),
              const SizedBox(height: 24),
              AuthField(
                controller: emailController,
                label: 'Email',
                hint: 'nama@email.com',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: _cooldownSeconds > 0
                    ? 'Tunggu (${_cooldownSeconds}s)'
                    : 'Kirim OTP',
                onPressed: (loading || _cooldownSeconds > 0) ? null : sendOtpCode,
                loading: loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
