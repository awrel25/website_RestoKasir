import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/models.dart';

void main() {
  group('RestoKasir Unit Tests', () {
    test('DbProduct model calculations and attributes', () {
      final product = DbProduct(
        id: 'prod-1',
        name: 'Nasi Goreng Spesial',
        category: 'Makanan Utama',
        price: 25000,
        stock: 10,
        imageUrl: 'https://example.com/nasi.jpg',
      );

      final cartItem = CartItem(product, 3);
      expect(cartItem.total, 75000);
      expect(product.isAvailable, true);
    });

    test('DbOrder model parses statuses correctly', () {
      final rawOrderMap = {
        'id': 'ord-123',
        'invoice_no': 'INV-20261014-0001',
        'created_at': DateTime.now().toIso8601String(),
        'cashier_name': 'Aurel',
        'table_number': 5,
        'subtotal': 50000,
        'service_fee': 2500,
        'total': 52500,
        'payment_method': 'Tunai',
        'status': 'pesanan dibuat',
      };

      final order = DbOrder.fromMap(rawOrderMap, [
        {
          'id': 'item-1',
          'order_id': 'ord-123',
          'product_id': 'prod-1',
          'product_name': 'Nasi Goreng Spesial',
          'price': 25000,
          'quantity': 2,
          'subtotal': 50000,
        }
      ]);

      expect(order.status, 'pesanan dibuat');
      expect(order.tableNumber, 5);
      expect(order.items.length, 1);
      expect(order.total, 52500);
    });

    test('UserProfile role security checks', () {
      final kasirProfile = UserProfile(
        id: 'u-1',
        fullName: 'Kasir Satu',
        email: 'kasir@resto.com',
        role: 'kasir',
      );
      expect(kasirProfile.isAdmin, false);
      expect(kasirProfile.isKasir, true);

      final adminProfile = UserProfile(
        id: 'u-2',
        fullName: 'Admin Utama',
        email: 'admin@resto.com',
        role: 'admin',
      );
      expect(adminProfile.isAdmin, true);
      expect(adminProfile.isKasir, false);

      final ownerProfile = UserProfile(
        id: 'u-3',
        fullName: 'Owner Resto',
        email: 'owner@resto.com',
        role: 'owner',
      );
      expect(ownerProfile.isAdmin, true);
    });
  });
}
