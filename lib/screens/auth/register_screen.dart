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

  String selectedRole = 'kasir'; // 'kasir', 'admin', 'owner'
  bool hidePassword = true;
  bool loading = false;

  final Map<String, String> roleLabels = {
    'kasir': 'Kasir (Operator POS)',
    'admin': 'Admin (Manajer Resto & Stok)',
    'owner': 'Owner (Pemilik & Laporan Keuangan)',
  };

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
          'role': selectedRole,
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

      // Karena "Confirm email" sudah dinonaktifkan di Supabase,
      // akun langsung aktif dan profil langsung disimpan ke tabel profiles:
      try {
        await supabase.from('profiles').upsert({
          'id': user.id,
          'full_name': name,
          'email': email,
          'role': selectedRole,
          'resto_id': null,
        });
      } catch (profileError) {
        debugPrint('Catatan upsert profiles saat register: $profileError');
      }

      // Logout dari sesi sementara agar user login secara mandiri di LoginScreen
      await supabase.auth.signOut();

      if (!mounted) return;

      showMessage('Akun ${roleLabels[selectedRole]} berhasil dibuat! Silakan masuk.');
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
        bannerTitle: 'Bergabung dengan RestoKasir',
        bannerSubtitle:
            'Daftarkan akun Owner, Admin, atau Kasir untuk mengelola operasional dan penjualan restoran kamu secara nyata.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandHeader(
              title: 'Buat akun baru',
              subtitle:
                  'Daftar akun kasir, admin, atau owner restoran dalam satu sistem terintegrasi.',
              showLogo: false,
            ),
            const SizedBox(height: 24),
            AuthField(
              controller: nameController,
              label: 'Nama lengkap',
              hint: 'Nama kamu',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 14),
            AuthField(
              controller: usernameController,
              label: 'Username',
              hint: 'contoh: resto_awrel',
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
            // Role Selector Dropdown
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Peran Akun',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedRole,
                      isExpanded: true,
                      dropdownColor: AppColors.card(context),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                      ),
                      items: roleLabels.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.text(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => selectedRole = val);
                      },
                    ),
                  ),
                ),
              ],
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
              text: 'Daftar Akun ${selectedRole.toUpperCase()}',
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
                      'Masuk',
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
