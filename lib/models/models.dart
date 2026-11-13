import 'package:flutter/material.dart';

enum UserRole { kasir, admin, owner }

class DbProduct {
  final String id;
  final String? restoId;
  String name;
  String category;
  int price;
  int stock;
  bool isAvailable;
  String iconName;
  String? imageUrl;
  String? description;

  DbProduct({
    required this.id,
    this.restoId,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.isAvailable = true,
    this.iconName = 'fastfood',
    this.imageUrl,
    this.description,
  });

  factory DbProduct.fromMap(Map<String, dynamic> map) {
    return DbProduct(
      id: map['id']?.toString() ?? '',
      restoId: map['resto_id']?.toString(),
      name: map['name']?.toString() ?? '',
      category: map['category']?.toString() ?? 'Makanan Utama',
      price: (map['price'] is int)
          ? map['price'] as int
          : int.tryParse(map['price']?.toString() ?? '0') ?? 0,
      stock: (map['stock'] is int)
          ? map['stock'] as int
          : int.tryParse(map['stock']?.toString() ?? '0') ?? 0,
      isAvailable: map['is_available'] == true,
      iconName: map['icon_name']?.toString() ?? 'fastfood',
      imageUrl: map['image_url']?.toString(),
      description: map['description']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (restoId != null) 'resto_id': restoId,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'is_available': isAvailable,
      'icon_name': iconName,
      'image_url': imageUrl,
      if (description != null && description!.isNotEmpty)
        'description': description,
    };
  }

  IconData get iconData {
    switch (iconName) {
      case 'rice_bowl':
        return Icons.rice_bowl_rounded;
      case 'lunch_dining':
        return Icons.lunch_dining_rounded;
      case 'ramen_dining':
        return Icons.ramen_dining_rounded;
      case 'local_cafe':
        return Icons.local_cafe_rounded;
      case 'local_drink':
        return Icons.local_drink_rounded;
      case 'cake':
        return Icons.cake_rounded;
      case 'bakery_dining':
        return Icons.bakery_dining_rounded;
      default:
        return Icons.fastfood_rounded;
    }
  }
}

class CartItem {
  final DbProduct product;
  int qty;

  CartItem(this.product, this.qty);

  int get total => product.price * qty;
}

class DbOrderItem {
  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final int price;
  final int quantity;
  final int subtotal;

  DbOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.subtotal,
  });

  factory DbOrderItem.fromMap(Map<String, dynamic> map) {
    return DbOrderItem(
      id: map['id']?.toString() ?? '',
      orderId: map['order_id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? 'Produk',
      price: (map['price'] is int)
          ? map['price'] as int
          : int.tryParse(map['price']?.toString() ?? '0') ?? 0,
      quantity: (map['quantity'] is int)
          ? map['quantity'] as int
          : int.tryParse(map['quantity']?.toString() ?? '1') ?? 1,
      subtotal: (map['subtotal'] is int)
          ? map['subtotal'] as int
          : int.tryParse(map['subtotal']?.toString() ?? '0') ?? 0,
    );
  }
}

class DbOrder {
  final String id;
  final String invoiceNo;
  final DateTime createdAt;
  final String cashierName;
  final int tableNumber;
  final int subtotal;
  final int serviceFee;
  final int total;
  final String paymentMethod;
  final String paymentStatus; // 'unpaid', 'paid', 'demo_paid'
  final String orderSource; // 'pos', 'qr'
  final String status; // 'pesanan dibuat', 'pesanan selesai', 'dibatalkan'
  final List<DbOrderItem> items;

  DbOrder({
    required this.id,
    required this.invoiceNo,
    required this.createdAt,
    required this.cashierName,
    required this.tableNumber,
    required this.subtotal,
    required this.serviceFee,
    required this.total,
    required this.paymentMethod,
    this.paymentStatus = 'unpaid',
    this.orderSource = 'pos',
    required this.status,
    required this.items,
  });

  bool get isPaid =>
      paymentStatus == 'paid' || status.toLowerCase() == 'pesanan selesai';

  bool get isDemoQris {
    final m = paymentMethod.toUpperCase();
    return m.contains('QRIS_DEMO') || m.contains('QRIS DEMO');
  }

  bool get isDemoPaid =>
      paymentStatus == 'demo_paid' ||
      paymentMethod.toLowerCase().contains('demo berhasil');

  bool get isQrSource => orderSource == 'qr';

