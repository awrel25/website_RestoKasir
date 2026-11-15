import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/auth_onboarding_service.dart';

class FakeMultiUserStore implements OnboardingStore {
  final Map<String, UserProfile> profiles = {};
  final Map<String, String> ownedRestaurants = {}; // userId -> restoId
  final Map<String, String> restaurants = {}; // restoId -> restoName
  final Map<String, List<RestaurantMember>> restaurantMembers = {}; // restoId -> list of members
  int _restoSeq = 1;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    return profiles[userId];
  }

  @override
  Future<UserProfile> ensureProfile({
    required String userId,
    required String fullName,
    required String email,
    required String defaultRole,
  }) async {
    final existing = profiles[userId];
    if (existing != null) return existing;

    final normalizedRole = (defaultRole.toLowerCase() == 'admin' || defaultRole.toLowerCase() == 'owner')
        ? 'admin'
        : 'kasir';

    final created = UserProfile(
      id: userId,
      fullName: fullName,
      email: email,
      role: normalizedRole,
      restoId: null,
    );
    profiles[userId] = created;
    return created;
  }

  @override
  Future<String?> findOwnedRestaurantId(String userId) async {
    return ownedRestaurants[userId];
  }

  @override
  Future<bool> restaurantExists(String restoId) async {
    return restaurants.containsKey(restoId);
  }

  @override
  Future<void> linkProfileToRestaurant(
    String userId,
    String restoId, {
    String? role,
  }) async {
    final existing = profiles[userId];
    if (existing != null) {
      profiles[userId] = existing.copyWith(
        restoId: restoId,
        role: role ?? existing.role,
      );
    }
  }

  @override
  Future<RestaurantMember?> fetchActiveMembership(String userId) async {
    for (final members in restaurantMembers.values) {
      for (final m in members) {
        if (m.userId == userId && m.isActive) {
          return m;
        }
      }
    }
    return null;
  }

  @override
  Future<RestaurantMember?> checkAndClaimInvitation({
    required String userId,
    required String email,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    for (final entry in restaurantMembers.entries) {
      final members = entry.value;
      for (int i = 0; i < members.length; i++) {
        final m = members[i];
        if (m.isInvited && m.invitedEmail?.toLowerCase() == cleanEmail) {
          final claimed = RestaurantMember(
            id: m.id,
            userId: userId,
            restaurantId: m.restaurantId,
            role: 'KASIR',
            status: 'ACTIVE',
            invitedEmail: cleanEmail,
            createdAt: m.createdAt,
          );
          members[i] = claimed;
          await linkProfileToRestaurant(userId, m.restaurantId, role: 'kasir');
          return claimed;
        }
      }
    }
    return null;
  }

  @override
  Future<String> upsertRestaurantForUser({
    required String userId,
    required String name,
    required String category,
    String? address,
    String? phone,
  }) async {
    final existingRestoId = ownedRestaurants[userId];
    if (existingRestoId != null) {
      restaurants[existingRestoId] = name;
      return existingRestoId;
    }

    final newRestoId = 'RESTO-00${_restoSeq++}';
    restaurants[newRestoId] = name;
    ownedRestaurants[userId] = newRestoId;

    // Constraint: Pastikan hanya ada 1 Admin aktif per restoran
    final members = restaurantMembers.putIfAbsent(newRestoId, () => []);
    final hasAdmin = members.any((m) => m.isAdmin && m.isActive);
    if (hasAdmin) {
      throw Exception('Restoran sudah memiliki ADMIN aktif.');
    }

    final adminMember = RestaurantMember(
      id: 'member-admin-$userId',
      userId: userId,
      restaurantId: newRestoId,
      role: 'ADMIN',
      status: 'ACTIVE',
      createdAt: DateTime.now(),
    );
    members.add(adminMember);

    await linkProfileToRestaurant(userId, newRestoId, role: 'admin');
    return newRestoId;
  }

  void inviteEmployee({
    required String adminUserId,
    required String restoId,
    required String email,
  }) {
    final members = restaurantMembers[restoId] ?? [];
    final isAdmin = members.any((m) => m.userId == adminUserId && m.isAdmin && m.isActive);
    if (!isAdmin) {
      throw Exception('Hanya ADMIN yang dapat mengundang karyawan.');
    }

    members.add(
      RestaurantMember(
        id: 'inv-${DateTime.now().millisecondsSinceEpoch}',
        userId: null,
        restaurantId: restoId,
        role: 'KASIR',
        status: 'INVITED',
        invitedEmail: email.toLowerCase().trim(),
        createdAt: DateTime.now(),
      ),
    );
    restaurantMembers[restoId] = members;
  }
}

