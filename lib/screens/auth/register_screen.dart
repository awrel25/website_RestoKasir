import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/core/theme/auth_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final supabase = Supabase.instance.client;
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool hidePassword = true;
  bool loading = false;

  Future<void> register() async {
    final name = nameController.text.trim();
    final username = usernameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;

    if (name.isEmpty || username.isEmpty || email.isEmpty || password.isEmpty) {
      return showMessage('Semua field harus diisi.');
    }
    if (!email.contains('@') || !email.contains('.')) {
      return showMessage('Format email tidak valid.');
    }
    if (password.length < 6) {
      return showMessage('Password minimal 6 karakter.');
    }

    setState(() => loading = true);
    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
          'username': username,
        },
      );

      final user = response.user;

      // Deteksi jika email sudah pernah terdaftar di Supabase
      if (user != null && user.identities != null && user.identities!.isEmpty) {
        showMessage('Email $email sudah terdaftar. Silakan login menggunakan email tersebut.');
        return;
      }

      if (user == null) {
        showMessage('Gagal membuat akun. Silakan coba lagi.');
        return;
      }

      try {
        await supabase.from('profiles').upsert({
          'id': user.id,
          'full_name': name,
          'email': email,
          'role': 'kasir',
          'resto_id': null,
        });

        // Klaim undangan jika sebelumnya sudah diundang oleh Admin restoran
        try {
          await supabase.rpc('claim_staff_invitation', params: {
            'p_user_id': user.id,
            'p_email': email,
          });
        } catch (_) {}
      } catch (profileError) {
        debugPrint('Catatan upsert profiles saat register: $profileError');
      }

      // Logout dari sesi sementara agar user login secara mandiri di LoginScreen
      await supabase.auth.signOut();

      if (!mounted) return;

      showMessage('Akun berhasil dibuat! Silakan masuk.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('user already registered') ||
          msg.contains('already been registered') ||
          msg.contains('already in use') ||
          msg.contains('identity already exists')) {
        showMessage('Email $email sudah terdaftar. Silakan login atau gunakan email lain.');
      } else if (msg.contains('invalid email')) {
        showMessage('Format email tidak valid.');
      } else if (msg.contains('password')) {
        showMessage('Password tidak memenuhi syarat (minimal 6 karakter).');
      } else {
        showMessage('Gagal membuat akun: ${e.message}');
      }
    } catch (e) {
      debugPrint('REGISTER ERROR: $e');
      showMessage('Terjadi kesalahan saat membuat akun: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

  @override
  void dispose() {
    nameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
        bannerTitle: 'Daftar RestoKasir',
        bannerSubtitle: 'Sistem POS & Kasir Restoran',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandHeader(
              title: 'Buat Akun Baru',
              subtitle: 'Lengkapi data untuk mendaftar.',
              showLogo: false,
            ),
            const SizedBox(height: 24),
            AuthField(
              controller: nameController,
              label: 'Nama Lengkap',
              hint: 'Nama lengkap',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 14),
            AuthField(
              controller: usernameController,
              label: 'Username',
              hint: 'Username',
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 14),
            AuthField(
              controller: emailController,
              label: 'Email',
              hint: 'nama@email.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            AuthField(
              controller: passwordController,
              label: 'Password',
              hint: 'Minimal 6 karakter',
              icon: Icons.lock_outline_rounded,
              obscureText: hidePassword,
              suffix: IconButton(
                onPressed: () => setState(() => hidePassword = !hidePassword),
                icon: Icon(
                  hidePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              text: 'Daftar',
              onPressed: loading ? null : register,
              loading: loading,
            ),
            const SizedBox(height: 22),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    'Sudah punya akun? ',
                    style: TextStyle(color: AppColors.muted(context)),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text(
                      'Login',
                      style: TextStyle(
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