  factory DbOrder.fromMap(
    Map<String, dynamic> map,
    List<Map<String, dynamic>> orderItems,
  ) {
    String rawStatus =
        (map['status']?.toString() ?? 'pesanan dibuat').toLowerCase();
    if (rawStatus == 'selesai') {
      rawStatus = 'pesanan selesai';
    }

    final rawInvoice = map['invoice_no']?.toString() ?? 'INV-0000';
    final rawCashier = map['cashier_name']?.toString() ?? 'Kasir';
    final rawMethod = map['payment_method']?.toString() ?? 'Tunai';

    String payStatus =
        (map['payment_status']?.toString() ?? '').toLowerCase().trim();
    if (payStatus.isEmpty) {
      if (rawStatus == 'pesanan selesai') {
        payStatus = 'paid';
      } else if (rawMethod.toLowerCase().contains('demo berhasil')) {
        payStatus = 'demo_paid';
      } else {
        payStatus = 'unpaid';
      }
    }

    String source =
        (map['order_source']?.toString() ?? '').toLowerCase().trim();
    if (source.isEmpty) {
      final invLower = rawInvoice.toLowerCase();
      final methodLower = rawMethod.toLowerCase();
      final cashierLower = rawCashier.toLowerCase();
      if (invLower.startsWith('web-') ||
          methodLower.contains('(meja)') ||
          methodLower.contains('demo') ||
          methodLower == 'cashier' ||
          cashierLower.startsWith('meja ')) {
        source = 'qr';
      } else {
        source = 'pos';
      }
    }

    return DbOrder(
      id: map['id']?.toString() ?? '',
      invoiceNo: rawInvoice,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      cashierName: rawCashier,
      tableNumber: (map['table_number'] is int)
          ? map['table_number'] as int
          : int.tryParse(map['table_number']?.toString() ?? '1') ?? 1,
      subtotal: (map['subtotal'] is int)
          ? map['subtotal'] as int
          : int.tryParse(map['subtotal']?.toString() ?? '0') ?? 0,
      serviceFee: (map['service_fee'] is int)
          ? map['service_fee'] as int
          : int.tryParse(map['service_fee']?.toString() ?? '0') ?? 0,
      total: (map['total'] is int)
          ? map['total'] as int
          : int.tryParse(map['total']?.toString() ?? '0') ?? 0,
      paymentMethod: rawMethod,
      paymentStatus: payStatus,
      orderSource: source,
      status: rawStatus,
      items: orderItems.map((e) => DbOrderItem.fromMap(e)).toList(),
    );
  }
}

class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final String role; // 'admin', 'kasir', 'owner'
  final String? restoId;
  final String? avatarUrl;
  final String? phone;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.restoId,
    this.avatarUrl,
    this.phone,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? 'Pengguna',
      email: map['email']?.toString() ?? '',
      role: (map['role']?.toString() ?? 'kasir').toLowerCase(),
      restoId: map['resto_id']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      phone: map['phone']?.toString(),
    );
  }

  UserProfile copyWith({
    String? fullName,
    String? email,
    String? role,
    String? restoId,
    String? avatarUrl,
    String? phone,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      restoId: restoId ?? this.restoId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
    );
  }

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'U';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isKasir => role == 'kasir';
}

class DbEmployee {
  final String id;
  final String? restoId;
  final String name;
  final String role; // 'Kasir', 'Koki / Dapur', 'Pelayan', 'Barista', 'Manager'
  final String? phone;
  final String? email;
  final String shift;
  final bool isActive;
  final DateTime createdAt;

  DbEmployee({
    required this.id,
    this.restoId,
    required this.name,
    this.role = 'Kasir',
    this.phone,
    this.email,
    this.shift = 'Shift Pagi',
    this.isActive = true,
    required this.createdAt,
  });

  factory DbEmployee.fromMap(Map<String, dynamic> map) {
    return DbEmployee(
      id: map['id']?.toString() ?? '',
      restoId: map['resto_id']?.toString(),
      name: map['name']?.toString() ?? 'Karyawan',
      role: map['role']?.toString() ?? 'Kasir',
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      shift: map['shift']?.toString() ?? 'Shift Pagi',
      isActive: map['is_active'] != false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (restoId != null) 'resto_id': restoId,
      'name': name,
      'role': role,
      'phone': phone,
      'email': email,
      'shift': shift,
      'is_active': isActive,
    };
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'K';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

class DbAttendance {
  final String id;
  final String? userId;
  final String? employeeId;
  final String? restoId;
  final String userName;
  final String role;
  final DateTime date;
  final DateTime clockIn;
  final DateTime? clockOut;
  final String shift;
  final String status;
  final String? notes;

  DbAttendance({
    required this.id,
    this.userId,
    this.employeeId,
    this.restoId,
    required this.userName,
    this.role = 'kasir',
    required this.date,
    required this.clockIn,
    this.clockOut,
    this.shift = 'Shift Pagi',
    this.status = 'Hadir Tepat Waktu',
    this.notes,
  });

  factory DbAttendance.fromMap(Map<String, dynamic> map) {
    return DbAttendance(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      employeeId: map['employee_id']?.toString(),
      restoId: map['resto_id']?.toString(),
      userName: map['user_name']?.toString() ?? 'Karyawan',
      role: map['role']?.toString() ?? 'kasir',
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      clockIn: map['clock_in'] != null
          ? DateTime.tryParse(map['clock_in'].toString()) ?? DateTime.now()
          : DateTime.now(),
      clockOut: map['clock_out'] != null
          ? DateTime.tryParse(map['clock_out'].toString())
          : null,
      shift: map['shift']?.toString() ?? 'Shift Pagi',
      status: map['status']?.toString() ?? 'Hadir Tepat Waktu',
      notes: map['notes']?.toString(),
    );
  }

  bool get isClockedOut => clockOut != null;

  Duration get workingDuration {
    final end = clockOut ?? DateTime.now();
    return end.difference(clockIn);
  }

  String get durationFormatted {
    final d = workingDuration;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '$minutes menit';
    return '$hours jam $minutes mnt';
  }
}

