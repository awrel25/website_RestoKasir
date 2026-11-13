import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/screens/cashier/receipt_print_screen.dart';
import 'package:my_app/core/theme/theme_controller.dart';

class QrisPaymentDialog extends StatefulWidget {
  final String restaurantName;
  final int totalAmount;
  final String invoiceNo;
  final int tableNumber;
  final String cashierName;
  final String paymentMethod; // 'QRIS' or 'Transfer Bank' / 'Virtual Account'
  final List<CartItem>? cartItems; // If from cashier
  final DbOrder? existingOrder; // If paying an existing pending order

  const QrisPaymentDialog({
    super.key,
    required this.restaurantName,
    required this.totalAmount,
    required this.invoiceNo,
    required this.tableNumber,
    required this.cashierName,
    this.paymentMethod = 'QRIS',
    this.cartItems,
    this.existingOrder,
  });

  static String buildQrisPaymentUrl({
    required String invoiceNo,
    required int totalAmount,
    required String restaurantName,
    String? orderId,
    required String referenceId,
    int? tableNumber,
  }) {
    const baseUrl = 'https://awrel25.github.io/website_RestoKasir/pay.html';
    final tableParam = tableNumber != null ? '&table=$tableNumber' : '';
    return '$baseUrl?inv=${Uri.encodeComponent(invoiceNo)}&amt=$totalAmount&resto=${Uri.encodeComponent(restaurantName)}&id=${orderId ?? ''}&ref=$referenceId$tableParam';
  }

  @override
  State<QrisPaymentDialog> createState() => _QrisPaymentDialogState();
}

