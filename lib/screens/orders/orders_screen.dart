import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/screens/cashier/receipt_print_screen.dart';
import 'package:my_app/screens/cashier/qris_payment_dialog.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/core/utils/responsive.dart';

class OrdersScreen extends StatefulWidget {
  final String restaurantName;
  final bool isAdmin;
  final int? initialTableFilter;

  const OrdersScreen({
    super.key,
    required this.restaurantName,
    this.isAdmin = false,
    this.initialTableFilter,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _posService = PosService();
  List<DbOrder> _orders = [];
  bool _isLoading = true;
  String _selectedFilter = 'Semua';
  int? _selectedTableFilter;
  String _searchQuery = '';

  final List<String> _filterTabs = [
    'Semua',
    'Menunggu Dicek / Bayar',
    'Selesai',
    'Dibatalkan',
  ];

  Timer? _autoRefreshTimer;
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _selectedTableFilter = widget.initialTableFilter;
    if (_selectedTableFilter != null) {
      _selectedFilter = 'Menunggu Dicek / Bayar';
    }
    _loadOrders();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _ordersChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _silentRefreshOrders() async {
    if (!mounted) return;
    try {
      final loaded = await _posService.fetchOrders();
      if (mounted) {
        setState(() {
          _orders = loaded;
        });
      }
    } catch (e) {
      debugPrint('Auto refresh orders error: $e');
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _ordersChannel?.unsubscribe();

    try {
      _ordersChannel = _posService.supabase
          .channel('orders-screen-realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => _silentRefreshOrders(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Supabase realtime orders fallback: $e');
    }

    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _silentRefreshOrders(),
    );
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final loaded = await _posService.fetchOrders();
    if (mounted) {
      setState(() {
        _orders = loaded;
        _isLoading = false;
      });
    }
  }

  String _formatRupiah(int val) {
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return f.format(val);
  }

  bool _isPendingOrder(DbOrder o) {
    final s = o.status.toLowerCase();
    return s == 'pesanan dibuat' || s == 'pending';
  }

  bool _isCompletedOrder(DbOrder o) {
    final s = o.status.toLowerCase();
    return s == 'pesanan selesai' || s == 'selesai';
  }

  bool _isTableWebOrder(DbOrder o) {
    return o.isQrSource ||
        o.paymentMethod.toLowerCase().contains('(meja)') ||
        o.cashierName.toLowerCase().startsWith('meja ');
  }

  /// Pesanan dari website yang pembayaran QRIS-nya sudah selesai di website.
  /// Kasir TIDAK perlu memproses pembayaran lagi.
  bool _isWebQrisPaid(DbOrder o) {
    if (!_isTableWebOrder(o)) return false;
    final m = o.paymentMethod.toUpperCase();
    final isQrisMethod = m.contains('QRIS') || m == 'CASHIER';
    final isPaidStatus =
        o.paymentStatus == 'paid' || o.paymentStatus == 'demo_paid';
    return isQrisMethod && isPaidStatus;
  }

  int get _totalOrdersCount => _orders.length;

  int get _unpaidOrdersCount => _orders.where(_isPendingOrder).length;

  int get _unpaidOrdersSum =>
      _orders.where(_isPendingOrder).fold(0, (sum, o) => sum + o.total);

  int get _completedOrdersCount => _orders.where(_isCompletedOrder).length;

  int get _totalRevenueSum =>
      _orders.where(_isCompletedOrder).fold(0, (sum, o) => sum + o.total);

  List<int> get _activeTables {
    final tables = _orders.map((o) => o.tableNumber).toSet().toList()..sort();
    return tables;
  }

  List<DbOrder> get _filteredOrders {
    return _orders.where((order) {
      bool matchFilter = true;
      if (_selectedFilter == 'Menunggu Dicek / Bayar') {
        matchFilter = _isPendingOrder(order);
      } else if (_selectedFilter == 'Selesai') {
        matchFilter = _isCompletedOrder(order);
      } else if (_selectedFilter == 'Dibatalkan') {
        final s = order.status.toLowerCase();
        matchFilter = s == 'dibatalkan' || s == 'batal';
      }

      final matchTable = _selectedTableFilter == null ||
          order.tableNumber == _selectedTableFilter;

      final q = _searchQuery.toLowerCase().trim();
      final matchQuery = q.isEmpty ||
          order.invoiceNo.toLowerCase().contains(q) ||
          order.cashierName.toLowerCase().contains(q) ||
          order.tableNumber.toString() == q ||
          'meja ${order.tableNumber}'.contains(q) ||
          order.paymentMethod.toLowerCase().contains(q);

      return matchFilter && matchTable && matchQuery;
    }).toList();
  }

  Future<void> _changeStatus(DbOrder order, String newStatus) async {
    try {
      await _posService.updateOrderStatus(order.id, newStatus);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status pesanan Meja ${order.tableNumber} (${order.invoiceNo}) diubah menjadi "$newStatus".',
          ),
          backgroundColor: newStatus == 'pesanan selesai'
              ? AppColors.statusCompleted
              : AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );

      _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengubah status: $e'),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openQrisPaymentForOrder(DbOrder order) async {
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrisPaymentDialog(
        restaurantName: widget.restaurantName,
        totalAmount: order.total,
        invoiceNo: order.invoiceNo,
        tableNumber: order.tableNumber,
        cashierName: order.cashierName,
        paymentMethod: order.paymentMethod.toUpperCase().contains('VIRTUAL')
            ? 'Virtual Account'
            : 'QRIS',
        existingOrder: order,
      ),
    );

    if (paid == true) {
      _loadOrders();
    }
  }

