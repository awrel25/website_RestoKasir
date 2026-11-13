import 'package:flutter/material.dart';
import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/screens/home/home_screen.dart';
import 'package:my_app/services/auth_onboarding_service.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SaveRestaurantCallback = Future<String> Function({
  required String name,
  required String category,
  String? address,
  String? phone,
});

class BusinessSetupScreen extends StatefulWidget {
  final String? initialOwnerName;
  final SaveRestaurantCallback? onSaveRestaurant;
  final VoidCallback? onSavedNavigate;

  const BusinessSetupScreen({
    super.key,
    this.initialOwnerName,
    this.onSaveRestaurant,
    this.onSavedNavigate,
  });

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  PosService? _posService;

  PosService get _service => _posService ??= PosService();

  String _selectedCategory = 'Restoran / Kafe';
  bool _isLoading = false;

  final List<String> _categories = [
    'Restoran / Kafe',
    'Kedai Kopi / Warkop',
    'Rumah Makan Tradisional',
    'Fast Food & Street Food',
    'Bakery & Pastry',
    'Food Truck / Stand',
    'Retail / Minimarket',
    'Usaha Lainnya',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final saver = widget.onSaveRestaurant ?? _service.registerRestaurant;
      await saver(
        name: _nameController.text.trim(),
        category: _selectedCategory,
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restoran "${_nameController.text.trim()}" berhasil disimpan.',
          ),
          backgroundColor: AppColors.statusCompleted,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (widget.onSavedNavigate != null) {
        widget.onSavedNavigate!();
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final friendly = AuthOnboardingService.formatFriendlyError(
        e,
        fallback: 'Gagal menyimpan identitas usaha: $e',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendly),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final mutedColor = isDark ? AppColors.darkMuted : AppColors.lightMuted;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shape: const Border(),
          automaticallyImplyLeading: false,
          actions: [
            TextButton.icon(
              onPressed: _isLoading ? null : _logout,
              icon: const Icon(
                Icons.logout_rounded,
                color: AppColors.statusCancelled,
                size: 20,
              ),
              label: const Text(
                'Keluar',
                style: TextStyle(
                  color: AppColors.statusCancelled,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1.2),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Logo & Title
                      Center(
                        child: Column(
                          children: [
                            const AppLogo(size: 64, borderRadius: 18),
                            const SizedBox(height: 16),
                            Text(
                              'Identitas Usaha',
                              textAlign: TextAlign.center,
                              style: AppFonts.display(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Lengkapi data restoran Anda sebelum mulai menggunakan aplikasi kasir dan daftar menu.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: mutedColor,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Field: Nama Resto / Usaha
                      _buildLabel('Nama Usaha / Resto *', textColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          hint: 'Contoh: Resto Nusantara Awrel',
                          icon: Icons.storefront_rounded,
                          isDark: isDark,
                          borderColor: borderColor,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Nama usaha / resto wajib diisi.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Field: Kategori Usaha
                      _buildLabel('Kategori Usaha *', textColor),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCategory,
                            isExpanded: true,
                            dropdownColor: isDark
                                ? AppColors.darkSurface
                                : Colors.white,
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.primary,
                            ),
                            items: _categories.map((c) {
                              return DropdownMenuItem<String>(
                                value: c,
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCategory = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Field: Alamat Lengkap
                      _buildLabel('Alamat Lengkap Usaha *', textColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: _inputDecoration(
                          hint: 'Contoh: Jl. Melati No. 45, Jakarta Selatan',
                          icon: Icons.location_on_outlined,
                          isDark: isDark,
                          borderColor: borderColor,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Alamat usaha wajib diisi.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Field: Nomor WhatsApp / Telepon
                      _buildLabel('No. WhatsApp / Telepon *', textColor),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          hint: 'Contoh: 081234567890',
                          icon: Icons.phone_android_rounded,
                          isDark: isDark,
                          borderColor: borderColor,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Nomor kontak usaha wajib diisi.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Simpan dan Lanjutkan',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildLabel(String text, Color color) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
    required Color borderColor,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
      filled: true,
      fillColor: isDark ? AppColors.darkSurface : Colors.white,
      hintStyle: TextStyle(
        fontSize: 13,
        color: isDark
            ? AppColors.darkMuted.withOpacity(0.6)
            : AppColors.lightMuted,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
    );
  }
}
