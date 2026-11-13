import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/auth_onboarding_service.dart';

class PosService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<String> fetchRestaurantName() async {
    try {
      final rid = await fetchRestaurantId();
      if (rid != null) {
        final res = await supabase
            .from('restaurants')
            .select('name')
            .eq('id', rid)
            .maybeSingle();
        if (res != null && res['name'] != null) {
          return res['name'].toString();
        }
      }
    } catch (e) {
      debugPrint('Error fetching resto name: $e');
    }
    return 'Resto Saya';
  }

  Future<String?> fetchRestaurantId() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('profiles')
            .select('resto_id')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && profile['resto_id'] != null) {
          final rid = profile['resto_id'].toString().trim();
          if (rid.isNotEmpty) return rid;
        }
      }
    } catch (e) {
      debugPrint('Error fetching resto id from profile: $e');
    }
    return null;
  }

  Future<String> registerRestaurant({
    required String name,
    required String category,
    String? address,
    String? phone,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Sesi login tidak aktif. Silakan login kembali.');
    }

    final onboarding = AuthOnboardingService(
      store: SupabaseOnboardingStore(supabase),
    );
    return onboarding.saveRestaurantForUser(
      userId: user.id,
      name: name,
      category: category,
      address: address,
      phone: phone,
    );
  }

  // -------------------------------------------------------------
  // EMPLOYEES (KELOLA KARYAWAN)
  // -------------------------------------------------------------
  Future<List<DbEmployee>> fetchEmployees() async {
    try {
      final rid = await fetchRestaurantId();
      if (rid == null) return [];
      final List<dynamic> res = await supabase
          .from('employees')
          .select('*')
          .eq('resto_id', rid)
          .order('name', ascending: true);
      return res.map((e) => DbEmployee.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      return [];
    }
  }

  Future<DbEmployee> addEmployee({
    required String name,
    required String role,
    String? phone,
    String? email,
    String shift = 'Shift Pagi',
  }) async {
    final restoId = await fetchRestaurantId();
    final payload = {
      'resto_id': restoId,
      'name': name.trim(),
      'role': role.trim(),
      'phone': phone?.trim().isNotEmpty == true ? phone!.trim() : null,
      'email': email?.trim().isNotEmpty == true ? email!.trim() : null,
      'shift': shift,
      'is_active': true,
    };
    final res = await supabase.from('employees').insert(payload).select().single();
    return DbEmployee.fromMap(res);
  }

  Future<void> updateEmployee({
    required String id,
    required String name,
    required String role,
    String? phone,
    String? email,
    required String shift,
    required bool isActive,
  }) async {
    await supabase.from('employees').update({
      'name': name.trim(),
      'role': role.trim(),
      'phone': phone?.trim().isNotEmpty == true ? phone!.trim() : null,
      'email': email?.trim().isNotEmpty == true ? email!.trim() : null,
      'shift': shift,
      'is_active': isActive,
    }).eq('id', id);
  }

  Future<void> deleteEmployee(String id) async {
    await supabase.from('employees').delete().eq('id', id);
  }

  // -------------------------------------------------------------
  // USER PROFILE & ROLE
  // -------------------------------------------------------------
  Future<UserProfile?> fetchUserProfile(String userId) async {
    try {
      final res = await supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      if (res != null) {
        return UserProfile.fromMap(res);
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
    return null;
  }

  Future<List<UserProfile>> fetchStaffList() async {
    try {
      final List<dynamic> res = await supabase
          .from('profiles')
          .select('*')
          .order('created_at', ascending: true);
      return res.map((e) => UserProfile.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching staff list: $e');
      return [];
    }
  }

  // -------------------------------------------------------------
  // PRODUCTS (PRODUK NYATA SUPABASE)
  // -------------------------------------------------------------
  Future<List<DbProduct>> fetchProducts() async {
    try {
      final rid = await fetchRestaurantId();
      if (rid == null) return []; // Dashboard bersih jika belum ada restoran
      final List<dynamic> res = await supabase
          .from('products')
          .select('*')
          .eq('resto_id', rid)
          .order('created_at', ascending: false);

      return res.map((e) => DbProduct.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching products: $e');
      return [];
    }
  }

  Future<DbProduct> addProduct({
    required String name,
    required String category,
    required int price,
    required int stock,
    String? description,
    String? imageUrl,
    String iconName = 'fastfood',
  }) async {
    final restoId = await fetchRestaurantId();

    final basePayload = {
      'resto_id': restoId,
      'name': name.trim(),
      'category': category.trim(),
      'price': price,
      'stock': stock,
      'is_available': stock > 0,
      'icon_name': iconName,
      'image_url': imageUrl != null && imageUrl.trim().isNotEmpty
          ? imageUrl.trim()
          : null,
    };

    final extendedPayload = {
      ...basePayload,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    };

    Map<String, dynamic> res;
    try {
      res = await supabase
          .from('products')
          .insert(extendedPayload)
          .select()
          .single();
    } on PostgrestException catch (e) {
      if (e.code == '42703' ||
          e.message.contains('column') ||
          e.message.contains('description')) {
        res = await supabase
            .from('products')
            .insert(basePayload)
            .select()
            .single();
      } else {
        rethrow;
      }
    }
    return DbProduct.fromMap(res);
  }

  Future<void> updateProduct({
    required String productId,
    required String name,
    required String category,
    required int price,
    required int stock,
    String? description,
    String? imageUrl,
    String iconName = 'fastfood',
  }) async {
    final basePayload = {
      'name': name.trim(),
      'category': category.trim(),
      'price': price,
      'stock': stock,
      'is_available': stock > 0,
      'icon_name': iconName,
      if (imageUrl != null) 'image_url': imageUrl.trim(),
    };

    final extendedPayload = {
      ...basePayload,
      if (description != null) 'description': description.trim(),
    };

    try {
      await supabase
          .from('products')
          .update(extendedPayload)
          .eq('id', productId);
    } on PostgrestException catch (e) {
      if (e.code == '42703' ||
          e.message.contains('column') ||
          e.message.contains('description')) {
        await supabase
            .from('products')
            .update(basePayload)
            .eq('id', productId);
      } else {
        rethrow;
      }
    }
  }

  Future<void> updateProductStock(String productId, int newStock) async {
    await supabase.from('products').update({
      'stock': newStock,
      'is_available': newStock > 0,
    }).eq('id', productId);
  }

  Future<void> deleteProduct(String productId) async {
    await supabase.from('products').delete().eq('id', productId);
  }

  // -------------------------------------------------------------
  // ORDERS (PESANAN DIBUAT, PESANAN SELESAI, DIBATALKAN)
  // -------------------------------------------------------------
  Future<List<DbOrder>> fetchOrders() async {
    try {
      final rid = await fetchRestaurantId();
      if (rid == null) return [];
      final List<dynamic> res = await supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('resto_id', rid)
          .order('created_at', ascending: false);

      return res.map((e) {
        final rawItems = (e['order_items'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        return DbOrder.fromMap(e as Map<String, dynamic>, rawItems);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      return [];
    }
  }

  Future<DbOrder> createOrder({
    required String invoiceNo,
    required String cashierName,
    required int tableNumber,
    required int subtotal,
    required int serviceFee,
    required int total,
    required String paymentMethod,
    required String status, // 'pesanan dibuat' or 'pesanan selesai'
    required List<CartItem> cartItems,
  }) async {
    final user = supabase.auth.currentUser;
    final restoId = await fetchRestaurantId();

    final orderPayload = {
      'invoice_no': invoiceNo,
      'resto_id': restoId,
      'cashier_id': user?.id,
      'cashier_name': cashierName,
      'table_number': tableNumber,
      'subtotal': subtotal,
      'service_fee': serviceFee,
      'total': total,
      'payment_method': paymentMethod,
      'status': status,
    };

    final extendedPayload = {
      ...orderPayload,
      'payment_status': status == 'pesanan selesai' ? 'paid' : 'unpaid',
      'order_source': 'pos',
    };

    Map<String, dynamic> orderRes;
    try {
      orderRes = await supabase
          .from('orders')
          .insert(extendedPayload)
          .select()
          .single();
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.message.contains('column')) {
        orderRes = await supabase
            .from('orders')
            .insert(orderPayload)
            .select()
            .single();
      } else {
        rethrow;
      }
    }
    final String orderId = orderRes['id'].toString();

    // Insert order items & reduce stock
    final List<Map<String, dynamic>> insertedItems = [];
    for (final item in cartItems) {
      final itemPayload = {
        'order_id': orderId,
        'product_id': item.product.id,
        'product_name': item.product.name,
        'price': item.product.price,
        'quantity': item.qty,
        'subtotal': item.total,
      };

      final insertedItem = await supabase
          .from('order_items')
          .insert(itemPayload)
          .select()
          .single();
      insertedItems.add(insertedItem);

      // Kurangi stok produk di Supabase
      final updatedStock = (item.product.stock - item.qty).clamp(0, 99999);
      await updateProductStock(item.product.id, updatedStock);
    }

    return DbOrder.fromMap(orderRes, insertedItems);
  }

  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    final updates = <String, dynamic>{'status': newStatus};
    if (newStatus.toLowerCase() == 'pesanan selesai') {
      updates['payment_status'] = 'paid';
    }

    try {
      await supabase.from('orders').update(updates).eq('id', orderId);
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.message.contains('column')) {
        await supabase
            .from('orders')
            .update({'status': newStatus}).eq('id', orderId);
      } else {
        rethrow;
      }
    }
  }

  Future<String?> fetchOrderStatus(String orderId) async {
    try {
      final res = await supabase
          .from('orders')
          .select('status')
          .eq('id', orderId)
          .maybeSingle();
      if (res != null && res['status'] != null) {
        return res['status'].toString();
      }
    } catch (e) {
      debugPrint('Error fetching order status: $e');
    }
    return null;
  }

  Future<DbOrder?> fetchOrderById(String orderId) async {
    try {
      final res = await supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('id', orderId)
          .maybeSingle();

      if (res != null) {
        final rawItems = (res['order_items'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        return DbOrder.fromMap(res, rawItems);
      }
    } catch (e) {
      debugPrint('Error fetching order by id: $e');
    }
    return null;
  }

  // -------------------------------------------------------------
  // UPDATE USER PROFILE
  // -------------------------------------------------------------
  Future<UserProfile> updateUserProfile({
    required String userId,
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName.trim();
    if (phone != null) updates['phone'] = phone.trim();
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl.trim();

    final res = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();
    return UserProfile.fromMap(res);
  }

  // -------------------------------------------------------------
  // SECURITY & CHANGE PASSWORD
  // -------------------------------------------------------------
  Future<void> updatePassword(String newPassword) async {
    await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  Future<String?> uploadProductImageBytes(Uint8List bytes, String fileExtension) async {
    try {
      final fileName = 'prod_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final path = 'products/$fileName';

      await supabase.storage.from('product-images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: fileExtension == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl =
          supabase.storage.from('product-images').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('Supabase storage upload fallback to base64: $e');
      final mime = fileExtension == 'png' ? 'image/png' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
  }

  // -------------------------------------------------------------
  // ATTENDANCE (ABSENSI KARYAWAN)
  // -------------------------------------------------------------
  Future<DbAttendance?> fetchTodayAttendance([String? userId, String? employeeId]) async {
    try {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      var query = supabase.from('attendances').select('*').eq('date', todayStr);
      if (employeeId != null && employeeId.isNotEmpty) {
        query = query.eq('employee_id', employeeId);
      } else if (userId != null && userId.isNotEmpty) {
        query = query.or('user_id.eq.$userId,employee_id.eq.$userId');
      }
      final res = await query
          .order('clock_in', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        return DbAttendance.fromMap(res);
      }
    } catch (e) {
      debugPrint('Error fetchTodayAttendance: $e');
    }
    return null;
  }

  Future<DbAttendance> clockInAttendance({
    String? userId,
    String? employeeId,
    required String userName,
    required String role,
    required String shift,
    String? notes,
  }) async {
    final restoId = await fetchRestaurantId();
    final now = DateTime.now();
    final todayStr = now.toIso8601String().substring(0, 10);

    // Hitung status ketepatan waktu
    String status = 'Hadir Tepat Waktu';
    if (shift.contains('Pagi') && (now.hour > 8 || (now.hour == 8 && now.minute > 30))) {
      status = 'Hadir Terlambat';
    } else if (shift.contains('Siang') && (now.hour > 14 || (now.hour == 14 && now.minute > 15))) {
      status = 'Hadir Terlambat';
    } else if (shift.contains('Malam') && (now.hour > 18 || (now.hour == 18 && now.minute > 15))) {
      status = 'Hadir Terlambat';
    }

    final payload = <String, dynamic>{
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
      if (employeeId != null && employeeId.isNotEmpty) 'employee_id': employeeId,
      'resto_id': restoId,
      'user_name': userName,
      'role': role,
      'date': todayStr,
      'clock_in': now.toIso8601String(),
      'shift': shift,
      'status': status,
      'notes': notes,
    };

    final res = await supabase.from('attendances').insert(payload).select().single();
    return DbAttendance.fromMap(res);
  }

  Future<DbAttendance> clockOutAttendance(String attendanceId) async {
    final now = DateTime.now();
    final res = await supabase
        .from('attendances')
        .update({
          'clock_out': now.toIso8601String(),
        })
        .eq('id', attendanceId)
        .select()
        .single();
    return DbAttendance.fromMap(res);
  }

  Future<List<DbAttendance>> fetchUserAttendanceHistory(String userId) async {
    try {
      final List<dynamic> res = await supabase
          .from('attendances')
          .select('*')
          .eq('user_id', userId)
          .order('clock_in', ascending: false)
          .limit(30);

      return res.map((e) => DbAttendance.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetchUserAttendanceHistory: $e');
      return [];
    }
  }

  Future<List<DbAttendance>> fetchAllAttendancesToday() async {
    try {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final List<dynamic> res = await supabase
          .from('attendances')
          .select('*')
          .eq('date', todayStr)
          .order('clock_in', ascending: false);

      return res.map((e) => DbAttendance.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetchAllAttendancesToday: $e');
      return [];
    }
  }
}

