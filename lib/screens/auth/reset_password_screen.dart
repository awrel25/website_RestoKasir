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

  String newPassword = '';
  String confirmPassword = '';

  @override
  void initState() {
    super.initState();
    newPasswordController.addListener(() {
      setState(() => newPassword = newPasswordController.text);
    });
    confirmPasswordController.addListener(() {
      setState(() => confirmPassword = confirmPasswordController.text);
    });
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // Validasi kriteria password
  bool get hasMinLength => newPassword.length >= 6;
  bool get hasLettersAndNumbers =>
      RegExp(r'[A-Za-z]').hasMatch(newPassword) &&
      RegExp(r'[0-9]').hasMatch(newPassword);
  bool get passwordsMatch =>
      newPassword.isNotEmpty && newPassword == confirmPassword;
  bool get isFormValid => hasMinLength && hasLettersAndNumbers && passwordsMatch;

  Future<void> updatePassword() async {
    if (!isFormValid) {
      if (!hasMinLength) {
        showMessage('Kata sandi harus terdiri dari minimal 6 karakter.');
      } else if (!hasLettersAndNumbers) {
        showMessage('Kata sandi harus mengandung kombinasi huruf dan angka.');
      } else if (!passwordsMatch) {
        showMessage('Kata sandi baru dan konfirmasi kata sandi tidak cocok.');
      }
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      final session = supabase.auth.currentSession;

      if (user == null && session == null) {
        throw const AuthException(
          'Sesi pemulihan kedaluwarsa atau tidak valid. Silakan ajukan permintaan reset password kembali.',
        );
      }

      // Update password resmi di Supabase Auth
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      // Sign out agar sesi recovery selesai dan pengguna masuk dengan kredensial baru
      try {
        await supabase.auth.signOut();
      } catch (_) {}

      if (!mounted) return;
      setState(() => isSuccess = true);
    } on AuthException catch (e) {
      showMessage(e.message);
    } catch (e) {
      showMessage('Gagal memperbarui kata sandi: $e');
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

  Widget _buildValidationRow({
    required bool isValid,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            isValid
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: isValid
                ? AppColors.statusCompleted
                : AppColors.muted(context).withAlpha(150),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isValid ? FontWeight.w600 : FontWeight.w500,
              color: isValid
                  ? AppColors.text(context)
                  : AppColors.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final displayEmail = widget.targetEmail ?? user?.email;

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
          bannerSubtitle:
              'Buat kata sandi baru yang aman untuk melindungi akun RestoKasir Anda.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(
                title: 'Buat Kata Sandi Baru',
                subtitle:
                    'Masukkan kata sandi baru yang kuat untuk akun RestoKasir Anda.',
              ),
              if (displayEmail != null && displayEmail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Akun: $displayEmail',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (!isSuccess) ...[
                AuthField(
                  controller: newPasswordController,
                  label: 'Password Baru',
                  hint: 'Minimal 6 karakter kombinasi huruf & angka',
                  icon: Icons.lock_outline_rounded,
                  obscureText: hideNewPassword,
                  suffix: IconButton(
                    onPressed: () =>
                        setState(() => hideNewPassword = !hideNewPassword),
                    icon: Icon(
                      hideNewPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                PasswordStrengthIndicator(password: newPassword),
                const SizedBox(height: 16),
                AuthField(
                  controller: confirmPasswordController,
                  label: 'Konfirmasi Password Baru',
                  hint: 'Ketik ulang password baru Anda',
                  icon: Icons.lock_reset_rounded,
                  obscureText: hideConfirmPassword,
                  suffix: IconButton(
                    onPressed: () => setState(
                        () => hideConfirmPassword = !hideConfirmPassword),
                    icon: Icon(
                      hideConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Indikator checklist validasi password
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildValidationRow(
                        isValid: hasMinLength,
                        label: 'Minimal 6 karakter',
                      ),
                      _buildValidationRow(
                        isValid: hasLettersAndNumbers,
                        label: 'Mengandung kombinasi huruf & angka',
                      ),
                      _buildValidationRow(
                        isValid: passwordsMatch,
                        label: 'Konfirmasi kata sandi cocok',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  text: 'Simpan Password Baru',
                  onPressed: (loading || !isFormValid) ? null : updatePassword,
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
                          color: AppColors.statusCompleted.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.statusCompleted,
                          size: 52,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Kata Sandi Berhasil Diperbarui',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kredensial akun RestoKasir Anda telah berhasil diperbarui di Supabase. Anda dapat langsung masuk dengan kata sandi baru.',
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
                const SizedBox(height: 24),
                PrimaryButton(
                  text: 'Masuk dengan Kata Sandi Baru',
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
