import 'package:flutter/material.dart';
import 'package:my_app/core/theme/theme_controller.dart';
export 'package:my_app/core/theme/theme_controller.dart';

// Token warna auth selaras dengan palet utama (Orange, Kuning, Putih / Hitam)
const Color kPrimary = AppColors.primary;
const Color kPrimaryDark = AppColors.primaryDark;
const Color kPrimaryLight = AppColors.yellowSoft;
const Color kSurfaceTint = AppColors.lightSurface;
const Color kBorder = AppColors.lightBorder;
const Color kBackground = AppColors.lightBg;
const Color kText = AppColors.lightText;
const Color kMuted = AppColors.lightMuted;

class AuthTheme {
  static ThemeData theme() => ThemeController.lightTheme;
}

class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showShadow;

  const AppLogo({
    super.key,
    this.size = 64,
    this.borderRadius = 16,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderCol = AppColors.border(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderCol, width: 1),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1),
        child: Image.asset(
          'assets/image/app_logo.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: size * 0.48,
          ),
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final double logoSize;
  final bool showLogo;

  const BrandHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.logoSize = 48,
    this.showLogo = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final shouldShowLogo = showLogo && !isDesktop;
    final titleColor = AppColors.text(context);
    final subColor = AppColors.muted(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shouldShowLogo) ...[
          Row(
            children: [
              AppLogo(size: logoSize, borderRadius: logoSize * 0.25),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RestoKasir',
                    style: AppFonts.display(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Sistem Kasir & POS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text(
          title,
          style: AppFonts.display(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: titleColor,
            letterSpacing: -0.4,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: subColor,
          ),
        ),
      ],
    );
  }
}

class ResponsiveAuthLayout extends StatelessWidget {
  final Widget child;
  final String? bannerTitle;
  final String? bannerSubtitle;

  const ResponsiveAuthLayout({
    super.key,
    required this.child,
    this.bannerTitle,
    this.bannerSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.lightSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;

          // Mobile / Tablet: kartu putih proporsional di tengah latar off-white
          if (!isDesktop) {
            final compact = constraints.maxWidth < 400;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 24,
                  vertical: compact ? 20 : 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: EdgeInsets.all(compact ? 22 : 28),
                    decoration: BoxDecoration(
                      color: AppColors.lightCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.lightBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          }

          // Desktop: panel kiri aksen gelap elegan + panel form putih proporsional
          const panelBg = AppColors.lightText;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 860),
                decoration: BoxDecoration(
                  color: AppColors.lightCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.lightBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(36),
                          decoration: const BoxDecoration(
                            color: panelBg,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(19),
                              bottomLeft: Radius.circular(19),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppLogo(
                                size: 48,
                                borderRadius: 12,
                                showShadow: false,
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: const Text(
                                  'RESTOKASIR POS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                bannerTitle ?? 'RestoKasir',
                                style: AppFonts.display(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                bannerSubtitle ??
                                    'Kelola transaksi kasir, pesanan meja QR, dan stok restoran secara terpadu.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: Colors.white.withValues(alpha: 0.74),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              const SizedBox(height: 22),
                              const _FeatureItem(
                                icon: Icons.point_of_sale_outlined,
                                label: 'Kasir dan cetak struk cepat',
                              ),
                              const SizedBox(height: 12),
                              const _FeatureItem(
                                icon: Icons.qr_code_2_rounded,
                                label: 'Pesanan meja QR otomatis masuk',
                              ),
                              const SizedBox(height: 12),
                              const _FeatureItem(
                                icon: Icons.bar_chart_rounded,
                                label: 'Laporan penjualan harian akurat',
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 38,
                          ),
                          child: Center(child: child),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.primaryLight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: AppColors.statusCancelled,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF991B1B),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final mutedColor = AppColors.muted(context);
    final fieldBg = AppColors.surface(context);
    final borderColor = AppColors.border(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction ?? TextInputAction.next,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            errorMaxLines: 2,
            hintStyle: TextStyle(color: mutedColor, fontSize: 13.5),
            prefixIcon: Icon(icon, size: 19, color: mutedColor),
            suffixIcon: suffix,
            filled: true,
            fillColor: fieldBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: AppColors.statusCancelled),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(
                color: AppColors.statusCancelled,
                width: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final disabledBg = AppColors.border(context);
    final disabledFg = AppColors.muted(context);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: disabled ? disabledBg : AppColors.primary,
          disabledBackgroundColor: disabledBg,
          foregroundColor: Colors.white,
          disabledForegroundColor: disabledFg,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final border = AppColors.border(context);
    final muted = AppColors.muted(context);

    return Row(
      children: [
        Expanded(child: Divider(color: border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'atau',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: border)),
      ],
    );
  }
}

class MethodTabToggle extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const MethodTabToggle({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Link Email',
              icon: Icons.mail_outline_rounded,
              isSelected: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Kode OTP',
              icon: Icons.pin_outlined,
              isSelected: selectedIndex == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBg = AppColors.card(context);
    final textCol = AppColors.text(context);
    final mutedCol = AppColors.muted(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: isSelected
              ? Border.all(color: AppColors.border(context))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : mutedCol,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? textCol : mutedCol,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OtpInputField extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;

  const OtpInputField({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.onChanged,
  });

  @override
  State<OtpInputField> createState() => OtpInputFieldState();
}

class OtpInputFieldState extends State<OtpInputField> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get code => _controllers.map((c) => c.text).join();

  void clear() {
    for (var c in _controllers) {
      c.clear();
    }
    if (_focusNodes.isNotEmpty) _focusNodes[0].requestFocus();
  }

  void _onFieldChanged(String value, int index) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < widget.length; i++) {
        if (i < digits.length) _controllers[i].text = digits[i];
      }
      if (digits.length >= widget.length) {
        _focusNodes[widget.length - 1].unfocus();
        widget.onCompleted(code);
      } else {
        _focusNodes[digits.length].requestFocus();
      }
    } else if (value.isNotEmpty) {
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    final currentCode = code;
    widget.onChanged?.call(currentCode);
    if (currentCode.length == widget.length) {
      widget.onCompleted(currentCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textCol = AppColors.text(context);
    final fieldBg = AppColors.surface(context);
    final borderCol = AppColors.border(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
        const double itemSpacing = 8.0;
        final double totalSpacing = itemSpacing * (widget.length - 1);
        final double itemWidth =
            ((availableWidth - totalSpacing) / widget.length).clamp(36.0, 50.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (index) {
            return Container(
              margin: EdgeInsets.only(
                right: index < widget.length - 1 ? itemSpacing : 0,
              ),
              width: itemWidth,
              height: 52,
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textCol,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  filled: true,
                  fillColor: fieldBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.6),
                  ),
                ),
                onChanged: (val) => _onFieldChanged(val, index),
              ),
            );
          }),
        );
      },
    );
  }
}

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  double _calculateScore() {
    if (password.isEmpty) return 0.0;
    double score = 0.0;
    if (password.length >= 6) score += 0.33;
    if (password.length >= 8) score += 0.33;
    if (RegExp(r'[A-Z]').hasMatch(password) ||
        RegExp(r'[0-9]').hasMatch(password) ||
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      score += 0.34;
    }
    return score.clamp(0.0, 1.0);
  }

  String _getLabel(double score) {
    if (password.isEmpty) return '';
    if (score < 0.34) return 'Lemah';
    if (score < 0.67) return 'Sedang';
    return 'Kuat';
  }

  Color _getColor(double score) {
    if (score < 0.34) return AppColors.statusCancelled;
    if (score < 0.67) return AppColors.amber;
    return AppColors.statusCompleted;
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final score = _calculateScore();
    final label = _getLabel(score);
    final color = _getColor(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: score,
                  backgroundColor: AppColors.border(context),
                  color: color,
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
