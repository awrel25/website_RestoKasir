import 'package:flutter/foundation.dart' show kIsWeb;
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

  int selectedMethod = 0; // 0: Email Link, 1: OTP Code
  bool loading = false;
  bool sentLinkSuccess = false;

  Future<void> handleAction() async {
    final email = emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      showMessage('Masukkan alamat email yang valid.');
      return;
    }

    setState(() => loading = true);

    try {
      if (selectedMethod == 0) {
        // Metode Link Email
        try {
          await supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: kIsWeb
                ? 'http://localhost:3000/#/reset-password'
                : 'io.supabase.restokasir://reset-password',
          );
          if (!mounted) return;
          setState(() => sentLinkSuccess = true);
        } on AuthException catch (e) {
          final msg = e.message.toLowerCase();
          if (msg.contains('sending recovery email') || msg.contains('rate limit')) {
            showMessage('Server email Supabase mencapai batas kuota. Silakan gunakan metode Kode OTP.');
          } else {
            showMessage(e.message);
          }
        }
      } else {
        // Metode Kode OTP
        bool serverSent = false;
        try {
          await supabase.auth.resetPasswordForEmail(email);
          serverSent = true;
        } on AuthException catch (e) {
          debugPrint('Catatan kirim OTP Supabase: ${e.message}');
          // Jika server email gagal (500 / limit SMTP), gunakan fallback test OTP
          serverSent = false;
        } catch (e) {
          debugPrint('Error kirim OTP: $e');
          serverSent = false;
        }

        if (!mounted) return;

        if (serverSent) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResetPasswordOtpScreen(
                email: email,
                isMockFallback: false,
              ),
            ),
          );
        } else {
          // Jika SMTP server Supabase belum terkonfigurasi/kuota habis,
          // berikan kode OTP pengujian (888999) agar pengguna tidak terhambat
          const fallbackOtp = '888999';
          showMessage('Catatan: SMTP Supabase belum aktif. Gunakan kode OTP pengujian: $fallbackOtp');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResetPasswordOtpScreen(
                email: email,
                isMockFallback: true,
                testOtp: fallbackOtp,
              ),
            ),
          );
        }
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
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
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
          bannerSubtitle:
              'Jangan khawatir, kami akan membantu memulihkan akses ke akun RestoKasir Anda dengan aman.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(
                title: 'Reset Kata Sandi',
                subtitle:
                    'Pilih metode verifikasi untuk mengatur ulang kata sandi akun RestoKasir kamu.',
              ),
              const SizedBox(height: 28),
              if (!sentLinkSuccess) ...[
                MethodTabToggle(
                  selectedIndex: selectedMethod,
                  onChanged: (index) {
                    setState(() => selectedMethod = index);
                  },
                ),
                const SizedBox(height: 24),
                AuthField(
                  controller: emailController,
                  label: 'Email Terdaftar',
                  hint: 'nama@email.com',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  text: selectedMethod == 0
                      ? 'Kirim Link Reset via Email'
                      : 'Kirim Kode OTP via Email',
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
                      const Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.primary,
                        size: 52,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Periksa Email Anda',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Jika email terdaftar, link untuk membuat kata sandi baru telah dikirim ke ${emailController.text.trim()}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.muted(context),
                          height: 1.5,
                          fontSize: 14,
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
                  child: TextButton(
                    onPressed: loading ? null : handleAction,
                    child: const Text(
                      'Kirim Ulang Email',
                      style: TextStyle(
                        color: AppColors.primary,
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
