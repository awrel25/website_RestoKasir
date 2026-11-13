import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/screens/admin/add_product_screen.dart';
import 'package:my_app/screens/orders/orders_screen.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/core/utils/responsive.dart';
import 'package:my_app/screens/profile/profile_screen.dart';
import 'package:my_app/screens/cashier/table_qr_dialog.dart';
import 'package:my_app/widgets/product_image_view.dart';

class AdminScreen extends StatefulWidget {
  final UserProfile userProfile;
  final String restaurantName;
  final VoidCallback onOpenPos;

  const AdminScreen({
    super.key,
    required this.userProfile,
    required this.restaurantName,
    required this.onOpenPos,
  });

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _posService = PosService();
  late TabController _tabController;
  late UserProfile _currentProfile;

  bool _isLoading = true;
  List<DbProduct> _products = [];
  List<DbOrder> _orders = [];
  List<UserProfile> _staff = [];

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.userProfile;
    _tabController = TabController(length: 3, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _posService.fetchProducts(),
        _posService.fetchOrders(),
        _posService.fetchStaffList(),
      ]);

      if (mounted) {
        setState(() {
          _products = results[0] as List<DbProduct>;
          _orders = results[1] as List<DbOrder>;
          _staff = results[2] as List<UserProfile>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatRupiah(int val) {
    final f = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return f.format(val);
  }

  int get _totalCompletedSales {
    return _orders
        .where((o) {
          final s = o.status.toLowerCase();
          return s == 'pesanan selesai' || s == 'selesai';
        })
        .fold(0, (sum, o) => sum + o.total);
  }

  int get _completedOrdersCount {
    return _orders.where((o) {
      final s = o.status.toLowerCase();
      return s == 'pesanan selesai' || s == 'selesai';
    }).length;
  }

  int get _pendingOrdersCount {
    return _orders.where((o) {
      final s = o.status.toLowerCase();
      return s == 'pesanan dibuat' || s.contains('dibuat') || s == 'pending';
    }).length;
  }

  int get _cancelledOrdersCount {
    return _orders.where((o) {
      final s = o.status.toLowerCase();
      return s == 'dibatalkan' || s == 'batal';
    }).length;
  }

  List<Map<String, dynamic>> get _topProducts {
    final Map<String, int> qtyMap = {};
    final Map<String, int> revMap = {};

    for (final order in _orders) {
      final s = order.status.toLowerCase();
      if (s == 'dibatalkan' || s == 'batal') continue;

      for (final item in order.items) {
        qtyMap[item.productName] =
            (qtyMap[item.productName] ?? 0) + item.quantity;
        revMap[item.productName] =
            (revMap[item.productName] ?? 0) + item.subtotal;
      }
    }

    final list = qtyMap.entries.map((e) {
      return {'name': e.key, 'qty': e.value, 'revenue': revMap[e.key] ?? 0};
    }).toList();

    list.sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
    return list.take(5).toList();
  }

  List<double> get _last7DaysSales {
    final now = DateTime.now();
    final List<double> result = List.filled(7, 0.0);

    for (final order in _orders) {
      final s = order.status.toLowerCase();
      if (s != 'pesanan selesai' && s != 'selesai') continue;

      final diff = now.difference(order.createdAt).inDays;
      if (diff >= 0 && diff < 7) {
        final idx = 6 - diff;
        result[idx] += (order.total / 1000.0);
      }
    }
    return result;
  }

  Future<void> _logout() async {
    await _posService.supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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
            setState(() => _currentProfile = updated);
          },
        ),
      ),
    );
    final user = _posService.supabase.auth.currentUser;
    if (user != null) {
      final fresh = await _posService.fetchUserProfile(user.id);
      if (fresh != null && mounted) {
        setState(() => _currentProfile = fresh);
      }
    }
    _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);

    if (!widget.userProfile.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Akses Dibatasi')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 72,
                  color: AppColors.statusCancelled,
                ),
                const SizedBox(height: 16),
                Text(
                  'Akses Khusus Administrator',
                  style: AppFonts.display(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Akun Anda terdaftar sebagai ${widget.userProfile.role.toUpperCase()}. Anda tidak memiliki hak akses dashboard admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: widget.onOpenPos,
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Kembali ke Kasir POS'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final phone = Responsive.isPhone(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: phone ? kToolbarHeight : 68,
        titleSpacing: phone ? 8 : 16,
        title: InkWell(
          onTap: _openProfile,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: phone ? 16 : 18,
                  backgroundColor: AppColors.primary.withAlpha(40),
                  backgroundImage:
                      _currentProfile.avatarUrl != null &&
                          _currentProfile.avatarUrl!.isNotEmpty
                      ? NetworkImage(_currentProfile.avatarUrl!)
                      : null,
                  child:
                      _currentProfile.avatarUrl == null ||
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
                      Text(
                        widget.restaurantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.display(
                          fontWeight: FontWeight.w700,
                          fontSize: phone ? 14 : 16,
                        ),
                      ),
                      Text(
                        '${_currentProfile.role.toUpperCase()} • ${_currentProfile.fullName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: phone ? 10 : 12,
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
        ),
        actions: phone
            ? [
                IconButton(
                  tooltip: 'Kasir POS',
                  icon: const Icon(Icons.point_of_sale_rounded),
                  onPressed: widget.onOpenPos,
                ),
                PopupMenuButton<String>(
                  tooltip: 'Menu',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    if (v == 'profile') _openProfile();
                    if (v == 'logout') _logout();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_circle_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 10),
                          Text('Profil & Absensi'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 10),
                          Text('Keluar Akun'),
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onPressed: widget.onOpenPos,
                  icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                  label: const Text(
                    'Buka Kasir POS',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Profil',
                  icon: const Icon(Icons.account_circle_rounded),
                  onPressed: _openProfile,
                ),
                IconButton(
                  tooltip: 'Keluar Akun',
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                  ),
                  onPressed: _logout,
                ),
                const SizedBox(width: 8),
              ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark
              ? AppColors.darkMuted
              : AppColors.lightMuted,
          labelStyle: TextStyle(
            fontSize: phone ? 11 : 13,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: TextStyle(fontSize: phone ? 11 : 13),
          tabs: [
            Tab(
              icon: const Icon(Icons.insights_rounded),
              text: phone ? 'Ringkasan' : 'Ringkasan & Grafik',
            ),
            const Tab(icon: Icon(Icons.inventory_2_rounded), text: 'Produk'),
            const Tab(icon: Icon(Icons.badge_rounded), text: 'Karyawan'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAnalyticsTab(isDark),
                _buildProductsTab(isDark),
                _buildStaffTab(isDark),
              ],
            ),
    );
  }

  Widget _buildAnalyticsTab(bool isDark) {
    final last7 = _last7DaysSales;
    final maxVal = last7.reduce((a, b) => a > b ? a : b);
    final topProds = _topProducts;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          Responsive.pick(context, phone: 12.0, tablet: 20.0),
        ),
        child: MaxWidthBox(
          maxWidth: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width > 950
                      ? 4
                      : (width > 500 ? 2 : 1);

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 88,
                    children: [
                      _buildStatCard(
                        title: 'Total Penjualan Selesai',
                        value: _formatRupiah(_totalCompletedSales),
                        subtitle: 'Omset Transaksi Sukses',
                        icon: Icons.payments_rounded,
                        color: AppColors.statusCompleted,
                        isDark: isDark,
                      ),
                      _buildStatCard(
                        title: 'Pesanan Selesai',
                        value: '$_completedOrdersCount Transaksi',
                        subtitle: 'Lunas & Disajikan',
                        icon: Icons.task_alt_rounded,
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                      _buildStatCard(
                        title: 'Pesanan Dibuat / Aktif',
                        value: '$_pendingOrdersCount Pesanan',
                        subtitle: 'Sedang Diproses',
                        icon: Icons.pending_actions_rounded,
                        color: AppColors.statusPending,
                        isDark: isDark,
                      ),
                      _buildStatCard(
                        title: 'Pesanan Dibatalkan',
                        value: '$_cancelledOrdersCount Pesanan',
                        subtitle: 'Tidak Diproses',
                        icon: Icons.cancel_outlined,
                        color: AppColors.statusCancelled,
                        isDark: isDark,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrdersScreen(
                        restaurantName: widget.restaurantName,
                        isAdmin: true,
                      ),
                    ),
                  ).then((_) => _loadDashboardData());
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primaryTintDark
                        : AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withAlpha(110),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Pantau Pesanan Masuk & Meja',
                                  style: TextStyle(
                                    color: AppColors.text(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_pendingOrdersCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.yellowSoftDark
                                          : AppColors.yellowSoft,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: AppColors.amber.withAlpha(150),
                                      ),
                                    ),
                                    child: Text(
                                      '$_pendingOrdersCount menunggu dicek',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppColors.yellow
                                            : AppColors.yellowText,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Cek nomor meja pelanggan, verifikasi pembayaran, dan cetak nota.',
                              style: TextStyle(
                                color: AppColors.muted(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.primary,
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => TableQrDialog(
                      restaurantName: widget.restaurantName,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? AppColors.amber.withAlpha(90)
                          : AppColors.amber.withAlpha(140),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.yellowSoftDark
                              : AppColors.yellowSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.amber.withAlpha(130),
                          ),
                        ),
                        child: Icon(
                          Icons.qr_code_2_rounded,
                          color: isDark ? AppColors.yellow : AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QR Code Meja Pelanggan',
                              style: TextStyle(
                                color: AppColors.text(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Cetak stiker QR meja agar pelanggan pesan dari ponsel lalu sebut nomor meja ke kasir.',
                              style: TextStyle(
                                color: AppColors.muted(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: isDark ? AppColors.yellow : AppColors.primary,
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Grafik Penjualan 7 Hari',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Omset harian (dalam ribuan Rp)',
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.bar_chart_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Live',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: (maxVal <= 0 ? 50 : maxVal * 1.2),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                      final valRp = (rod.toY * 1000).toInt();
                                      return BarTooltipItem(
                                        _formatRupiah(valRp),
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      );
                                    },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 36,
                                  getTitlesWidget: (value, meta) {
                                    if (value == 0)
                                      return const Text(
                                        '0',
                                        style: TextStyle(fontSize: 9),
                                      );
                                    return Text(
                                      '${value.toInt()}k',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isDark
                                            ? AppColors.darkMuted
                                            : AppColors.lightMuted,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final days = [
                                      'H-6',
                                      'H-5',
                                      'H-4',
                                      'H-3',
                                      'H-2',
                                      'Kemarin',
                                      'Hari ini',
                                    ];
                                    final idx = value.toInt();
                                    if (idx >= 0 && idx < days.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6.0,
                                        ),
                                        child: Text(
                                          days[idx],
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: idx == 6
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: idx == 6
                                                ? AppColors.primary
                                                : (isDark
                                                      ? AppColors.darkMuted
                                                      : AppColors.lightMuted),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval:
                                  maxVal > 3.0 ? (maxVal / 3.0) : 25.0,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                                strokeWidth: 0.8,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            barGroups: List.generate(7, (i) {
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: last7[i],
                                    color: i == 6
                                        ? AppColors.primary
                                        : AppColors.amber,
                                    width: 14,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Produk Paling Terjual',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (topProds.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Belum ada transaksi item produk.',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkMuted
                                    : AppColors.lightMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        ...topProds.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: idx == 0
                                      ? AppColors.amber.withAlpha(40)
                                      : Colors.grey.withAlpha(30),
                                  child: Text(
                                    '${idx + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: idx == 0
                                          ? AppColors.yellowText
                                          : null,
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
                                        item['name'] as String,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Omset: ${_formatRupiah(item['revenue'] as int)}',
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
                                Text(
                                  '${item['qty']} terjual',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? AppColors.darkMuted
                          : AppColors.lightMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: AppFonts.display(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTab(bool isDark) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddProductScreen(onProductAdded: _loadDashboardData),
            ),
          ).then((_) => _loadDashboardData());
        },
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: AppColors.primary,
        child: MaxWidthBox(
          maxWidth: 960,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final p = _products[index];
              final inStock = p.stock > 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 48,
                          height: 48,
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.lightSurface,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: ProductImageView(
                              imageUrl: p.imageUrl,
                              fallbackIcon: p.iconData,
                              iconSize: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${p.category} · ${_formatRupiah(p.price)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? AppColors.darkMuted
                                    : AppColors.lightMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (p.description != null &&
                                p.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                p.description!.trim(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppColors.darkMuted.withAlpha(200)
                                      : AppColors.lightMuted.withAlpha(220),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (inStock
                                        ? AppColors.statusCompleted
                                        : AppColors.statusCancelled)
                                    .withAlpha(24),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Stok: ${p.stock}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: inStock
                                      ? AppColors.statusCompleted
                                      : AppColors.statusCancelled,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Ubah Data & Deskripsi',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddProductScreen(
                                    productToEdit: p,
                                    onProductAdded: _loadDashboardData,
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.inventory_2_outlined, size: 20),
                            tooltip: 'Ubah Stok Cepat',
                            onPressed: () => _showEditStockDialog(p),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: AppColors.statusCancelled,
                            ),
                            tooltip: 'Hapus Produk',
                            onPressed: () => _confirmDeleteProduct(p),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmDeleteProduct(DbProduct product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Produk?'),
        content: Text('Apakah Anda yakin ingin menghapus "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusCancelled,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _posService.deleteProduct(product.id);
                await _loadDashboardData();
              } catch (_) {}
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showEditStockDialog(DbProduct product) {
    final stockCtrl = TextEditingController(text: product.stock.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ubah Stok: ${product.name}'),
        content: TextField(
          controller: stockCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Jumlah Stok Baru'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newStock = int.tryParse(stockCtrl.text.trim());
              if (newStock != null && newStock >= 0) {
                Navigator.pop(ctx);
                await _posService.updateProductStock(product.id, newStock);
                _loadDashboardData();
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: AppColors.primary,
      child: MaxWidthBox(
        maxWidth: 860,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _staff.length,
          itemBuilder: (context, index) {
            final member = _staff[index];
            final isStaffAdmin = member.isAdmin;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isStaffAdmin
                      ? AppColors.primary
                      : AppColors.lightMuted,
                  backgroundImage:
                      member.avatarUrl != null && member.avatarUrl!.isNotEmpty
                      ? NetworkImage(member.avatarUrl!)
                      : null,
                  child: member.avatarUrl == null || member.avatarUrl!.isEmpty
                      ? Text(
                          member.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  member.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  member.email.isNotEmpty ? member.email : 'Tidak ada email',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isStaffAdmin
                                ? AppColors.primary
                                : AppColors.statusPending)
                            .withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    member.role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isStaffAdmin
                          ? AppColors.primary
                          : AppColors.statusPending,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
