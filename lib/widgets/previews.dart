import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:my_app/core/theme/auth_theme.dart';

PreviewThemeData posThemeBuilder() {
  return PreviewThemeData(
    materialLight: ThemeController.lightTheme,
  );
}

final class PosPreview extends Preview {
  const PosPreview({
    required super.name,
    super.group = 'RestoKasir UI',
    super.size,
  }) : super(
          brightness: Brightness.light,
          theme: posThemeBuilder,
        );
}

void _noopPreviewTap() {}
void _noopTabChange(int _) {}

@PosPreview(name: 'Tombol Utama Orange', size: Size(340, 96))
Widget primaryButtonPreview() {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: PrimaryButton(
        text: 'Kirim Pesanan',
        onPressed: _noopPreviewTap,
      ),
    ),
  );
}

@PosPreview(name: 'Banner Error Login', size: Size(360, 96))
Widget authErrorBannerPreview() {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: AuthErrorBanner(
        message: 'Email/Username atau password salah.',
      ),
    ),
  );
}

@PosPreview(name: 'Tab Metode Reset', size: Size(340, 96))
Widget methodTabTogglePreview() {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: MethodTabToggle(
        selectedIndex: 0,
        onChanged: _noopTabChange,
      ),
    ),
  );
}

@PosPreview(name: 'Kartu Keterangan Meja Kasir', size: Size(360, 140))
Widget tableInstructionCardPreview() {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.primary.withAlpha(90)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.table_restaurant_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Meja 4 - Sebutkan ke Kasir',
                style: AppFonts.display(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.lightText,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Sebutkan nomor meja ke kasir untuk dicek di aplikasi kasir.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.lightMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
