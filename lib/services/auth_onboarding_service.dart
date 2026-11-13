import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:my_app/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OnboardingStatus {
  unauthenticated,
  needsBusinessSetup,
  readyForDashboard,
}

class OnboardingResult {
  final OnboardingStatus status;
  final UserProfile? profile;
  final String? restoId;
  final String? ownerName;

  const OnboardingResult({
    required this.status,
    this.profile,
    this.restoId,
    this.ownerName,
  });

  bool get hasRestaurant => status == OnboardingStatus.readyForDashboard;
}

/// Kontrak penyimpanan data profil & restoran agar alur onboarding dapat diuji terpisah dari SDK Supabase.
abstract class OnboardingStore {
  Future<UserProfile?> fetchProfile(String userId);

  Future<UserProfile> ensureProfile({
    required String userId,
    required String fullName,
    required String email,
    required String defaultRole,
  });

  Future<String?> findOwnedRestaurantId(String userId);

  Future<bool> restaurantExists(String restoId);

  Future<void> linkProfileToRestaurant(String userId, String restoId);

  Future<String> upsertRestaurantForUser({
    required String userId,
    required String name,
    required String category,
    String? address,
    String? phone,
  });
}

/// Implementasi penyimpanan onboarding menggunakan Supabase Postgres & Auth.
class SupabaseOnboardingStore implements OnboardingStore {
  final SupabaseClient _supabase;
  bool? _restaurantsHasUserId;
  bool? _restaurantsHasCategory;

  SupabaseOnboardingStore([SupabaseClient? client])
      : _supabase = client ?? Supabase.instance.client;

  Future<void> _detectRestaurantColumnsIfPossible() async {
    if (_restaurantsHasUserId != null && _restaurantsHasCategory != null) {
      return;
    }
    try {
      final List<dynamic> rows =
          await _supabase.from('restaurants').select('*').limit(1);
      if (rows.isNotEmpty && rows.first is Map) {
        final first = Map<String, dynamic>.from(rows.first as Map);
        _restaurantsHasUserId = first.containsKey('user_id');
        _restaurantsHasCategory = first.containsKey('category');
      }
    } catch (e) {
      debugPrint('Catatan deteksi kolom restaurants: $e');
    }
  }

  static String _extractErrorText(Object e) {
    if (e is PostgrestException) {
      return '${e.code ?? ''} ${e.message} ${e.details ?? ''} ${e.hint ?? ''} $e';
    }
    return e.toString();
  }

  /// Mendeteksi galat kolom belum tersedia (baik kode terurai maupun JSON mentah Postgrest).
  static bool isMissingColumnError(Object e, String columnName) {
    final text = _extractErrorText(e).toLowerCase();
    final col = columnName.toLowerCase();
    final hasColSignal = text.contains('42703') ||
        text.contains('pgrst204') ||
        text.contains('does not exist') ||
        text.contains('could not find');
    return hasColSignal && text.contains(col);
  }

  /// Mendeteksi galat fungsi RPC belum tersedia di database.
  static bool isMissingFunctionError(Object e, String fnName) {
    final text = _extractErrorText(e).toLowerCase();
    final fn = fnName.toLowerCase();
    final hasFnSignal = text.contains('42883') ||
        text.contains('pgrst202') ||
        text.contains('could not find the function') ||
        text.contains('does not exist');
    return hasFnSignal && text.contains(fn);
  }

