import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/screens/admin/add_product_screen.dart';
import 'package:my_app/screens/cashier/receipt_print_screen.dart';
import 'package:my_app/screens/cashier/qris_payment_dialog.dart';
import 'package:my_app/screens/orders/orders_screen.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/core/utils/responsive.dart';
import 'package:my_app/screens/profile/profile_screen.dart';
import 'package:my_app/widgets/product_image_view.dart';
import 'package:my_app/screens/cashier/table_qr_dialog.dart';

class CashierScreen extends StatefulWidget {
  final UserProfile userProfile;
  final String restaurantName;
  final VoidCallback? onBackToAdmin;

  const CashierScreen({
    super.key,
    required this.userProfile,
    required this.restaurantName,
    this.onBackToAdmin,
  });

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final _posService = PosService();
  late UserProfile _currentProfile;

  List<DbProduct> _products = [];
  final List<CartItem> _cart = [];
  bool _isLoading = true;

  String _search = '';
  String _selectedCategory = 'Semua';
  int _selectedTable = 1;
  String _paymentMethod = 'Tunai';
  final _cashController = TextEditingController();

  final List<String> _categories = [
    'Semua',
    'Makanan Utama',
    'Snack & Camilan',
    'Minuman',
    'Dessert',
    'Paket Spesial',
  ];

