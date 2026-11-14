import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/screens/auth/forgot_password_screen.dart';
import 'package:my_app/screens/auth/reset_password_otp_screen.dart';
import 'package:my_app/screens/auth/reset_password_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await Supabase.initialize(
        url: 'https://uinumtttwkwlurvqvidh.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbnVtdHR0d2t3bHVydnF2aWRoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2OTUxNTcsImV4cCI6MjEwMDI3MTE1N30.eSfjbxge6LA8fIqP9Cnepld7s4PgQgh_Eqi3O58DI1M',
      );
    } catch (_) {}
  });

  group('Pengujian Sistem Reset Password RestoKasir', () {
    testWidgets('ForgotPasswordScreen menampilkan toggle metode Link Email dan Kode OTP',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: const ForgotPasswordScreen(),
        ),
      );

      expect(find.text('Reset Kata Sandi'), findsWidgets);
      expect(find.text('Email Terdaftar'), findsOneWidget);
      expect(find.text('Link Email'), findsOneWidget);
      expect(find.text('Kode OTP'), findsOneWidget);
      expect(find.text('Kirim Link Reset via Email'), findsOneWidget);

      // Beralih ke metode Kode OTP
      await tester.tap(find.text('Kode OTP'));
      await tester.pumpAndSettle();

      expect(find.text('Kirim Kode OTP via Email'), findsOneWidget);
    });

    testWidgets('ResetPasswordOtpScreen menampilkan input 6-digit OTP dan countdown timer',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: const ResetPasswordOtpScreen(
            email: 'kasir@restoran.com',
          ),
        ),
      );

      expect(find.text('Verifikasi Kode OTP'), findsWidgets);
      expect(find.text('kasir@restoran.com'), findsOneWidget);
      expect(find.byType(OtpSixDigitField), findsOneWidget);
      expect(find.text('Verifikasi & Lanjutkan'), findsOneWidget);

      // Tombol dinonaktifkan jika belum 6 digit
      final submitBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Verifikasi & Lanjutkan'),
      );
      expect(submitBtn.onPressed, isNull);
    });

    testWidgets('ResetPasswordScreen memvalidasi panjang password, angka, dan kecocokan konfirmasi',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: const ResetPasswordScreen(
            targetEmail: 'owner@restokasir.com',
          ),
        ),
      );

      expect(find.text('Buat Kata Sandi Baru'), findsWidgets);
      expect(find.text('Password Baru'), findsOneWidget);
      expect(find.text('Konfirmasi Password Baru'), findsOneWidget);

      // Kriteria checklist terlihat
      expect(find.text('Minimal 6 karakter'), findsOneWidget);
      expect(find.text('Mengandung kombinasi huruf & angka'), findsOneWidget);
      expect(find.text('Konfirmasi kata sandi cocok'), findsOneWidget);

      // Awalnya tombol Simpan dinonaktifkan
      final initialBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Simpan Password Baru'),
      );
      expect(initialBtn.onPressed, isNull);

      // Masukkan password yang tidak cocok
      await tester.enterText(find.byType(TextField).at(0), 'Resto123');
      await tester.enterText(find.byType(TextField).at(1), 'Beda123');
      await tester.pumpAndSettle();

      final mismatchedBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Simpan Password Baru'),
      );
      expect(mismatchedBtn.onPressed, isNull);

      // Masukkan password yang cocok dan memenuhi syarat
      await tester.enterText(find.byType(TextField).at(1), 'Resto123');
      await tester.pumpAndSettle();

      final validBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Simpan Password Baru'),
      );
      expect(validBtn.onPressed, isNotNull);
    });
  });
}