  static bool isUniqueViolationError(Object e) {
    final text = _extractErrorText(e).toLowerCase();
    return text.contains('23505') || text.contains('duplicate key');
  }

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    final res = await _supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();
    if (res == null) return null;
    return UserProfile.fromMap(res);
  }

  @override
  Future<UserProfile> ensureProfile({
    required String userId,
    required String fullName,
    required String email,
    required String defaultRole,
  }) async {
    final existing = await fetchProfile(userId);
    if (existing != null) {
      return existing;
    }

    await _supabase.from('profiles').upsert(
      {
        'id': userId,
        'full_name': fullName,
        'email': email,
        'role': defaultRole,
        'resto_id': null,
      },
      onConflict: 'id',
      ignoreDuplicates: true,
    );

    final created = await fetchProfile(userId);
    if (created != null) {
      return created;
    }

    return UserProfile(
      id: userId,
      fullName: fullName,
      email: email,
      role: defaultRole,
      restoId: null,
    );
  }

  @override
  Future<String?> findOwnedRestaurantId(String userId) async {
    await _detectRestaurantColumnsIfPossible();
    if (_restaurantsHasUserId == false) {
      return null;
    }

    try {
      final res = await _supabase
          .from('restaurants')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();
      _restaurantsHasUserId = true;
      if (res != null && res['id'] != null) {
        final rid = res['id'].toString().trim();
        if (rid.isNotEmpty) return rid;
      }
      return null;
    } catch (e) {
      if (isMissingColumnError(e, 'user_id')) {
        _restaurantsHasUserId = false;
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<bool> restaurantExists(String restoId) async {
    final res = await _supabase
        .from('restaurants')
        .select('id')
        .eq('id', restoId)
        .maybeSingle();
    return res != null;
  }

  @override
  Future<void> linkProfileToRestaurant(String userId, String restoId) async {
    await _supabase
        .from('profiles')
        .update({'resto_id': restoId})
        .eq('id', userId);
  }

  Future<void> _seedDefaultTablesBestEffort(String restoId) async {
    try {
      final rows = List.generate(
        20,
        (idx) => {
          'resto_id': restoId,
          'table_number': idx + 1,
          'is_active': true,
        },
      );
      await _supabase
          .from('restaurant_tables')
          .upsert(rows, onConflict: 'resto_id,table_number', ignoreDuplicates: true);
    } catch (e) {
      debugPrint('Catatan seed meja default: $e');
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
    final cleanName = name.trim();
    final cleanCategory = category.trim();
    final cleanAddress = address?.trim().isNotEmpty == true ? address!.trim() : null;
    final cleanPhone = phone?.trim().isNotEmpty == true ? phone!.trim() : null;

    await _detectRestaurantColumnsIfPossible();

    // 1. Prioritaskan RPC atomik (anti-duplikasi berbasis auth.uid()) bila skema sudah dimigrasi
    if (_restaurantsHasUserId != false) {
      try {
        final rpcResult = await _supabase.rpc(
          'upsert_my_restaurant',
          params: {
            'p_name': cleanName,
            'p_category': cleanCategory,
            'p_address': cleanAddress,
            'p_phone': cleanPhone,
          },
        );
        final rid = rpcResult?.toString().trim();
        if (rid != null && rid.isNotEmpty) {
          return rid;
        }
      } catch (e) {
        if (!isMissingFunctionError(e, 'upsert_my_restaurant') &&
            !isMissingColumnError(e, 'user_id')) {
          rethrow;
        }
      }
    }

    // 2. Fallback client-side yang tetap mencegah duplikasi restoran
    String? existingRestoId = await findOwnedRestaurantId(userId);
    if (existingRestoId == null) {
      final profile = await fetchProfile(userId);
      final profileRestoId = profile?.restoId?.trim();
      if (profileRestoId != null &&
          profileRestoId.isNotEmpty &&
          await restaurantExists(profileRestoId)) {
        existingRestoId = profileRestoId;
      }
    }

    final basePayload = <String, dynamic>{
      'name': cleanName,
      'address': cleanAddress,
      'phone': cleanPhone,
    };
    final extendedPayload = <String, dynamic>{
      ...basePayload,
      if (_restaurantsHasUserId != false) 'user_id': userId,
      if (_restaurantsHasCategory != false) 'category': cleanCategory,
    };

    if (existingRestoId != null) {
      try {
        await _supabase
            .from('restaurants')
            .update(extendedPayload)
            .eq('id', existingRestoId);
      } catch (e) {
        if (isMissingColumnError(e, 'category') ||
            isMissingColumnError(e, 'user_id')) {
          if (isMissingColumnError(e, 'user_id')) _restaurantsHasUserId = false;
          if (isMissingColumnError(e, 'category')) {
            _restaurantsHasCategory = false;
          }
          await _supabase
              .from('restaurants')
              .update(basePayload)
              .eq('id', existingRestoId);
        } else {
          rethrow;
        }
      }

      await linkProfileToRestaurant(userId, existingRestoId);
      return existingRestoId;
    }

    String createdId;
    try {
      final inserted = await _supabase
          .from('restaurants')
          .insert(extendedPayload)
          .select('id')
          .single();
      createdId = inserted['id'].toString();
    } catch (e) {
      if (isUniqueViolationError(e)) {
        final conflictId = await findOwnedRestaurantId(userId);
        if (conflictId == null) rethrow;
        createdId = conflictId;
      } else if (isMissingColumnError(e, 'category') ||
          isMissingColumnError(e, 'user_id')) {
        if (isMissingColumnError(e, 'user_id')) _restaurantsHasUserId = false;
        if (isMissingColumnError(e, 'category')) {
          _restaurantsHasCategory = false;
        }
        final inserted = await _supabase
            .from('restaurants')
            .insert(basePayload)
            .select('id')
            .single();
        createdId = inserted['id'].toString();
      } else {
        rethrow;
      }
    }

    await linkProfileToRestaurant(userId, createdId);
    await _seedDefaultTablesBestEffort(createdId);
    return createdId;
  }
}

/// Mengkoordinasikan pengecekan profil dan kepemilikan restoran untuk Email/Password maupun Google Auth.
class AuthOnboardingService {
  final OnboardingStore _store;

  AuthOnboardingService({OnboardingStore? store})
      : _store = store ?? SupabaseOnboardingStore();

  /// Menyamakan alur pasca-autentikasi untuk Email/Password, Google Sign-In, dan pemulihan sesi.
  Future<OnboardingResult> resolveAfterSignIn({
    required String userId,
    String? email,
    Map<String, dynamic>? userMetadata,
    String? fallbackEmail,
    String? fallbackName,
  }) async {
    final trimmedUid = userId.trim();
    if (trimmedUid.isEmpty) {
      return const OnboardingResult(status: OnboardingStatus.unauthenticated);
    }

    final metadata = userMetadata ?? const <String, dynamic>{};
    final effectiveEmail = (email ?? fallbackEmail ?? '').trim();
    final effectiveName = _pickDisplayName(
      metadata: metadata,
      fallbackName: fallbackName,
      email: effectiveEmail,
    );
    final defaultRole = (metadata['role']?.toString().trim().isNotEmpty == true)
        ? metadata['role'].toString().trim().toLowerCase()
        : 'kasir';

    var profile = await _store.ensureProfile(
      userId: trimmedUid,
      fullName: effectiveName,
      email: effectiveEmail,
      defaultRole: defaultRole,
    );

    final profileRestoId = profile.restoId?.trim();
    if (profileRestoId != null && profileRestoId.isNotEmpty) {
      final exists = await _store.restaurantExists(profileRestoId);
      if (exists) {
        return OnboardingResult(
          status: OnboardingStatus.readyForDashboard,
          profile: profile,
          restoId: profileRestoId,
          ownerName: profile.fullName,
        );
      }
    }

    final ownedRestoId = await _store.findOwnedRestaurantId(trimmedUid);
    if (ownedRestoId != null && ownedRestoId.isNotEmpty) {
      await _store.linkProfileToRestaurant(trimmedUid, ownedRestoId);
      profile = profile.copyWith(restoId: ownedRestoId);
      return OnboardingResult(
        status: OnboardingStatus.readyForDashboard,
        profile: profile,
        restoId: ownedRestoId,
        ownerName: profile.fullName,
      );
    }

    return OnboardingResult(
      status: OnboardingStatus.needsBusinessSetup,
      profile: profile,
      restoId: null,
      ownerName: profile.fullName.isNotEmpty ? profile.fullName : effectiveName,
    );
  }

  /// Pembantu praktis untuk objek [User] milik Supabase Auth.
  Future<OnboardingResult> resolveForSupabaseUser(
    User? user, {
    String? fallbackEmail,
    String? fallbackName,
  }) {
    if (user == null) {
      return Future.value(
        const OnboardingResult(status: OnboardingStatus.unauthenticated),
      );
    }
    return resolveAfterSignIn(
      userId: user.id,
      email: user.email,
      userMetadata: user.userMetadata,
      fallbackEmail: fallbackEmail,
      fallbackName: fallbackName,
    );
  }

  /// Menyimpan atau memperbarui identitas restoran untuk pengguna yang sedang login.
  Future<String> saveRestaurantForUser({
    required String userId,
    required String name,
    required String category,
    String? address,
    String? phone,
  }) async {
    if (userId.trim().isEmpty) {
      throw Exception('Sesi login tidak aktif. Silakan login kembali.');
    }
    if (name.trim().isEmpty) {
      throw Exception('Nama usaha / restoran wajib diisi.');
    }
    return _store.upsertRestaurantForUser(
      userId: userId,
      name: name,
      category: category,
      address: address,
      phone: phone,
    );
  }

  static String _pickDisplayName({
    required Map<String, dynamic> metadata,
    String? fallbackName,
    required String email,
  }) {
    final fromFullName = metadata['full_name']?.toString().trim();
    if (fromFullName != null && fromFullName.isNotEmpty) return fromFullName;

    final fromName = metadata['name']?.toString().trim();
    if (fromName != null && fromName.isNotEmpty) return fromName;

    final fromFallback = fallbackName?.trim();
    if (fromFallback != null && fromFallback.isNotEmpty) return fromFallback;

    if (email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) return prefix;
    }
    return 'Pengguna';
  }

  /// Mengubah galat koneksi/server menjadi pesan bahasa biasa yang aman dan jelas bagi pengguna.
  static String formatFriendlyError(
    Object error, {
    String fallback = 'Terjadi kesalahan. Silakan coba lagi.',
  }) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    // Galat jaringan / koneksi
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception') ||
        lower.contains('timed out') ||
        (lower.contains('connection') &&
            !lower.contains('signInWithIdToken') &&
            !lower.contains('google'))) {
      return 'Koneksi internet terputus. Periksa jaringan Anda lalu coba lagi.';
    }

    // Proses JSON mentah yang mungkin terbungkus di dalam Exception string
    String? embeddedJson;
    if (raw.contains('{') && raw.contains('}')) {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < end) {
        embeddedJson = raw.substring(start, end + 1);
      }
    }

    if (error is PostgrestException) {
      var msg = error.message.trim();
      var code = (error.code ?? '').trim();
      if (msg.startsWith('{') && msg.endsWith('}')) {
        try {
          final parsed = jsonDecode(msg);
          if (parsed is Map<String, dynamic>) {
            code = code.isEmpty ? (parsed['code']?.toString() ?? '') : code;
            final innerMsg = parsed['message']?.toString().trim();
            if (innerMsg != null && innerMsg.isNotEmpty) {
              msg = innerMsg;
            }
          }
        } catch (_) {}
      }
      // Galat kolom tidak ditemukan (tidak perlu ditampilkan ke pengguna)
      if (code == '42703' ||
          lower.contains('does not exist') ||
          lower.contains('column')) {
        return fallback;
      }
      if (code == '42501') {
        return 'Anda tidak memiliki izin akses untuk menyimpan data restoran ini.';
      }
      if (code == '23505') {
        return 'Data sudah tersimpan sebelumnya.';
      }
      return msg.isNotEmpty ? msg : fallback;
    }

    // Coba parse JSON yang terbungkus di Exception string
    if (embeddedJson != null) {
      try {
        final parsed = jsonDecode(embeddedJson);
        if (parsed is Map<String, dynamic>) {
          final code = parsed['code']?.toString() ?? '';
          final msg = parsed['message']?.toString().trim() ?? '';
          // Galat kolom tidak ditemukan — sembunyikan dari pengguna
          if (code == '42703' ||
              msg.toLowerCase().contains('does not exist') ||
              msg.toLowerCase().contains('column')) {
            return fallback;
          }
          if (code == '42501') {
            return 'Anda tidak memiliki izin akses untuk menyimpan data restoran ini.';
          }
          if (msg.isNotEmpty) return msg;
        }
      } catch (_) {}
    }

    if (raw.startsWith('Exception: ')) {
      final inner = raw.substring('Exception: '.length);
      // Jangan tampilkan JSON mentah ke pengguna
      if (inner.startsWith('{')) return fallback;
      return inner;
    }
    return fallback;
  }
}