  Future<void> _openCashPaymentForOrder(DbOrder order) async {
    final cashCtrl = TextEditingController(text: order.total.toString());
    final isDark = ThemeController.isDark(context);

    final paidAmount = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final cashGiven = int.tryParse(cashCtrl.text.trim()) ?? 0;
          final change = cashGiven - order.total;
          final isEnough = cashGiven >= order.total;

          return AlertDialog(
            backgroundColor: AppColors.card(ctx),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border(ctx)),
            ),
            title: Text(
              'Konfirmasi Pembayaran Meja ${order.tableNumber}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'No. Nota: ${order.invoiceNo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted(ctx),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface(ctx),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border(ctx)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Tagihan',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatRupiah(order.total),
                          style: AppFonts.display(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cashCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDlg(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Uang Tunai Diterima (Rp)',
                      prefixText: 'Rp ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        label: const Text('Uang Pas',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDlg(() => cashCtrl.text = order.total.toString());
                        },
                      ),
                      ActionChip(
                        label:
                            const Text('50rb', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDlg(() => cashCtrl.text = '50000');
                        },
                      ),
                      ActionChip(
                        label:
                            const Text('100rb', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDlg(() => cashCtrl.text = '100000');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kembalian',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                      Text(
                        isEnough
                            ? _formatRupiah(change)
                            : 'Kurang ${_formatRupiah(-change)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isEnough
                              ? AppColors.statusCompleted
                              : AppColors.statusCancelled,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: isEnough ? () => Navigator.pop(ctx, cashGiven) : null,
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('Lunas & Cetak Struk'),
              ),
            ],
          );
        },
      ),
    );
    cashCtrl.dispose();

    if (paidAmount == null || !mounted) return;

    try {
      await _posService.updateOrderStatus(order.id, 'pesanan selesai');
      await _loadOrders();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPrintScreen(
            order: DbOrder(
              id: order.id,
              invoiceNo: order.invoiceNo,
              createdAt: order.createdAt,
              cashierName: order.cashierName,
              tableNumber: order.tableNumber,
              subtotal: order.subtotal,
              serviceFee: order.serviceFee,
              total: order.total,
              paymentMethod: order.paymentMethod,
              paymentStatus: 'paid',
              orderSource: order.orderSource,
              status: 'pesanan selesai',
              items: order.items,
            ),
            restaurantName: widget.restaurantName,
            cashAmount: paidAmount,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyelesaikan pesanan: $e'),
          backgroundColor: AppColors.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildStatusBadge(String status, bool isDark) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (s == 'pesanan selesai' || s == 'selesai') {
      bg = AppColors.statusCompleted.withAlpha(28);
      fg = AppColors.statusCompleted;
      label = 'Selesai';
      icon = Icons.check_circle_rounded;
    } else if (s == 'dibatalkan' || s == 'batal') {
      bg = AppColors.statusCancelled.withAlpha(28);
      fg = AppColors.statusCancelled;
      label = 'Dibatalkan';
      icon = Icons.cancel_rounded;
    } else {
      bg = isDark ? AppColors.yellowSoftDark : AppColors.yellowSoft;
      fg = isDark ? AppColors.yellow : AppColors.yellowText;
      label = 'Menunggu Dicek';
      icon = Icons.access_time_filled_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withAlpha(110)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodBadge(String method, bool isDark) {
    IconData icon = Icons.payments_rounded;
    Color color = AppColors.primary;
    final m = method.toLowerCase();
    String displayLabel = method;

    if (m.contains('qris_demo') || m.contains('qris demo')) {
      icon = Icons.qr_code_2_rounded;
      color = AppColors.statusPending;
      displayLabel = 'QRIS (MODE DEMO)';
    } else if (m.contains('qris')) {
      icon = Icons.qr_code_scanner_rounded;
      color = AppColors.primary;
    } else if (m == 'cashier') {
      icon = Icons.point_of_sale_rounded;
      color = AppColors.primary;
      displayLabel = 'Bayar di Kasir';
    } else if (m.contains('virtual') ||
        m.contains('transfer') ||
        m.contains('debit')) {
      icon = Icons.account_balance_rounded;
      color = AppColors.yellowText;
    } else {
      icon = Icons.payments_outlined;
      color = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            displayLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusChip(DbOrder order) {
    Color color;
    String label;
    IconData icon;

    if (_isWebQrisPaid(order)) {
      // Pesanan website, sudah lunas via QRIS — tampilkan badge spesial
      color = AppColors.statusCompleted;
      label = 'LUNAS · QRIS';
      icon = Icons.qr_code_2_rounded;
    } else if (order.isPaid) {
      color = AppColors.statusCompleted;
      label = 'LUNAS';
      icon = Icons.check_circle_rounded;
    } else if (order.isDemoPaid) {
      color = AppColors.primary;
      label = 'DEMO BERHASIL';
      icon = Icons.qr_code_scanner_rounded;
    } else {
      color = AppColors.statusPending;
      label = 'BELUM DIBAYAR';
      icon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetailModal(DbOrder order, bool isDark) {
    final isPending = _isPendingOrder(order);
    final isWeb = _isTableWebOrder(order);
    final isWebQrisPaid = _isWebQrisPaid(order);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border(ctx),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Meja ${order.tableNumber}',
                                style: AppFonts.display(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                order.invoiceNo,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd MMMM yyyy, HH:mm', 'id_ID')
                              .format(order.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(order.status, isDark),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    isWeb
                        ? 'Pemesan: ${order.cashierName}'
                        : 'Kasir: ${order.cashierName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  _buildPaymentMethodBadge(order.paymentMethod, isDark),
                  _buildPaymentStatusChip(order),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Daftar Menu',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 190),
                decoration: BoxDecoration(
                  color: AppColors.surface(ctx),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(ctx)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: order.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final it = order.items[i];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${it.quantity}x ${it.productName}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          _formatRupiah(it.subtotal),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal', style: TextStyle(fontSize: 12)),
                  Text(_formatRupiah(order.subtotal),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Layanan Resto (5%)',
                      style: TextStyle(fontSize: 12)),
                  Text(_formatRupiah(order.serviceFee),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Akhir',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _formatRupiah(order.total),
                    style: AppFonts.display(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Banner QRIS sudah lunas (dari website)
              if (isWebQrisPaid) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.statusCompleted.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.statusCompleted.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.statusCompleted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pembayaran QRIS Sudah Lunas',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.statusCompleted,
                              ),
                            ),
                            Text(
                              'Pelanggan telah menyelesaikan pembayaran via QRIS di website. Kasir tidak perlu memproses pembayaran lagi.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkMuted
                                    : AppColors.lightMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Cetak Nota'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReceiptPrintScreen(
                            order: order,
                            restaurantName: widget.restaurantName,
                            cashAmount: order.total,
                          ),
                        ),
                      );
                    },
                  ),
                  // Hanya tampilkan tombol selesai manual jika QRIS sudah lunas dari website
                  if (isPending && isWebQrisPaid) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.statusCompleted,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: const Text('Tandai Selesai'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _changeStatus(order, 'pesanan selesai');
                      },
                    ),
                  ] else if (isPending && !isWebQrisPaid) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Bayar Tunai'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openCashPaymentForOrder(order);
                      },
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text('Bayar QRIS'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openQrisPaymentForOrder(order);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);
    final filtered = _filteredOrders;
    final activeTables = _activeTables;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Daftar Pesanan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Perbarui daftar pesanan',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadOrders,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Summary KPI Cards
            Container(
              color: AppColors.card(context),
              child: MaxWidthBox(
                maxWidth: 960,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final isNarrow = c.maxWidth < 600;

                    final cards = [
                      _buildKpiCard(
                        title: 'Total Pesanan',
                        count: '$_totalOrdersCount',
                        subtext: 'Semua transaksi',
                        icon: Icons.receipt_long_rounded,
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                      _buildKpiCard(
                        title: 'Menunggu Dicek',
                        count: '$_unpaidOrdersCount',
                        subtext: _formatRupiah(_unpaidOrdersSum),
                        icon: Icons.pending_actions_rounded,
                        color: isDark ? AppColors.yellow : AppColors.yellowText,
                        isDark: isDark,
                      ),
                      _buildKpiCard(
                        title: 'Pesanan Selesai',
                        count: '$_completedOrdersCount',
                        subtext: _formatRupiah(_totalRevenueSum),
                        icon: Icons.verified_rounded,
                        color: AppColors.statusCompleted,
                        isDark: isDark,
                      ),
                    ];

                    if (isNarrow) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: cards
                              .map((w) => Container(
                                    width: 175,
                                    margin: const EdgeInsets.only(right: 8),
                                    child: w,
                                  ))
                              .toList(),
                        ),
                      );
                    }

                    return Row(
                      children: cards
                          .map((w) => Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: w,
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
              ),
            ),

            // Search and Filter Bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                border: Border(
                  bottom: BorderSide(color: AppColors.border(context)),
                ),
              ),
              child: MaxWidthBox(
                maxWidth: 960,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: const InputDecoration(
                        hintText:
                            'Cari nomor meja (contoh: 2), no. nota, atau nama pemesan...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filterTabs.map((tab) {
                          final isSelected = _selectedFilter == tab;
                          int count = 0;
                          if (tab == 'Semua') {
                            count = _orders.length;
                          } else if (tab == 'Menunggu Dicek / Bayar') {
                            count = _unpaidOrdersCount;
                          } else if (tab == 'Selesai') {
                            count = _completedOrdersCount;
                          } else {
                            count = _orders
                                .where((o) =>
                                    o.status.toLowerCase().contains('batal'))
                                .length;
                          }

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              selected: isSelected,
                              showCheckmark: false,
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(tab),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withAlpha(50)
                                          : AppColors.border(context),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.text(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.text(context),
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 12,
                              ),
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.surface(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border(context),
                                ),
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedFilter = tab),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (activeTables.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: const Text('Semua Meja'),
                                selected: _selectedTableFilter == null,
                                showCheckmark: false,
                                selectedColor: isDark
                                    ? AppColors.yellowSoftDark
                                    : AppColors.yellowSoft,
                                backgroundColor: AppColors.surface(context),
                                side: BorderSide(
                                  color: _selectedTableFilter == null
                                      ? AppColors.amber
                                      : AppColors.border(context),
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _selectedTableFilter == null
                                      ? (isDark
                                          ? AppColors.yellow
                                          : AppColors.yellowText)
                                      : AppColors.muted(context),
                                ),
                                onSelected: (_) =>
                                    setState(() => _selectedTableFilter = null),
                              ),
                            ),
                            ...activeTables.map((t) {
                              final sel = _selectedTableFilter == t;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text('Meja $t'),
                                  selected: sel,
                                  showCheckmark: false,
                                  selectedColor: isDark
                                      ? AppColors.yellowSoftDark
                                      : AppColors.yellowSoft,
                                  backgroundColor: AppColors.surface(context),
                                  side: BorderSide(
                                    color: sel
                                        ? AppColors.amber
                                        : AppColors.border(context),
                                  ),
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: sel
                                        ? (isDark
                                            ? AppColors.yellow
                                            : AppColors.yellowText)
                                        : AppColors.text(context),
                                  ),
                                  onSelected: (_) => setState(
                                    () => _selectedTableFilter = sel ? null : t,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Order List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 52,
                                color: AppColors.muted(context),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Belum ada pesanan untuk filter ini.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted(context),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadOrders,
                          color: AppColors.primary,
                          child: MaxWidthBox(
                            maxWidth: 960,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final order = filtered[index];
                                final isCompleted = _isCompletedOrder(order);
                                final isCancelled = order.status
                                        .toLowerCase() ==
                                    'dibatalkan' ||
                                    order.status.toLowerCase() == 'batal';
                                final isPending = !isCompleted && !isCancelled;
                                final isWebOrder = _isTableWebOrder(order);
                                final isWebQrisPaid = _isWebQrisPaid(order);

                                final dateStr = DateFormat(
                                        'dd MMM yyyy, HH:mm', 'id_ID')
                                    .format(order.createdAt);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    onTap: () =>
                                        _showOrderDetailModal(order, isDark),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Header Row: Meja Pill, Invoice & Status Badge
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Meja ${order.tableNumber}',
                                                  style: AppFonts.display(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      order.invoiceNo,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      dateStr,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.muted(
                                                            context),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _buildStatusBadge(
                                                  order.status, isDark),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          const Divider(height: 1),
                                          const SizedBox(height: 10),

                                          // Meta Wrap (anti-overflow on narrow mobile)
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              if (isWebOrder)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isDark
                                                        ? AppColors
                                                            .yellowSoftDark
                                                        : AppColors.yellowSoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    border: Border.all(
                                                      color: AppColors.amber
                                                          .withAlpha(110),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Pesanan Website Meja',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: isDark
                                                          ? AppColors.yellow
                                                          : AppColors
                                                              .yellowText,
                                                    ),
                                                  ),
                                                ),
                                              Text(
                                                isWebOrder
                                                    ? 'Pemesan: ${order.cashierName}'
                                                    : 'Kasir: ${order.cashierName}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppColors.muted(
                                                      context),
                                                ),
                                              ),
                                              _buildPaymentMethodBadge(
                                                  order.paymentMethod, isDark),
                                              _buildPaymentStatusChip(order),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // Order Items Preview
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: AppColors.surface(context),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color:
                                                    AppColors.border(context),
                                              ),
                                            ),
                                            child: Column(
                                              children: order.items.map((it) {
                                                return Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 3),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '${it.quantity}x ${it.productName}',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 12),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        _formatRupiah(
                                                            it.subtotal),
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                          const SizedBox(height: 14),

                                          // Bottom Row: Total & Action Buttons
                                          LayoutBuilder(
                                            builder:
                                                (context, cardConstraints) {
                                              final totalWidget = Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    isWebQrisPaid
                                                        ? 'Total Lunas · QRIS'
                                                        : isPending
                                                            ? 'Total Tagihan (Belum Bayar)'
                                                            : 'Total Pembayaran',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: isPending
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                      color: isWebQrisPaid
                                                          ? AppColors.statusCompleted
                                                          : isPending
                                                              ? AppColors.statusPending
                                                              : AppColors.muted(context),
                                                    ),
                                                  ),
                                                  Text(
                                                    _formatRupiah(order.total),
                                                    style: AppFonts.display(
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: isPending
                                                          ? AppColors.primary
                                                          : AppColors.text(
                                                              context),
                                                    ),
                                                  ),
                                                ],
                                              );

                                              final printNotaButton =
                                                  OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.text(context),
                                                  side: BorderSide(
                                                    color: AppColors.border(
                                                        context),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                    Icons.print_rounded,
                                                    size: 16),
                                                label: const Text('Cetak Nota',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ReceiptPrintScreen(
                                                        order: order,
                                                        restaurantName: widget
                                                            .restaurantName,
                                                        cashAmount: order.total,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );

                                              final payCashButton =
                                                  ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primary,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _openCashPaymentForOrder(
                                                        order),
                                                child: const Text(
                                                  'Bayar Tunai',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              );

                                              final payQrisButton =
                                                  OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.primary,
                                                  side: const BorderSide(
                                                      color: AppColors.primary),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                    Icons
                                                        .qr_code_scanner_rounded,
                                                    size: 16),
                                                label: const Text(
                                                  'QRIS',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _openQrisPaymentForOrder(
                                                        order),
                                              );

                                              final completeManualButton =
                                                  ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.statusCompleted,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                                onPressed: () => _changeStatus(
                                                    order, 'pesanan selesai'),
                                                child: const Text('Selesai',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                              );

                                              final cancelButton =
                                                  OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.statusCancelled,
                                                  side: const BorderSide(
                                                      color: AppColors
                                                          .statusCancelled),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 8),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                                onPressed: () => _changeStatus(
                                                    order, 'dibatalkan'),
                                                child: const Text('Batal',
                                                    style: TextStyle(
                                                        fontSize: 12)),
                                              );

                                              if (cardConstraints.maxWidth <
                                                  520) {
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        totalWidget,
                                                        printNotaButton,
                                                      ],
                                                    ),
                                                    if (isPending) ...[
                                                      const SizedBox(
                                                          height: 10),
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        children: [
                                                          if (!isWebQrisPaid) payCashButton,
                                                          if (!isWebQrisPaid) payQrisButton,
                                                          completeManualButton,
                                                          cancelButton,
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                );
                                              }

                                              return Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  totalWidget,
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: [
                                                      printNotaButton,
                                                      if (isPending) ...[
                                                        if (!isWebQrisPaid) payCashButton,
                                                        if (!isWebQrisPaid) payQrisButton,
                                                        completeManualButton,
                                                        cancelButton,
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String count,
    required String subtext,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.muted(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  count,
                  style: AppFonts.display(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  subtext,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
