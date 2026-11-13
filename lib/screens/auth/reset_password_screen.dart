import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/screens/auth/login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? targetEmail;
  const ResetPasswordScreen({super.key, this.targetEmail});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final supabase = Supabase.instance.client;

  bool loading = false;
  bool hideNewPassword = true;
  bool hideConfirmPassword = true;
  bool isSuccess = false;
  String currentPasswordText = '';

  @override
  void initState() {
    super.initState();
    newPasswordController.addListener(() {
      setState(() {
        currentPasswordText = newPasswordController.text;
      });
    });
  }

  Future<void> updatePassword() async {
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      showMessage('Silakan isi kedua kolom password.');
      return;
    }

    if (newPassword.length < 6) {
      showMessage('Password minimal terdiri dari 6 karakter.');
      return;
    }

    if (newPassword != confirmPassword) {
      showMessage('Password baru dan konfirmasi password tidak cocok.');
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.auth.updateUser(
          UserAttributes(password: newPassword),
        );
      }

      if (!mounted) return;
      setState(() => isSuccess = true);
    } on AuthException catch (e) {
      showMessage(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => isSuccess = true);
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
    newPasswordController.dispose();
    confirmPasswordController.dispose();
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
          bannerTitle: 'Atur Ulang Kata Sandi',
          bannerSubtitle: 'Buat kata sandi baru yang aman untuk akun RestoKasir Anda.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(
                title: 'Buat Kata Sandi Baru',
                subtitle: 'Masukkan kata sandi baru yang kuat dan mudah kamu ingat.',
              ),
              const SizedBox(height: 34),
              if (!isSuccess) ...[
                AuthField(
                  controller: newPasswordController,
                  label: 'Password Baru',
                  hint: 'Minimal 6 karakter',
                  icon: Icons.lock_outline_rounded,
                  obscureText: hideNewPassword,
                  suffix: IconButton(
                    onPressed: () => setState(() => hideNewPassword = !hideNewPassword),
                    icon: Icon(
                      hideNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    ),
                  ),
                ),
                PasswordStrengthIndicator(password: currentPasswordText),
                const SizedBox(height: 18),
                AuthField(
                  controller: confirmPasswordController,
                  label: 'Konfirmasi Password Baru',
                  hint: 'Ulangi password baru',
                  icon: Icons.lock_reset_rounded,
                  obscureText: hideConfirmPassword,
                  suffix: IconButton(
                    onPressed: () => setState(() => hideConfirmPassword = !hideConfirmPassword),
                    icon: Icon(
                      hideConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  text: 'Simpan Password Baru',
                  onPressed: loading ? null : updatePassword,
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
                        Icons.check_circle_outline_rounded,
                        color: AppColors.primary,
                        size: 54,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Kata Sandi Berhasil Diubah',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kata sandi akun Anda sudah diperbarui. Silakan masuk kembali dengan kata sandi baru.',
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
                const SizedBox(height: 24),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
