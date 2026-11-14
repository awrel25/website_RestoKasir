import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/screens/auth/reset_password_screen.dart';

class ResetPasswordOtpScreen extends StatefulWidget {
  final String email;

  const ResetPasswordOtpScreen({
    super.key,
    required this.email,
  });

  @override
  State<ResetPasswordOtpScreen> createState() =>
      _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends State<ResetPasswordOtpScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController otpController = TextEditingController();
  final FocusNode otpFocusNode = FocusNode();

  Timer? timer;
  bool loading = false;
  bool canResend = false;
  int countdownSeconds = 60;
  String otpCode = '';
  int remainingAttempts = 5;

  @override
  void initState() {
    super.initState();
    _startResendTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        otpFocusNode.requestFocus();
      }
    });
  }

  // ============================================================
  // TIMER RESEND OTP (60 DETIK)
  // ============================================================

  void _startResendTimer() {
    timer?.cancel();
    countdownSeconds = 60;
    canResend = false;

    if (mounted) setState(() {});

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      if (countdownSeconds > 0) {
        setState(() {
          countdownSeconds--;
        });
      } else {
        setState(() {
          canResend = true;
        });
        t.cancel();
      }
    });
  }

  // ============================================================
  // RESEND OTP DENGAN SUPABASE AUTH
  // ============================================================

  Future<void> resendOtp() async {
    if (!canResend || loading) return;

    setState(() => loading = true);

    try {
      await supabase.auth.resetPasswordForEmail(widget.email);

      if (!mounted) return;

      otpController.clear();
      setState(() {
        otpCode = '';
        remainingAttempts = 5;
      });

      _startResendTimer();
      showMessage('Kode OTP baru telah dikirimkan ke ${widget.email}');
      otpFocusNode.requestFocus();
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('sending recovery email') ||
          msg.contains('unexpected_failure') ||
          msg.contains('error sending')) {
        showMessage(
          'Server email Supabase gagal mengirim: Kuota email gratis Supabase (3 email/jam) habis atau Custom SMTP belum aktif.',
        );
      } else if (msg.contains('rate limit')) {
        showMessage('Batas pengiriman OTP tercapai. Harap tunggu beberapa menit.');
      } else {
        showMessage(e.message);
      }
    } catch (e) {
      showMessage('Gagal mengirim ulang kode OTP: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ============================================================
  // VERIFIKASI OTP RESMI SUPABASE (OtpType.recovery)
  // ============================================================

  Future<void> verifyOtp() async {
    if (remainingAttempts <= 0) {
      showMessage('Batas percobaan verifikasi habis. Silakan kirim ulang kode OTP.');
      return;
    }

    final token = otpController.text.trim();

    if (token.length != 6 || !RegExp(r'^\d{6}$').hasMatch(token)) {
      showMessage('Kode OTP harus terdiri dari 6 digit angka.');
      return;
    }

    setState(() => loading = true);

    try {
      final response = await supabase.auth.verifyOTP(
        email: widget.email,
        token: token,
        type: OtpType.recovery,
      );

      if (response.session == null) {
        throw const AuthException('Sesi pemulihan gagal dibentuk oleh server.');
      }

      if (!mounted) return;

      showMessage('Kode OTP valid! Silakan atur kata sandi baru Anda.');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(targetEmail: widget.email),
        ),
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      setState(() {
        remainingAttempts = (remainingAttempts - 1).clamp(0, 5);
      });

      if (msg.contains('expired') || msg.contains('token has expired')) {
        showMessage('Kode OTP telah kedaluwarsa. Silakan tekan "Kirim Ulang Kode OTP".');
      } else if (msg.contains('invalid') || msg.contains('token is invalid') || msg.contains('token is not valid')) {
        if (remainingAttempts > 0) {
          showMessage('Kode OTP tidak sesuai. Sisa kesempatan: $remainingAttempts kali.');
        } else {
          showMessage('Kesempatan mencoba habis. Silakan kirim ulang kode OTP baru.');
        }
      } else {
        showMessage(e.message);
      }
    } catch (e) {
      showMessage('Verifikasi OTP gagal. Silakan periksa kembali koneksi internet Anda.');
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
  void dispose() {
    timer?.cancel();
    otpController.dispose();
    otpFocusNode.dispose();
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
          bannerTitle: 'Verifikasi Kode OTP',
          bannerSubtitle:
              'Masukkan kode verifikasi 6 digit yang dikirimkan ke email akun Anda.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(
                title: 'Verifikasi Kode OTP',
                subtitle: 'Masukkan 6 digit kode OTP yang telah dikirim ke:',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.email_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.email,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              OtpSixDigitField(
                controller: otpController,
                focusNode: otpFocusNode,
                onChanged: (value) {
                  setState(() => otpCode = value);
                  if (value.length == 6 && !loading) {
                    verifyOtp();
                  }
                },
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Kode OTP resmi Supabase (6 digit)',
                    style: TextStyle(
                      color: AppColors.muted(context),
                      fontSize: 12,
                    ),
                  ),
                  if (remainingAttempts < 5)
                    Text(
                      'Sisa coba: $remainingAttempts',
                      style: TextStyle(
                        color: remainingAttempts > 1
                            ? AppColors.amber
                            : AppColors.statusCancelled,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: 'Verifikasi & Lanjutkan',
                onPressed: (loading || otpCode.length != 6 || remainingAttempts <= 0)
                    ? null
                    : verifyOtp,
                loading: loading,
              ),
              const SizedBox(height: 20),
              Center(
                child: canResend
                    ? TextButton.icon(
                        onPressed: loading ? null : resendOtp,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        label: const Text(
                          'Kirim Ulang Kode OTP',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Kirim ulang kode dalam $countdownSeconds detik',
                            style: TextStyle(
                              color: AppColors.muted(context),
                              fontSize: 13,
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
}

// ============================================================
// WIDGET KOTAK INPUT 6 DIGIT OTP RESPONSIF
// ============================================================

class OtpSixDigitField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;

  const OtpSixDigitField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
  });

  @override
  State<OtpSixDigitField> createState() => _OtpSixDigitFieldState();
}

class _OtpSixDigitFieldState extends State<OtpSixDigitField> {
  static const int otpLength = 6;
  late final List<TextEditingController> controllers;
  late final List<FocusNode> nodes;

  @override
  void initState() {
    super.initState();
    controllers = List.generate(otpLength, (_) => TextEditingController());
    nodes = List.generate(otpLength, (_) => FocusNode());
  }

  String get code => controllers.map((c) => c.text).join();

  void _notifyChanged() {
    final value = code;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
    if (mounted) setState(() {});
  }

  void _handleChange(int index, String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    // Handle paste multiple digits
    if (digits.length > 1) {
      final limited = digits.length > otpLength ? digits.substring(0, otpLength) : digits;
      for (int i = 0; i < otpLength; i++) {
        controllers[i].clear();
      }
      for (int i = 0; i < limited.length; i++) {
        controllers[i].text = limited[i];
      }
      _notifyChanged();

      if (limited.length == otpLength) {
        FocusScope.of(context).unfocus();
      } else {
        nodes[limited.length].requestFocus();
      }
      return;
    }

    if (digits.isEmpty) {
      controllers[index].clear();
    } else {
      controllers[index].text = digits[0];
      if (index < otpLength - 1) {
        nodes[index + 1].requestFocus();
      } else {
        FocusScope.of(context).unfocus();
      }
    }

    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double spacing = constraints.maxWidth < 350 ? 4.0 : 8.0;
        final double boxWidth =
            (constraints.maxWidth - (spacing * (otpLength - 1))) / otpLength;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            otpLength,
            (index) {
              return Container(
                width: boxWidth,
                height: 58,
                margin: EdgeInsets.only(
                  right: index == otpLength - 1 ? 0 : spacing,
                ),
                child: TextField(
                  controller: controllers[index],
                  focusNode: nodes[index],
                  keyboardType: TextInputType.number,
                  textInputAction: index == otpLength - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text(context),
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surface(context),
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.border(context),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) => _handleChange(index, value),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final n in nodes) {
      n.dispose();
    }
    super.dispose();
  }
}