  Timer? _incomingOrdersTimer;
  RealtimeChannel? _ordersChannel;
  String? _lastNotifiedOrderId;
  List<DbOrder> _pendingOrders = [];

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.userProfile;
    _loadProducts();
    _startIncomingOrdersListener();
  }

  @override
  void dispose() {
    _incomingOrdersTimer?.cancel();
    _ordersChannel?.unsubscribe();
    _cashController.dispose();
    super.dispose();
  }

  bool _isPendingOrder(DbOrder order) {
    final s = order.status.toLowerCase();
    return s == 'pesanan dibuat' || s.contains('dibuat') || s == 'pending';
  }

  String _pendingTablesSummary() {
    final tables = _pendingOrders.map((o) => 'Meja ${o.tableNumber}').toSet().toList();
    if (tables.length <= 3) return tables.join(', ');
    return '${tables.take(3).join(', ')} +${tables.length - 3}';
  }

  Future<void> _refreshPendingOrders({bool notifyIfNew = false}) async {
    try {
      final recentOrders = await _posService.fetchOrders();
      if (!mounted) return;
      final pending = recentOrders.where(_isPendingOrder).toList();
      final newest = recentOrders.isNotEmpty ? recentOrders.first : null;

      final previousIds = _pendingOrders.map((e) => e.id).join(',');
      final nextIds = pending.map((e) => e.id).join(',');
      if (previousIds != nextIds) {
        setState(() => _pendingOrders = pending);
      }

      if (newest == null) return;
      if (!notifyIfNew) {
        _lastNotifiedOrderId ??= newest.id;
        return;
      }

      if (_lastNotifiedOrderId != null &&
          newest.id != _lastNotifiedOrderId &&
          _isPendingOrder(newest)) {
        _lastNotifiedOrderId = newest.id;
        _loadProducts();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pesanan baru masuk dari Meja ${newest.tableNumber} (${newest.cashierName}) - ${_formatRupiah(newest.total)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Cek Meja',
                textColor: AppColors.yellow,
                onPressed: _openOrders,
              ),
            ),
          );
        }
      } else {
        _lastNotifiedOrderId ??= newest.id;
      }
    } catch (e) {
      debugPrint('Polling incoming orders error: $e');
    }
  }

  void _startIncomingOrdersListener() {
    _incomingOrdersTimer?.cancel();
    _ordersChannel?.unsubscribe();
    _refreshPendingOrders(notifyIfNew: false);

    try {
      _ordersChannel = _posService.supabase
          .channel('cashier-orders-realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => _refreshPendingOrders(notifyIfNew: true),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Supabase realtime cashier fallback: $e');
    }

    _incomingOrdersTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshPendingOrders(notifyIfNew: true),
    );
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final loaded = await _posService.fetchProducts();
    if (mounted) {
      setState(() {
        _products = loaded;
        _isLoading = false;
      });
    }
  }

  String _formatRupiah(int val) {
    final f = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return f.format(val);
  }

  List<DbProduct> get _filteredProducts {
    return _products.where((p) {
      final hasStock = p.stock > 0;
      final matchCat = _selectedCategory == 'Semua' || p.category == _selectedCategory;
      final matchSearch = p.name.toLowerCase().contains(_search.toLowerCase());
      return hasStock && matchCat && matchSearch;
    }).toList();
  }

  int get _subtotal => _cart.fold(0, (sum, i) => sum + i.total);
  int get _serviceFee => (_subtotal * 0.05).round();
  int get _grandTotal => _subtotal + _serviceFee;

  void _addToCart(DbProduct product) {
    if (product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maaf, stok produk ini sedang habis.'),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      final idx = _cart.indexWhere((c) => c.product.id == product.id);
      if (idx != -1) {
        if (_cart[idx].qty < product.stock) {
          _cart[idx].qty += 1;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Batas maksimal stok (${product.stock}) telah tercapai.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        _cart.add(CartItem(product, 1));
      }
    });
  }

  void _decreaseCartItem(int index) {
    setState(() {
      if (_cart[index].qty > 1) {
        _cart[index].qty -= 1;
      } else {
        _cart.removeAt(index);
      }
    });
  }

  void _increaseCartItem(int index) {
    final item = _cart[index];
    if (item.qty < item.product.stock) {
      setState(() => item.qty += 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stok hanya tersedia ${item.product.stock} pcs.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _processCheckout({required String targetStatus}) async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keranjang belanja masih kosong.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final int cashGiven = int.tryParse(_cashController.text.trim()) ?? 0;
    if (targetStatus == 'pesanan selesai' &&
        _paymentMethod == 'Tunai' &&
        cashGiven < _grandTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uang tunai kurang. Minimal ${_formatRupiah(_grandTotal)}'),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Generate unique invoice number
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final randomPart = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    final invoiceNo = 'INV-$dateStr-$randomPart';

    final savedCart = List<CartItem>.from(_cart);
    final savedSubtotal = _subtotal;
    final savedServiceFee = _serviceFee;
    final savedGrandTotal = _grandTotal;
    final savedTable = _selectedTable;
    final savedCashierName = widget.userProfile.fullName;

    // Jika metode QRIS atau Transfer Bank dan bayar selesai: tampilkan dialog QRIS / Transfer
    if (targetStatus == 'pesanan selesai' &&
        (_paymentMethod == 'QRIS' ||
            _paymentMethod.contains('Transfer') ||
            _paymentMethod.contains('Virtual'))) {
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QrisPaymentDialog(
          restaurantName: widget.restaurantName,
          totalAmount: savedGrandTotal,
          invoiceNo: invoiceNo,
          tableNumber: savedTable,
          cashierName: savedCashierName,
          paymentMethod: _paymentMethod == 'QRIS' ? 'QRIS' : 'Transfer Bank',
          cartItems: savedCart,
        ),
      );

      if (paid == true) {
        setState(() {
          _cart.clear();
          _cashController.clear();
        });
        _loadProducts();
      }
      return;
    }

    // Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final newOrder = await _posService.createOrder(
        invoiceNo: invoiceNo,
        cashierName: savedCashierName,
        tableNumber: savedTable,
        subtotal: savedSubtotal,
        serviceFee: savedServiceFee,
        total: savedGrandTotal,
        paymentMethod: _paymentMethod,
        status: targetStatus,
        cartItems: savedCart,
      );

      if (!mounted) return;
      Navigator.pop(context); // close progress dialog

      setState(() {
        _cart.clear();
        _cashController.clear();
      });

      // Reload products to refresh stock counts
      _loadProducts();

      if (targetStatus == 'pesanan selesai') {
        // Langsung arahkan ke Halaman Cetak Nota
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptPrintScreen(
              order: newOrder,
              restaurantName: widget.restaurantName,
              cashAmount: cashGiven > 0 ? cashGiven : savedGrandTotal,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pesanan ${newOrder.invoiceNo} berhasil dibuat & masuk antrian dapur!'),
            backgroundColor: AppColors.statusPending,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memproses pesanan: $e'),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  StateSetter? _sheetSetState;

  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
    _sheetSetState?.call(() {});
  }

  void _openAddProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(onProductAdded: _loadProducts),
      ),
    ).then((_) => _loadProducts());
  }

  void _confirmDeleteProduct(DbProduct product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.statusCancelled, size: 26),
            SizedBox(width: 10),
            Expanded(child: Text('Hapus Produk?')),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${product.name}" dari katalog? Data produk akan dihapus secara permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusCancelled,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _posService.deleteProduct(product.id);
                setState(() {
                  _cart.removeWhere((item) => item.product.id == product.id);
                });
                await _loadProducts();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Produk "${product.name}" berhasil dihapus.'),
                      backgroundColor: AppColors.statusCompleted,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menghapus produk: $e'),
                      backgroundColor: AppColors.statusCancelled,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _openOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrdersScreen(
          restaurantName: widget.restaurantName,
          isAdmin: widget.userProfile.isAdmin,
        ),
      ),
    ).then((_) {
      _loadProducts();
      _refreshPendingOrders(notifyIfNew: false);
    });
  }

  void _openTableQr() {
    showDialog(
      context: context,
      builder: (_) => TableQrDialog(
        restaurantName: widget.restaurantName,
        initialTable: _selectedTable,
      ),
    );
  }

  void _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userProfile: _currentProfile,
          restaurantName: widget.restaurantName,
          onProfileUpdated: (updated) {
            setState(() {
              _currentProfile = updated;
            });
          },
        ),
      ),
    );
    // Refresh user profile if modified in profile screen
    final user = _posService.supabase.auth.currentUser;
    if (user != null) {
      final fresh = await _posService.fetchUserProfile(user.id);
      if (fresh != null && mounted) {
        setState(() => _currentProfile = fresh);
      }
    }
  }

  Future<void> _logout() async {
    await _posService.supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _openCartSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) {
          _sheetSetState = setSheet;

          // Keranjang kosong (dikosongkan / setelah checkout) -> tutup sheet.
          if (_cart.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final route = ModalRoute.of(ctx);
              if (ctx.mounted && route != null && route.isActive) {
                Navigator.of(ctx).removeRoute(route);
              }
            });
          }

          final media = MediaQuery.of(ctx);
          final height = (media.size.height - media.viewInsets.bottom) * 0.92;

          return Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: SizedBox(height: height, child: _buildCartPanel(isDark)),
          );
        },
      ),
    ).whenComplete(() => _sheetSetState = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);

    return Scaffold(
      appBar: _buildAppBar(isDark),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            // Pakai ukuran layar penuh (bukan constraints) supaya layout tidak
            // berpindah-pindah saat keyboard muncul.
            final size = MediaQuery.sizeOf(context);
            final isSplit = size.width >= 700 && size.height >= 480;

            // Tablet / emulator lebar: katalog + keranjang berdampingan.
            if (isSplit) {
              final cartWidth =
                  (c.maxWidth * 0.36).clamp(340.0, 460.0).toDouble();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildProductCatalogSection(isDark)),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  SizedBox(width: cartWidth, child: _buildCartPanel(isDark)),
                ],
              );
            }

            // HP: katalog + bar keranjang di bawah.
            return Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: _cart.isNotEmpty ? 84 : 0),
                    child: _buildProductCatalogSection(isDark),
                  ),
                ),
                if (_cart.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _buildMobileBottomCartBar(isDark),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // =========================================================================
  // APP BAR
  // =========================================================================
  PreferredSizeWidget _buildAppBar(bool isDark) {
    final phone = Responsive.isPhone(context);
    final muted = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    final canBackToAdmin =
        _currentProfile.isAdmin && widget.onBackToAdmin != null;

    final title = InkWell(
      onTap: _openProfile,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: phone ? 16 : 18,
              backgroundColor: AppColors.primary.withAlpha(40),
              backgroundImage: _currentProfile.avatarUrl != null &&
                      _currentProfile.avatarUrl!.isNotEmpty
                  ? NetworkImage(_currentProfile.avatarUrl!)
                  : null,
              child: _currentProfile.avatarUrl == null ||
                      _currentProfile.avatarUrl!.isEmpty
                  ? Text(
                      _currentProfile.initials,
                      style: TextStyle(
                        fontSize: phone ? 11 : 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.restaurantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.display(
                            fontWeight: FontWeight.w700,
                            fontSize: phone ? 15 : 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.statusCompleted.withAlpha(35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.statusCompleted.withAlpha(80)),
                        ),
                        child: Text(
                          _currentProfile.role.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.statusCompleted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Kasir: ${_currentProfile.fullName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: phone ? 11 : 12, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final pendingCount = _pendingOrders.length;

    final Widget ordersBadgeButton = pendingCount > 0
        ? Badge(
            label: Text(
              '$pendingCount',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
            backgroundColor: AppColors.primary,
            textColor: Colors.white,
            child: IconButton(
              tooltip: 'Cek Pesanan Meja ($pendingCount menunggu)',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: _openOrders,
            ),
          )
        : IconButton(
            tooltip: 'Riwayat & Status Pesanan',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: _openOrders,
          );

    final List<Widget> actions = phone
        ? [
            ordersBadgeButton,
            IconButton(
              tooltip: 'QR Meja Pelanggan',
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: _openTableQr,
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'add_product') _openAddProduct();
                if (v == 'profile') _openProfile();
                if (v == 'table_qr') _openTableQr();
                if (v == 'admin') widget.onBackToAdmin?.call();
                if (v == 'logout') _logout();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'add_product',
                  child: Row(children: [
                    Icon(Icons.add_circle_outline_rounded,
                        size: 20, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('Tambah Produk'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'table_qr',
                  child: Row(children: [
                    Icon(Icons.qr_code_2_rounded,
                        size: 20, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('QR Meja Pelanggan'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(children: [
                    Icon(Icons.account_circle_rounded,
                        size: 20, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('Profil & Absensi'),
                  ]),
                ),
                if (canBackToAdmin)
                  const PopupMenuItem(
                    value: 'admin',
                    child: Row(children: [
                      Icon(Icons.admin_panel_settings_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Ke Admin'),
                    ]),
                  ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout_rounded,
                        size: 20, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Keluar Akun'),
                  ]),
                ),
              ],
            ),
          ]
        : [
            if (canBackToAdmin)
              TextButton.icon(
                onPressed: widget.onBackToAdmin,
                icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                label: const Text('Ke Admin'),
              ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: _openAddProduct,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Tambah Produk', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: pendingCount > 0
                    ? (isDark ? AppColors.yellowSoftDark : AppColors.yellowSoft)
                    : null,
                side: BorderSide(
                  color: pendingCount > 0
                      ? AppColors.amber
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                foregroundColor: pendingCount > 0
                    ? (isDark ? AppColors.yellow : AppColors.yellowText)
                    : (isDark ? AppColors.darkText : AppColors.lightText),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onPressed: _openOrders,
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(
                pendingCount > 0 ? 'Pesanan ($pendingCount)' : 'Pesanan',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'QR Meja Pelanggan',
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: _openTableQr,
            ),
            IconButton(
              tooltip: 'Profil & Absensi Pegawai',
              icon: const Icon(Icons.account_circle_rounded),
              onPressed: _openProfile,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Keluar Akun',
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              onPressed: _logout,
            ),
            const SizedBox(width: 8),
          ];

    return AppBar(
      toolbarHeight: phone ? kToolbarHeight : 64,
      titleSpacing: phone ? 12 : 20,
      title: title,
      actions: actions,
    );
  }

  // =========================================================================
  // KATALOG PRODUK (grid adaptif)
  // =========================================================================
  Widget _buildProductCatalogSection(bool isDark) {
    final filtered = _filteredProducts;
    final muted = isDark ? AppColors.darkMuted : AppColors.lightMuted;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final big = Responsive.isTabletUp(context);
        final pad = big ? 20.0 : 16.0;
        // HP portrait: daftar 1 kolom. Selain itu: grid adaptif.
        final listMode = Responsive.isPhone(context) && w < 440;

        return Column(
          children: [
            // Search & kategori
            Container(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
              color: isDark ? AppColors.darkSurface : Colors.white,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: TextStyle(fontSize: big ? 15 : 14),
                    decoration: InputDecoration(
                      hintText: 'Cari menu makanan atau minuman...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: isDark ? AppColors.darkCard : AppColors.lightBg,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: big ? 14 : 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: isSelected,
                            label: Text(cat),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? AppColors.darkText : AppColors.lightText),
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: big ? 14 : 12,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor:
                                isDark ? AppColors.darkCard : AppColors.lightBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder),
                              ),
                            ),
                            onSelected: (val) {
                              setState(() => _selectedCategory = cat);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            if (_pendingOrders.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 10, pad, 2),
                child: InkWell(
                  onTap: _openOrders,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.yellowSoftDark
                          : AppColors.yellowSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.amber.withAlpha(140),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(24),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.table_restaurant_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_pendingOrders.length} pesanan meja menunggu dicek (${_pendingTablesSummary()}). Tanya nomor meja pelanggan lalu cek di Pesanan.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.yellowText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Cek',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Produk
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withAlpha(25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _products.isEmpty
                                        ? Icons.storefront_rounded
                                        : (_products.every((p) => p.stock <= 0)
                                            ? Icons.inventory_2_outlined
                                            : Icons.search_off_rounded),
                                    size: 54,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _products.isEmpty
                                      ? 'Menu Restoran Masih Kosong'
                                      : (_products.every((p) => p.stock <= 0)
                                          ? 'Semua Stok Produk Habis'
                                          : 'Menu Tidak Ditemukan'),
                                  style: AppFonts.display(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.darkText : AppColors.lightText,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _products.isEmpty
                                      ? 'Tambahkan menu makanan atau minuman beserta harga, stok, dan foto asli melalui form tambah produk.'
                                      : (_products.every((p) => p.stock <= 0)
                                          ? 'Produk yang kehabisan stok otomatis disembunyikan dari dashboard kasir. Silakan perbarui stok atau masukkan produk baru.'
                                          : 'Tidak ada produk yang cocok dengan pencarian "$_search" atau filter kategori "$_selectedCategory".'),
                                  style: TextStyle(fontSize: 13, color: muted, height: 1.4),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _openAddProduct,
                                  icon: const Icon(Icons.add_circle_outline_rounded),
                                  label: Text(
                                    _products.isEmpty ? 'Masukkan Produk Pertama' : 'Tambah Produk Baru',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadProducts,
                          color: AppColors.primary,
                          child: listMode
                              ? ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.all(pad),
                                  itemCount: filtered.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) =>
                                      _buildProductCard(filtered[index], isDark, true),
                                )
                              : GridView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.all(pad),
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: big ? 220 : 200,
                                    mainAxisExtent: big ? 250 : 232,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) =>
                                      _buildProductCard(filtered[index], isDark, false),
                                ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductCard(DbProduct p, bool isDark, bool isListMode) {
    final out = p.stock <= 0;
    final muted = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    final big = Responsive.isTabletUp(context);

    Widget image(double iconSize) {
      return ProductImageView(
        imageUrl: p.imageUrl,
        fallbackIcon: p.iconData,
        iconSize: iconSize,
      );
    }

    // ---------- Mode daftar (HP portrait) ----------
    if (isListMode) {
      return Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: out ? null : () => _addToCart(p),
          onLongPress: () => _confirmDeleteProduct(p),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: image(28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${p.category} • Stok: ${p.stock}',
                        style: TextStyle(
                          fontSize: 11,
                          color: out ? AppColors.statusCancelled : muted,
                          fontWeight: out ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (p.description != null &&
                          p.description!.trim().isNotEmpty) ...[
                        Text(
                          p.description!.trim(),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: muted,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _formatRupiah(p.price),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.statusCancelled, size: 22),
                  tooltip: 'Hapus Produk',
                  onPressed: () => _confirmDeleteProduct(p),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: out ? Colors.grey : AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: out ? null : () => _addToCart(p),
                  child: Text(
                    out ? 'Habis' : '+ Tambah',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ---------- Mode grid (tablet / emulator / HP landscape) ----------
    final addSize = big ? 38.0 : 30.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: out ? null : () => _addToCart(p),
        onLongPress: () => _confirmDeleteProduct(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: isDark ? AppColors.darkSurface : AppColors.lightBg,
                    child: image(big ? 46 : 40),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _confirmDeleteProduct(p),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(140),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: out ? Colors.red : Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        out ? 'Habis' : 'Stok: ${p.stock}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: big ? 14 : 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    p.category,
                    style: TextStyle(fontSize: big ? 11 : 10, color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatRupiah(p.price),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: big ? 14 : 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: addSize,
                        height: addSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: out
                              ? Colors.grey.withAlpha(40)
                              : AppColors.primary.withAlpha(40),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.add,
                          size: big ? 20 : 16,
                          color: out ? Colors.grey : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PANEL KERANJANG & CHECKOUT
  // =========================================================================
  Widget _buildCartPanel(bool isDark) {
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final muted = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    // HP landscape (layar pendek): selector meja dipindah ke area scroll bawah.
    final compactHeight = MediaQuery.sizeOf(context).height < 600;

    return LayoutBuilder(
      builder: (context, c) {
        final big = Responsive.isTabletUp(context);
        final pad = big ? 20.0 : 16.0;
        final maxBottom = c.maxHeight * (compactHeight ? 0.7 : 0.62);

        return Container(
          color: isDark ? AppColors.darkSurface : Colors.white,
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Keranjang Pesanan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: big ? 17 : 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_cart.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_cart.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _cart.clear()),
                        child: const Text(
                          'Kosongkan',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              if (!compactHeight)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 10, pad, 4),
                  child: _buildTableSelector(isDark, big),
                ),

              // Daftar item
              Expanded(
                child: _cart.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.remove_shopping_cart_outlined,
                                size: 48, color: muted),
                            const SizedBox(height: 8),
                            Text(
                              'Keranjang masih kosong',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
                        itemCount: _cart.length,
                        itemBuilder: (context, idx) {
                          final item = _cart[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: EdgeInsets.all(big ? 12 : 10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : AppColors.lightBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.product.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: big ? 14 : 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatRupiah(item.total),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: big ? 14 : 13,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${_formatRupiah(item.product.price)} / pcs',
                                        style: TextStyle(
                                          fontSize: big ? 12 : 11,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                    _qtyButton(Icons.remove,
                                        () => _decreaseCartItem(idx), isDark, big),
                                    Container(
                                      constraints: const BoxConstraints(minWidth: 34),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${item.qty}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: big ? 15 : 13,
                                        ),
                                      ),
                                    ),
                                    _qtyButton(Icons.add,
                                        () => _increaseCartItem(idx), isDark, big),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Pembayaran (area ini bisa di-scroll agar aman di layar pendek / keyboard)
              Container(
                constraints: BoxConstraints(maxHeight: maxBottom),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  border: Border(top: BorderSide(color: border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compactHeight) ...[
                        _buildTableSelector(isDark, big),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'Metode Bayar',
                        style: TextStyle(
                          fontSize: big ? 13 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: ['Tunai', 'QRIS', 'Transfer Bank', 'Debit / EDC'].map((m) {
                          final sel = _paymentMethod == m;
                          return ChoiceChip(
                            label: Text(m),
                            selected: sel,
                            showCheckmark: false,
                            selectedColor: AppColors.primary,
                            backgroundColor:
                                isDark ? AppColors.darkSurface : AppColors.lightBg,
                            labelStyle: TextStyle(
                              fontSize: big ? 13 : 12,
                              fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                              color: sel
                                  ? Colors.white
                                  : (isDark ? AppColors.darkText : AppColors.lightText),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: sel ? AppColors.primary : border,
                              ),
                            ),
                            onSelected: (_) => setState(() => _paymentMethod = m),
                          );
                        }).toList(),
                      ),
                      if (_paymentMethod == 'Tunai') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _cashController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: big ? 15 : 13),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Uang Tunai Diterima (Rp)',
                            hintText: 'Contoh: 50000',
                            prefixText: 'Rp ',
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            suffixIcon: _cashController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _cashController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            ActionChip(
                              label: const Text('Uang Pas', style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                setState(() {
                                  _cashController.text = _grandTotal.toString();
                                });
                              },
                            ),
                            ActionChip(
                              label: const Text('20rb', style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                setState(() {
                                  _cashController.text = '20000';
                                });
                              },
                            ),
                            ActionChip(
                              label: const Text('50rb', style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                setState(() {
                                  _cashController.text = '50000';
                                });
                              },
                            ),
                            ActionChip(
                              label: const Text('100rb', style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                setState(() {
                                  _cashController.text = '100000';
                                });
                              },
                            ),
                          ],
                        ),
                        if ((int.tryParse(_cashController.text.trim()) ?? 0) >= _grandTotal && _grandTotal > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Kembalian:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                                ),
                              ),
                              Text(
                                _formatRupiah((int.tryParse(_cashController.text.trim()) ?? 0) - _grandTotal),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusCompleted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 10),
                      _buildCartSummaryRow('Subtotal', _formatRupiah(_subtotal), isDark, big),
                      _buildCartSummaryRow(
                          'Layanan Resto (5%)', _formatRupiah(_serviceFee), isDark, big),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TOTAL BAYAR',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: big ? 15 : 14,
                            ),
                          ),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatRupiah(_grandTotal),
                                style: AppFonts.display(
                                  fontWeight: FontWeight.w800,
                                  fontSize: big ? 21 : 17,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, bc) {
                          final stacked = bc.maxWidth < 380;
                          final h = big ? 54.0 : 48.0;

                          final saveBtn = SizedBox(
                            height: h,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.statusPending,
                                side: const BorderSide(
                                  color: AppColors.statusPending,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _cart.isEmpty
                                  ? null
                                  : () => _processCheckout(targetStatus: 'pesanan dibuat'),
                              child: Text(
                                'Simpan (Belum Bayar)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: big ? 13 : 12,
                                ),
                              ),
                            ),
                          );

                          final isQris = _paymentMethod == 'QRIS';
                          final isBank = _paymentMethod.contains('Transfer') || _paymentMethod.contains('Virtual');
                          final isDebit = _paymentMethod.contains('Debit');

                          final payBtn = SizedBox(
                            height: h,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _cart.isEmpty
                                  ? null
                                  : () => _processCheckout(targetStatus: 'pesanan selesai'),
                              icon: Icon(
                                isQris
                                    ? Icons.qr_code_scanner_rounded
                                    : (isBank
                                        ? Icons.account_balance_rounded
                                        : (isDebit ? Icons.credit_card_rounded : Icons.print_rounded)),
                                size: 18,
                              ),
                              label: Text(
                                isQris
                                    ? 'Bayar QRIS (Scan Kamera)'
                                    : (isBank
                                        ? 'Bayar Transfer Bank'
                                        : (isDebit ? 'Bayar Kartu Debit' : 'Bayar & Cetak Nota')),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: big ? 14 : 13,
                                ),
                              ),
                            ),
                          );

                          if (stacked) {
                            return Column(
                              children: [
                                SizedBox(width: double.infinity, child: payBtn),
                                const SizedBox(height: 8),
                                SizedBox(width: double.infinity, child: saveBtn),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: saveBtn),
                              const SizedBox(width: 10),
                              Expanded(flex: 2, child: payBtn),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableSelector(bool isDark, bool big) {
    return Row(
      children: [
        Text(
          'Nomor Meja:',
          style: TextStyle(fontSize: big ? 14 : 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(10, (i) {
                final tableNum = i + 1;
                final isSelected = _selectedTable == tableNum;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => _selectedTable = tableNum),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      constraints: BoxConstraints(minWidth: big ? 42 : 36),
                      padding: EdgeInsets.symmetric(
                        horizontal: big ? 12 : 10,
                        vertical: big ? 10 : 7,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkCard : AppColors.lightBg),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                      ),
                      child: Text(
                        '$tableNum',
                        style: AppFonts.display(
                          fontSize: big ? 14 : 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.darkText : AppColors.lightText),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap, bool isDark, bool big) {
    final size = big ? 38.0 : 30.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Icon(icon, size: big ? 20 : 16),
      ),
    );
  }

  Widget _buildCartSummaryRow(String label, String value, bool isDark, bool big) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: big ? 13 : 12,
              color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: big ? 13 : 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // Bar keranjang di bawah (HP)
  Widget _buildMobileBottomCartBar(bool isDark) {
    return InkWell(
      onTap: () => _openCartSheet(isDark),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(80),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  '${_cart.length} Menu',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatRupiah(_grandTotal),
                        style: AppFonts.display(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}