class _QrisPaymentDialogState extends State<QrisPaymentDialog>
    with SingleTickerProviderStateMixin {
  final PosService _posService = PosService();
  String? _orderId;
  late String _nmid;
  late String _referenceId;
  late String _vaNumber;
  late String _selectedBank;

  bool _isPaid = false;
  bool _isProcessing = false;
  DbOrder? _completedOrder;

  Timer? _countdownTimer;
  int _secondsLeft = 300; // 5 menit
  Timer? _pollingTimer;

  final List<String> _banks = ['BCA', 'Mandiri', 'BRI', 'BNI'];

  String get _qrisCameraUrl => QrisPaymentDialog.buildQrisPaymentUrl(
        invoiceNo: widget.invoiceNo,
        totalAmount: widget.totalAmount,
        restaurantName: widget.restaurantName,
        orderId: _orderId,
        referenceId: _referenceId,
        tableNumber: widget.tableNumber,
      );

  @override
  void initState() {
    super.initState();
    _selectedBank = 'BCA';
    _generateRandomPaymentCredentials();
    _startCountdown();
    _initOrderAndListener();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _generateRandomPaymentCredentials() {
    final random = Random();
    final randomDigits = List.generate(12, (_) => random.nextInt(10)).join();
    final nmidDigits = List.generate(10, (_) => random.nextInt(10)).join();
    _nmid = 'ID$nmidDigits';
    _referenceId =
        'QRIS-${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(9000) + 1000}';

    // Generate nomor Virtual Account acak
    final bankCode = _selectedBank == 'BCA'
        ? '8808'
        : _selectedBank == 'Mandiri'
            ? '8950'
            : _selectedBank == 'BRI'
                ? '8888'
                : '8277';
    _vaNumber = '$bankCode $randomDigits';
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initOrderAndListener() async {
    if (widget.existingOrder != null) {
      _orderId = widget.existingOrder!.id;
      _completedOrder = widget.existingOrder;
    } else if (widget.cartItems != null) {
      try {
        final subtotal = widget.cartItems!.fold(0, (sum, i) => sum + i.total);
        final serviceFee = (subtotal * 0.05).round();
        final grandTotal = subtotal + serviceFee;

        final newOrder = await _posService.createOrder(
          invoiceNo: widget.invoiceNo,
          cashierName: widget.cashierName,
          tableNumber: widget.tableNumber,
          subtotal: subtotal,
          serviceFee: serviceFee,
          total: grandTotal,
          paymentMethod: widget.paymentMethod == 'QRIS'
              ? 'QRIS'
              : 'Transfer Bank ($_selectedBank)',
          status: 'pesanan dibuat',
          cartItems: widget.cartItems!,
        );

        if (mounted) {
          setState(() {
            _orderId = newOrder.id;
            _completedOrder = newOrder;
          });
        }
      } catch (e) {
        debugPrint('Catatan inisialisasi order QRIS: $e');
      }
    }

    // Polling Supabase setiap 1.5 detik untuk mendeteksi saat kamera user scan link
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (!mounted || _isPaid) {
        timer.cancel();
        return;
      }

      if (_orderId != null && _orderId!.isNotEmpty) {
        final status = await _posService.fetchOrderStatus(_orderId!);
        if (status == 'pesanan selesai' || status == 'selesai') {
          timer.cancel();
          _onPaymentSuccessReceived();
        }
      }
    });
  }

  String _formatRupiah(int val) {
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(val);
  }

  String get _timerFormatted {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _onPaymentSuccessReceived() async {
    if (_isPaid || _isProcessing) return;
    setState(() {
      _isProcessing = true;
      _pollingTimer?.cancel();
    });

    try {
      if (_orderId != null) {
        await _posService.updateOrderStatus(_orderId!, 'pesanan selesai');
        final updated = await _posService.fetchOrderById(_orderId!);
        if (updated != null) {
          _completedOrder = updated;
        }
      } else if (widget.existingOrder != null) {
        await _posService.updateOrderStatus(
            widget.existingOrder!.id, 'pesanan selesai');
        final updated =
            await _posService.fetchOrderById(widget.existingOrder!.id);
        if (updated != null) {
          _completedOrder = updated;
        }
      }

      if (!mounted) return;
      setState(() {
        _isPaid = true;
        _isProcessing = false;
      });

      // Otomatis membuka jendela cetak struk agar transaksi langsung selesai
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _isPaid) {
          Navigator.pop(context, true);
          _printReceipt();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memverifikasi pembayaran: $e'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
    }
  }

  Future<void> _saveAsPendingUnpaid() async {
    _pollingTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context, false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Pesanan ${widget.invoiceNo} tersimpan sebagai BELUM SELESAI (Menunggu Pembayaran).'),
        backgroundColor: AppColors.statusPending,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _printReceipt() {
    if (_completedOrder != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPrintScreen(
            order: _completedOrder!,
            restaurantName: widget.restaurantName,
            cashAmount: widget.totalAmount,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);
    final isQris = widget.paymentMethod == 'QRIS';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              child: _isPaid
                  ? _buildPaidSuccessView(isDark)
                  : _buildPaymentWaitingView(isDark, isQris),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // VIEW: WAITING FOR PAYMENT (MENUNGGU PEMBAYARAN)
  // =========================================================================
  Widget _buildPaymentWaitingView(bool isDark, bool isQris) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: AppColors.primary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isQris
                          ? Icons.qr_code_scanner_rounded
                          : Icons.account_balance_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isQris
                                ? 'Pembayaran QRIS'
                                : 'Transfer Bank dan Virtual Account',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            isQris
                                ? 'Scan QR dengan kamera ponsel atau aplikasi pembayaran'
                                : 'Pilih bank tujuan transfer pelanggan',
                            style: TextStyle(
                              color: Colors.white.withAlpha(220),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: _saveAsPendingUnpaid,
                tooltip: 'Simpan Belum Bayar & Tutup',
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Meta info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.invoiceNo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Meja ${widget.tableNumber} • Kasir: ${widget.cashierName}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.statusPending.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.statusPending.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 14, color: AppColors.statusPending),
                        const SizedBox(width: 4),
                        Text(
                          _timerFormatted,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.statusPending,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Total Amount Display
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.lightBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL BAYAR:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkMuted
                            : AppColors.lightMuted,
                      ),
                    ),
                    Text(
                      _formatRupiah(widget.totalAmount),
                      style: AppFonts.display(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (isQris) ...[
                // QRIS Card Container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // QRIS Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'QRIS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.yellowSoft,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppColors.amber.withAlpha(120)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.camera_alt_rounded,
                                    size: 13, color: AppColors.yellowText),
                                SizedBox(width: 4),
                                Text(
                                  'Scan kamera aktif',
                                  style: TextStyle(
                                    color: AppColors.yellowText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.restaurantName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'NMID: $_nmid • Ref: $_referenceId',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),

                      // DYNAMIC CAMERA SCANNABLE QR CODE
                      SizedBox(
                        width: 210,
                        height: 210,
                        child: QrImageView(
                          data: _qrisCameraUrl,
                          version: QrVersions.auto,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Supported Apps / Camera info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          'Arahkan kamera ponsel ke QR untuk membayar. Transaksi langsung diproses setelah selesai.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Button: Salin Link QRIS
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _qrisCameraUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Link pembayaran QRIS berhasil disalin ke clipboard!'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Salin Link QRIS',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // VIRTUAL ACCOUNT CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pilih Bank Tujuan Pelanggan:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: _banks.map((b) {
                          final sel = _selectedBank == b;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: ChoiceChip(
                                label: Text(b),
                                selected: sel,
                                showCheckmark: false,
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : (isDark
                                          ? AppColors.darkText
                                          : AppColors.lightText),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    _selectedBank = b;
                                    _generateRandomPaymentCredentials();
                                  });
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nomor Virtual Account $_selectedBank:',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _vaNumber,
                              style: AppFonts.display(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text: _vaNumber.replaceAll(' ', '')));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Nomor Virtual Account disalin!'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Atas Nama:',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.lightMuted,
                            ),
                          ),
                          Text(
                            widget.restaurantName,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Simulation Banner with Live Polling Status
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.statusCompleted.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.statusCompleted.withAlpha(70)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.statusCompleted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isQris
                                ? 'Menunggu scan kamera pelanggan...'
                                : 'Menunggu pelanggan transfer...',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.statusCompleted,
                            ),
                          ),
                          Text(
                            isQris
                                ? 'Struk akan disiapkan begitu scan selesai.'
                                : 'Periksa mutasi lalu tekan tombol konfirmasi di bawah.',
                            style: TextStyle(
                              fontSize: 10.5,
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

              const SizedBox(height: 16),

              // Action Buttons
              if (_isProcessing)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusCompleted,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _onPaymentSuccessReceived,
                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                      label: Text(
                        isQris
                            ? 'Simulasikan Scan Kamera (Selesai & Struk)'
                            : 'Konfirmasi Transfer Masuk (Selesai & Struk)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusPending,
                        side: const BorderSide(color: AppColors.statusPending),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveAsPendingUnpaid,
                      child: const Text(
                        'Simpan Belum Bayar (Pesanan Tetap Disimpan)',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // VIEW: PAYMENT SUCCESS (AUTO SELESAI + CETAK NOTA)
  // =========================================================================
  Widget _buildPaidSuccessView(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.statusCompleted.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.statusCompleted,
              size: 56,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pembayaran Berhasil Diterima!',
            style: AppFonts.display(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Pesanan ${widget.invoiceNo} telah otomatis LUNAS. Menyiapkan struk...',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: [
                _buildSuccessRow(
                  'Metode Pembayaran',
                  widget.paymentMethod == 'QRIS'
                      ? 'QRIS Kamera Biasa'
                      : 'Transfer Bank $_selectedBank',
                ),
                _buildSuccessRow(
                    'Total Dibayar', _formatRupiah(widget.totalAmount)),
                _buildSuccessRow('Status Pesanan', 'PESANAN SELESAI (LUNAS)',
                    isHighlight: true),
                _buildSuccessRow('Waktu Bayar',
                    DateFormat('HH:mm:ss WIB').format(DateTime.now())),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // CETAK NOTA BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context, true); // true = paid
                _printReceipt();
              },
              icon: const Icon(Icons.print_rounded, size: 20),
              label: const Text(
                'Cetak Struk Nota Pembayaran',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Selesai & Tutup', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessRow(String label, String value,
      {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isHighlight ? AppColors.statusCompleted : null,
            ),
          ),
        ],
      ),
    );
  }
}