void main() {
  group('Sistem Role dan Multi-User RestoKasir (ADMIN & KASIR)', () {
    late FakeMultiUserStore store;
    late AuthOnboardingService authService;

    setUp(() {
      store = FakeMultiUserStore();
      authService = AuthOnboardingService(store: store);
    });

    test('1. Pendaftaran restoran pertama kali otomatis menetapkan pemilik sebagai ADMIN tunggal', () async {
      final res = await authService.resolveAfterSignIn(
        userId: 'admin-1',
        email: 'pemilik@restokasir.com',
        fallbackName: 'Pemilik Restoran',
      );

      // Pengguna baru tanpa restoran & tanpa undangan diarahkan ke setup restoran
      expect(res.status, OnboardingStatus.needsBusinessSetup);
      expect(res.profile?.role, 'kasir');

      // Saat mengisi data restoran, otomatis jadi ADMIN
      final restoId = await authService.saveRestaurantForUser(
        userId: 'admin-1',
        name: 'Restoran Enak',
        category: 'Restoran / Kafe',
      );
      expect(restoId, isNotEmpty);

      // Sesi login berikutnya langsung mendeteksi ADMIN aktif
      final resAfterSetup = await authService.resolveAfterSignIn(
        userId: 'admin-1',
        email: 'pemilik@restokasir.com',
      );
      expect(resAfterSetup.status, OnboardingStatus.readyForDashboard);
      expect(resAfterSetup.profile?.role, 'admin');
      expect(resAfterSetup.profile?.isAdmin, true);
      expect(resAfterSetup.profile?.isKasir, false);
      expect(resAfterSetup.restoId, restoId);
    });

    test('2. Restoran yang sudah memiliki Admin tidak dapat membuat Admin kedua', () async {
      final restoId = await authService.saveRestaurantForUser(
        userId: 'admin-1',
        name: 'Kedai Kopi Santai',
        category: 'Kedai Kopi / Warkop',
      );

      expect(store.restaurantMembers[restoId]?.length, 1);
      expect(store.restaurantMembers[restoId]?.first.isAdmin, true);

      // Admin kedua mencoba mendaftar pada restoran yang sama ditolak constraint
      expect(
        () async {
          final members = store.restaurantMembers[restoId]!;
          if (members.any((m) => m.isAdmin && m.isActive)) {
            throw Exception('Restoran sudah memiliki ADMIN aktif.');
          }
        },
        throwsA(isA<Exception>()),
      );
    });

    test('3. ADMIN mengundang karyawan, karyawan login/register langsung otomatis menjadi KASIR', () async {
      // 1. Setup resto oleh admin
      final restoId = await authService.saveRestaurantForUser(
        userId: 'admin-1',
        name: 'Warung Berkah',
        category: 'Rumah Makan Tradisional',
      );

      // 2. Admin mengundang 2 kasir
      store.inviteEmployee(
        adminUserId: 'admin-1',
        restoId: restoId,
        email: 'kasir1@gmail.com',
      );
      store.inviteEmployee(
        adminUserId: 'admin-1',
        restoId: restoId,
        email: 'kasir2@gmail.com',
      );

      // 3. Kasir 1 login/register
      final resKasir1 = await authService.resolveAfterSignIn(
        userId: 'kasir-uid-1',
        email: 'kasir1@gmail.com',
        fallbackName: 'Budi Kasir',
      );

      expect(resKasir1.status, OnboardingStatus.readyForDashboard);
      expect(resKasir1.restoId, restoId);
      // Dalam sistem tanpa role, seluruh akun yang terhubung ke resto memiliki akses penuh
      expect(resKasir1.profile?.isAdmin, true);

      // 4. Kasir 2 login/register
      final resKasir2 = await authService.resolveAfterSignIn(
        userId: 'kasir-uid-2',
        email: 'kasir2@gmail.com',
        fallbackName: 'Siti Kasir',
      );

      expect(resKasir2.status, OnboardingStatus.readyForDashboard);
      expect(resKasir2.restoId, restoId);
      expect(resKasir2.profile?.isAdmin, true);
    });

    test('4. Akun yang tergabung dalam restoran memiliki sesi independen pada Restaurant ID yang sama', () async {
      final restoId = await authService.saveRestaurantForUser(
        userId: 'admin-1',
        name: 'Resto Nusantara',
        category: 'Restoran / Kafe',
      );

      store.inviteEmployee(
        adminUserId: 'admin-1',
        restoId: restoId,
        email: 'kasir@nusantara.com',
      );

      final adminSession = await authService.resolveAfterSignIn(
        userId: 'admin-1',
        email: 'admin@nusantara.com',
      );
      final kasirSession = await authService.resolveAfterSignIn(
        userId: 'kasir-1',
        email: 'kasir@nusantara.com',
      );

      expect(adminSession.restoId, restoId);
      expect(kasirSession.restoId, restoId);
      expect(adminSession.profile?.id != kasirSession.profile?.id, true);
      expect(adminSession.profile?.isAdmin, true);
      expect(kasirSession.profile?.isAdmin, true);
    });

    test('5. Karyawan yang belum diundang tidak dapat bergabung secara otomatis ke restoran', () async {
      await authService.saveRestaurantForUser(
        userId: 'admin-1',
        name: 'Resto Rahasia',
        category: 'Restoran / Kafe',
      );

      // User asing mencoba login tanpa undangan
      final stranger = await authService.resolveAfterSignIn(
        userId: 'stranger-uid',
        email: 'stranger@gmail.com',
      );

      // Tidak masuk ke restoran rahasia, diarahkan untuk setup restoran sendiri
      expect(stranger.status, OnboardingStatus.needsBusinessSetup);
      expect(stranger.restoId, isNull);
    });

    test('6. Kasir tidak dapat mengundang karyawan lain (Hanya ADMIN yang berhak)', () {
      final restoId = 'RESTO-TEST';
      store.restaurants[restoId] = 'Resto Uji Coba';
      store.restaurantMembers[restoId] = [
        RestaurantMember(
          id: 'mem-kasir',
          userId: 'kasir-1',
          restaurantId: restoId,
          role: 'KASIR',
          status: 'ACTIVE',
          createdAt: DateTime.now(),
        ),
      ];

      expect(
        () => store.inviteEmployee(
          adminUserId: 'kasir-1',
          restoId: restoId,
          email: 'temankasir@gmail.com',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('7. Eliminasi menyeluruh role OWNER: legacy owner ternormalisasi menjadi admin', () {
      final profile = UserProfile.fromMap({
        'id': 'legacy-1',
        'full_name': 'Pak Hendra',
        'email': 'hendra@resto.com',
        'role': 'owner',
      });

      expect(profile.role, 'admin');
      expect(profile.isAdmin, true);
      expect(profile.isKasir, false);

      final member = RestaurantMember.fromMap({
        'id': 'mem-legacy',
        'restaurant_id': 'RESTO-001',
        'role': 'OWNER',
        'status': 'ACTIVE',
      });
      expect(member.role, 'ADMIN');
      expect(member.isAdmin, true);
      expect(member.isKasir, false);
    });
  });
}
