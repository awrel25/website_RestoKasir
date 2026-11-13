import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/screens/auth/business_setup_screen.dart';
import 'package:my_app/services/auth_onboarding_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeRestaurantRecord {
  String id;
  String userId;
  String name;
  String category;
  String? address;
  String? phone;

  FakeRestaurantRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    this.address,
    this.phone,
  });
}

/// Penyimpanan onboarding tiruan di memori untuk menguji seluruh skenario Auth Google & Email.
class FakeOnboardingStore implements OnboardingStore {
  final Map<String, UserProfile> profiles = {};
  final Map<String, FakeRestaurantRecord> restaurantsById = {};
  int restaurantCreateCount = 0;

  bool throwNetworkOnProfile = false;
  bool throwNetworkOnSave = false;
  int _nextId = 1;

  void _checkNetwork(bool shouldFail) {
    if (shouldFail) {
      throw const SocketException('Tidak ada koneksi internet');
    }
  }

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    _checkNetwork(throwNetworkOnProfile);
    return profiles[userId];
  }

  @override
  Future<UserProfile> ensureProfile({
    required String userId,
    required String fullName,
    required String email,
    required String defaultRole,
  }) async {
    _checkNetwork(throwNetworkOnProfile);
    final existing = profiles[userId];
    if (existing != null) {
      return existing;
    }
    final created = UserProfile(
      id: userId,
      fullName: fullName,
      email: email,
      role: defaultRole,
      restoId: null,
    );
    profiles[userId] = created;
    return created;
  }

  @override
  Future<String?> findOwnedRestaurantId(String userId) async {
    _checkNetwork(throwNetworkOnProfile);
    for (final r in restaurantsById.values) {
      if (r.userId == userId) return r.id;
    }
    return null;
  }

  @override
  Future<bool> restaurantExists(String restoId) async {
    _checkNetwork(throwNetworkOnProfile);
    return restaurantsById.containsKey(restoId);
  }

  @override
  Future<void> linkProfileToRestaurant(String userId, String restoId) async {
    _checkNetwork(throwNetworkOnProfile);
    final existing = profiles[userId];
    if (existing != null) {
      profiles[userId] = existing.copyWith(restoId: restoId);
    }
  }

  @override
  Future<String> upsertRestaurantForUser({
    required String userId,
    required String name,
    required String category,
    String? address,
    String? phone,
  }) async {
    _checkNetwork(throwNetworkOnSave);

    final existingId = await findOwnedRestaurantId(userId);
    if (existingId != null) {
      final record = restaurantsById[existingId]!;
      record.name = name.trim();
      record.category = category.trim();
      record.address = address?.trim();
      record.phone = phone?.trim();
      await linkProfileToRestaurant(userId, existingId);
      return existingId;
    }

    final newId = 'resto-${_nextId++}';
    restaurantCreateCount += 1;
    restaurantsById[newId] = FakeRestaurantRecord(
      id: newId,
      userId: userId,
      name: name.trim(),
      category: category.trim(),
      address: address?.trim(),
      phone: phone?.trim(),
    );
    await linkProfileToRestaurant(userId, newId);
    return newId;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Alur Onboarding Google Auth & Email/Password', () {
    late FakeOnboardingStore store;
    late AuthOnboardingService service;

    setUp(() {
      store = FakeOnboardingStore();
      service = AuthOnboardingService(store: store);
    });

    test('1-2-4-5. Login Google akun baru -> wajib ke form resto -> simpan -> login ulang langsung masuk dashboard', () async {
      // Login Google pertama kali (tanpa metadata role & belum ada resto)
      final firstLogin = await service.resolveAfterSignIn(
        userId: 'google-uid-1',
        email: 'baru@gmail.com',
        fallbackName: 'Pemilik Baru',
      );

      expect(firstLogin.status, OnboardingStatus.needsBusinessSetup);
      expect(firstLogin.hasRestaurant, isFalse);
      expect(store.profiles['google-uid-1']?.restoId, isNull);
      expect(store.restaurantsById, isEmpty);

      // Pengguna menutup/membatalkan pengisian form lalu membuka ulang app saat sesi aktif
      final reopened = await service.resolveAfterSignIn(
        userId: 'google-uid-1',
        email: 'baru@gmail.com',
      );
      expect(reopened.status, OnboardingStatus.needsBusinessSetup);
      expect(reopened.hasRestaurant, isFalse);

      // Pengguna mengisi dan menyimpan identitas restoran
      final restoId = await service.saveRestaurantForUser(
        userId: 'google-uid-1',
        name: 'Resto Nusantara Google',
        category: 'Restoran / Kafe',
        address: 'Jl. Mawar No. 10',
        phone: '08123456789',
      );
      expect(restoId, 'resto-1');
      expect(store.restaurantCreateCount, 1);

      // Logout dan login kembali memakai akun Google yang sama
      final secondLogin = await service.resolveAfterSignIn(
        userId: 'google-uid-1',
        email: 'baru@gmail.com',
        fallbackName: 'Pemilik Baru',
      );
      expect(secondLogin.status, OnboardingStatus.readyForDashboard);
      expect(secondLogin.hasRestaurant, isTrue);
      expect(secondLogin.restoId, 'resto-1');
      // Tidak membuat restoran baru atau profil duplikat
      expect(store.restaurantCreateCount, 1);
    });

    test('6-7. Login Email/Password baru (owner/admin/kasir tanpa resto) tetap diarahkan ke form resto lalu dashboard setelah simpan', () async {
      final firstEmailLogin = await service.resolveAfterSignIn(
        userId: 'email-uid-1',
        email: 'kasirbaru@resto.com',
        userMetadata: {'full_name': 'Kasir Baru', 'role': 'kasir'},
      );
      expect(firstEmailLogin.status, OnboardingStatus.needsBusinessSetup);
      expect(firstEmailLogin.profile?.role, 'kasir');

      await service.saveRestaurantForUser(
        userId: 'email-uid-1',
        name: 'Kedai Email',
        category: 'Kedai Kopi / Warkop',
        address: 'Jl. Kenanga No. 2',
        phone: '08987654321',
      );

      final secondEmailLogin = await service.resolveAfterSignIn(
        userId: 'email-uid-1',
        email: 'kasirbaru@resto.com',
      );
      expect(secondEmailLogin.status, OnboardingStatus.readyForDashboard);
      expect(secondEmailLogin.profile?.role, 'kasir');
    });

    test('8. Anti-duplikasi & self-heal: satu user tidak dapat membuat restoran ganda dan profil tanpa resto_id otomatis ditautkan', () async {
      // Simulasikan restoran sudah dibuat atas user_id tapi profiles.resto_id tertinggal null
      store.profiles['uid-heal'] = UserProfile(
        id: 'uid-heal',
        fullName: 'Owner Heal',
        email: 'heal@gmail.com',
        role: 'owner',
        restoId: null,
      );
      store.restaurantsById['resto-existing'] = FakeRestaurantRecord(
        id: 'resto-existing',
        userId: 'uid-heal',
        name: 'Resto Lama',
        category: 'Restoran / Kafe',
      );

      final resolved = await service.resolveAfterSignIn(
        userId: 'uid-heal',
        email: 'heal@gmail.com',
      );
      expect(resolved.status, OnboardingStatus.readyForDashboard);
      expect(resolved.restoId, 'resto-existing');
      expect(store.profiles['uid-heal']?.restoId, 'resto-existing');

      // Simpan ulang tidak boleh membuat restoran kedua
      final savedAgainId = await service.saveRestaurantForUser(
        userId: 'uid-heal',
        name: 'Resto Lama Diperbarui',
        category: 'Restoran / Kafe',
        address: 'Jl. Baru No. 1',
        phone: '0811111111',
      );
      expect(savedAgainId, 'resto-existing');
      expect(store.restaurantsById.length, 1);
      expect(store.restaurantsById['resto-existing']?.name, 'Resto Lama Diperbarui');
    });

    test('Koneksi internet terputus saat pengecekan maupun penyimpanan melempar error tanpa menganggap tersimpan', () async {
      store.throwNetworkOnProfile = true;

      await expectLater(
        () => service.resolveAfterSignIn(
          userId: 'offline-uid',
          email: 'offline@gmail.com',
        ),
        throwsA(isA<SocketException>()),
      );

      store.throwNetworkOnProfile = false;
      final beforeSave = await service.resolveAfterSignIn(
        userId: 'offline-uid',
        email: 'offline@gmail.com',
      );
      expect(beforeSave.status, OnboardingStatus.needsBusinessSetup);

      store.throwNetworkOnSave = true;
      await expectLater(
        () => service.saveRestaurantForUser(
          userId: 'offline-uid',
          name: 'Resto Offline',
          category: 'Restoran / Kafe',
          address: 'Jl. Coba',
          phone: '081234',
        ),
        throwsA(isA<SocketException>()),
      );
      expect(store.restaurantsById, isEmpty);

      // Setelah koneksi pulih, pengguna bisa mencoba kembali tanpa login ulang
      store.throwNetworkOnSave = false;
      final savedId = await service.saveRestaurantForUser(
        userId: 'offline-uid',
        name: 'Resto Offline',
        category: 'Restoran / Kafe',
        address: 'Jl. Coba',
        phone: '081234',
      );
      expect(savedId, 'resto-1');
    });
  });

  group('Widget Form Identitas Restoran (BusinessSetupScreen)', () {
    testWidgets('Validasi wajib diisi, mempertahankan input saat gagal simpan, dan berhasil lanjut saat retry', (tester) async {
      bool shouldFail = true;
      bool navigated = false;
      final completer = Completer<String>();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeController.lightTheme,
          home: BusinessSetupScreen(
            initialOwnerName: 'Pengguna Google',
            onSaveRestaurant: ({
              required String name,
              required String category,
              String? address,
              String? phone,
            }) {
              if (shouldFail) {
                return Future.error(const SocketException('offline'));
              }
              return completer.future;
            },
            onSavedNavigate: () {
              navigated = true;
            },
          ),
        ),
      );

      // Tekan simpan saat form kosong -> pesan validasi tampil
      await tester.ensureVisible(find.text('Simpan dan Lanjutkan'));
      await tester.tap(find.text('Simpan dan Lanjutkan'));
      await tester.pump();

      expect(find.text('Nama usaha / resto wajib diisi.'), findsOneWidget);
      expect(find.text('Alamat usaha wajib diisi.'), findsOneWidget);
      expect(find.text('Nomor kontak usaha wajib diisi.'), findsOneWidget);

      // Isi seluruh kolom wajib
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contoh: Resto Nusantara Awrel'),
        'Resto Awrel Google',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contoh: Jl. Melati No. 45, Jakarta Selatan'),
        'Jl. Melati No. 45',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contoh: 081234567890'),
        '081234567890',
      );

      // Percobaan pertama gagal karena koneksi terputus
      await tester.ensureVisible(find.text('Simpan dan Lanjutkan'));
      await tester.tap(find.text('Simpan dan Lanjutkan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Koneksi internet terputus. Periksa jaringan Anda lalu coba lagi.'),
        findsOneWidget,
      );
      expect(navigated, isFalse);
      // Data input tetap terjaga agar bisa coba ulang tanpa re-auth Google
      expect(find.text('Resto Awrel Google'), findsOneWidget);

      // Tutup snackbar terlebih dahulu agar tombol dapat ditekan untuk retry
      ScaffoldMessenger.of(tester.element(find.byType(Form)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Percobaan kedua saat koneksi pulih -> menampilkan loading lalu navigasi
      shouldFail = false;
      await tester.ensureVisible(find.text('Simpan dan Lanjutkan'));
      await tester.tap(find.text('Simpan dan Lanjutkan'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete('resto-google-1');
      await tester.pumpAndSettle();
      expect(navigated, isTrue);
    });

    test('Deteksi kompatibilitas kolom/fungsi Postgrest yang dibungkus JSON mentah', () {
      const jsonWrappedMissingCol = PostgrestException(
        message:
            '{"code":"42703","details":null,"hint":null,"message":"column restaurants.user_id does not exist"}',
      );
      expect(
        SupabaseOnboardingStore.isMissingColumnError(
          jsonWrappedMissingCol,
          'user_id',
        ),
        isTrue,
      );

      const missingRpc = PostgrestException(
        message:
            '{"code":"PGRST202","message":"Could not find the function public.upsert_my_restaurant"}',
      );
      expect(
        SupabaseOnboardingStore.isMissingFunctionError(
          missingRpc,
          'upsert_my_restaurant',
        ),
        isTrue,
      );

      expect(
        AuthOnboardingService.formatFriendlyError(jsonWrappedMissingCol),
        'column restaurants.user_id does not exist',
      );
    });
  });
}

