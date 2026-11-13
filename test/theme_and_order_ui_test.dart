import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_app/core/routing/app_routes.dart';
import 'package:my_app/core/theme/auth_theme.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/screens/cashier/table_qr_dialog.dart';
import 'package:my_app/screens/cashier/qris_payment_dialog.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Tema Permanen & Tipografi Google Fonts RestoKasir', () {
    test('ThemeController memakai Figtree (400-800) dan AppFonts display memakai Bricolage Grotesque (600-800)', () {
      final light = ThemeController.lightTheme;

      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, AppColors.lightSurface);
      expect(light.colorScheme.primary, AppColors.primary);
      expect(light.colorScheme.secondary, AppColors.amber);

      expect(light.textTheme.bodyMedium?.fontFamily, contains('Figtree'));
      expect(light.textTheme.titleLarge?.fontFamily, contains('BricolageGrotesque'));
      expect(light.textTheme.headlineMedium?.fontFamily, contains('BricolageGrotesque'));
      expect(light.appBarTheme.titleTextStyle?.fontFamily, contains('BricolageGrotesque'));

      final displayStyle = AppFonts.display(fontWeight: FontWeight.w400);
      expect(displayStyle.fontFamily, contains('BricolageGrotesque'));
      expect(displayStyle.fontWeight, FontWeight.w600);

      final bodyStyle = AppFonts.body(fontWeight: FontWeight.w700);
      expect(bodyStyle.fontFamily, contains('Figtree'));
      expect(bodyStyle.fontWeight, FontWeight.w700);
    });

    testWidgets('ThemeController.isDark selalu false pada konteks gelap maupun terang',
        (tester) async {
      bool? darkCheck;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: Builder(
            builder: (context) {
              darkCheck = ThemeController.isDark(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(darkCheck, isFalse);
      expect(find.byIcon(Icons.dark_mode_rounded), findsNothing);
      expect(find.byIcon(Icons.light_mode_rounded), findsNothing);
    });
  });

  group('Redesain Halaman Login & Responsivitas', () {
    testWidgets('Render bersih pada HP 360x720 dengan error banner tanpa overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emailCtrl = TextEditingController();
      final passCtrl = TextEditingController();
      addTearDown(() {
        emailCtrl.dispose();
        passCtrl.dispose();
      });

      int tabIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ResponsiveAuthLayout(
                  bannerTitle: 'RestoKasir POS',
                  bannerSubtitle: 'Kelola transaksi kasir dan pesanan meja.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandHeader(
                        title: 'Masuk ke Akun',
                        subtitle: 'Gunakan akun staf atau pengelola restoran Anda.',
                      ),
                      const SizedBox(height: 16),
                      const AuthErrorBanner(
                        message: 'Email/Username atau password salah.',
                      ),
                      const SizedBox(height: 14),
                      AuthField(
                        controller: emailCtrl,
                        label: 'Email atau Username',
                        hint: 'nama@email.com',
                        icon: Icons.person_outline_rounded,
                        errorText: 'Email atau username harus diisi.',
                      ),
                      const SizedBox(height: 12),
                      AuthField(
                        controller: passCtrl,
                        label: 'Password',
                        hint: 'Masukkan password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: 14),
                      MethodTabToggle(
                        selectedIndex: tabIndex,
                        onChanged: (idx) => setState(() => tabIndex = idx),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        text: 'Masuk',
                        onPressed: () {},
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Masuk ke Akun'), findsOneWidget);
      expect(find.text('Email/Username atau password salah.'), findsOneWidget);
      expect(find.text('Email atau username harus diisi.'), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_rounded), findsNothing);
      expect(find.byIcon(Icons.light_mode_rounded), findsNothing);

      await tester.tap(find.text('Kode OTP'));
      await tester.pump();
      expect(tabIndex, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Render dua kolom proporsional pada desktop 1280x800',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: Scaffold(
            body: ResponsiveAuthLayout(
              bannerTitle: 'RestoKasir POS',
              bannerSubtitle: 'Pesanan meja terhubung ke kasir.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandHeader(
                    title: 'Masuk ke Akun',
                    subtitle: 'Gunakan akun staf atau pengelola restoran.',
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    text: 'Masuk',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('RESTOKASIR POS'), findsOneWidget);
      expect(find.text('RestoKasir POS'), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_rounded), findsNothing);
      expect(find.byIcon(Icons.light_mode_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Declarative AppRoutes', () {
    test('Semua rute utama terdaftar dan fallback aman', () {
      final map = AppRoutes.routes;
      expect(map.containsKey(AppRoutes.splash), isTrue);
      expect(map.containsKey(AppRoutes.login), isTrue);
      expect(map.containsKey(AppRoutes.register), isTrue);
      expect(map.containsKey(AppRoutes.forgotPassword), isTrue);
      expect(map.containsKey(AppRoutes.resetPassword), isTrue);
      expect(map.containsKey(AppRoutes.home), isTrue);
      expect(map.containsKey(AppRoutes.addProduct), isTrue);

      final fallback = AppRoutes.onGenerateRoute(
        const RouteSettings(name: '/tidak-dikenal'),
      );
      expect(fallback, isA<MaterialPageRoute<dynamic>>());
    });
  });

  group('URL QR Meja Pelanggan & QRIS Kasir', () {
    test('Setiap meja menghasilkan parameter URL unik berformat 2 digit', () {
      expect(
        TableQrDialog.buildTableMenuUrl(1),
        'https://awrel25.github.io/website_RestoKasir/?table=01',
      );
      expect(
        TableQrDialog.buildTableMenuUrl(2),
        'https://awrel25.github.io/website_RestoKasir/?table=02',
      );
      expect(
        TableQrDialog.buildTableMenuUrl(3, restoId: 'resto-abc'),
        'https://awrel25.github.io/website_RestoKasir/?table=03&resto=resto-abc',
      );
    });

    test('URL QRIS kamera kasir mengarah ke halaman web pay.html dan menyertakan parameter lengkap', () {
      final url = QrisPaymentDialog.buildQrisPaymentUrl(
        invoiceNo: 'INV-20261113-0001',
        totalAmount: 50000,
        restaurantName: 'Resto Enak',
        orderId: 'ord-123',
        referenceId: 'REF-999',
        tableNumber: 1,
      );

      expect(url, contains('https://awrel25.github.io/website_RestoKasir/pay.html'));
      expect(url, contains('inv=INV-20261113-0001'));
      expect(url, contains('amt=50000'));
      expect(url, contains('resto=Resto%20Enak'));
      expect(url, contains('id=ord-123'));
      expect(url, contains('ref=REF-999'));
      expect(url, contains('table=1'));
    });
  });

  group('Model DbOrder & Integrasi Pembayaran QR', () {
    test('Mem-parse order QR bayar kasir unpaid dan transisi paid', () {
      final unpaid = DbOrder.fromMap({
        'id': 'ord-1',
        'invoice_no': 'WEB-20261112-0001',
        'cashier_name': 'Meja 01 (Budi)',
        'table_number': 1,
        'subtotal': 30000,
        'service_fee': 1500,
        'total': 31500,
        'payment_method': 'CASHIER',
        'payment_status': 'unpaid',
        'order_source': 'qr',
        'status': 'pesanan dibuat',
      }, const []);

      expect(unpaid.isQrSource, isTrue);
      expect(unpaid.isPaid, isFalse);
      expect(unpaid.isDemoQris, isFalse);
      expect(unpaid.paymentStatus, 'unpaid');

      final paid = DbOrder.fromMap({
        'id': 'ord-1',
        'invoice_no': 'WEB-20261112-0001',
        'cashier_name': 'Meja 01 (Budi)',
        'table_number': 1,
        'subtotal': 30000,
        'service_fee': 1500,
        'total': 31500,
        'payment_method': 'CASHIER',
        'payment_status': 'paid',
        'order_source': 'qr',
        'status': 'pesanan selesai',
      }, const []);

      expect(paid.isPaid, isTrue);
      expect(paid.paymentStatus, 'paid');
    });

    test('Memisahkan status QRIS_DEMO dari transaksi produksi paid', () {
      final demoOrder = DbOrder.fromMap({
        'id': 'ord-2',
        'invoice_no': 'WEB-20261112-0002',
        'cashier_name': 'Meja 03 (Sari) [QRIS DEMO]',
        'table_number': 3,
        'subtotal': 20000,
        'service_fee': 1000,
        'total': 21000,
        'payment_method': 'QRIS_DEMO',
        'payment_status': 'demo_paid',
        'order_source': 'qr',
        'status': 'pesanan dibuat',
      }, const []);

      expect(demoOrder.isQrSource, isTrue);
      expect(demoOrder.isDemoQris, isTrue);
      expect(demoOrder.isDemoPaid, isTrue);
      expect(demoOrder.isPaid, isFalse);
    });
  });
}
