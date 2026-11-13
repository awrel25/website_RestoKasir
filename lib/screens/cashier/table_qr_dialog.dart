import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:my_app/services/pos_service.dart';
import 'package:my_app/core/theme/theme_controller.dart';

class TableQrDialog extends StatefulWidget {
  final String restaurantName;
  final int initialTable;

  const TableQrDialog({
    super.key,
    required this.restaurantName,
    this.initialTable = 1,
  });

  static String buildTableMenuUrl(int tableNumber, {String? restoId}) {
    const baseUrl = 'https://awrel25.github.io/website_RestoKasir/';
    final paddedTable = tableNumber.toString().padLeft(2, '0');
    final restoParam = restoId != null && restoId.isNotEmpty
        ? '&resto=${Uri.encodeComponent(restoId)}'
        : '';
    return '$baseUrl?table=$paddedTable$restoParam';
  }

  @override
  State<TableQrDialog> createState() => _TableQrDialogState();
}

class _TableQrDialogState extends State<TableQrDialog> {
  final PosService _posService = PosService();
  late int _selectedTable;
  String? _restoId;

  @override
  void initState() {
    super.initState();
    _selectedTable = widget.initialTable;
    _fetchRestoId();
  }

  Future<void> _fetchRestoId() async {
    final rid = await _posService.fetchRestaurantId();
    if (mounted) {
      setState(() {
        _restoId = rid;
      });
    }
  }

  String get _tableMenuUrl =>
      TableQrDialog.buildTableMenuUrl(_selectedTable, restoId: _restoId);

  Future<void> _printTableSticker() async {
    try {
      await Printing.layoutPdf(
        name: 'Stiker_QR_Meja_$_selectedTable',
        onLayout: (PdfPageFormat format) async {
          final doc = pw.Document();
          const stickerFormat = PdfPageFormat.roll80;

          doc.addPage(
            pw.Page(
              pageFormat: stickerFormat,
              margin: const pw.EdgeInsets.all(16),
              build: (pw.Context context) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      widget.restaurantName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 1.5),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(6)),
                      ),
                      child: pw.Text(
                        'MEJA $_selectedTable',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.BarcodeWidget(
                      data: _tableMenuUrl,
                      barcode: pw.Barcode.qrCode(),
                      width: 160,
                      height: 160,
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'SCAN UNTUK PESAN DARI MEJA',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Scan QR dengan kamera ponsel untuk membuka menu. Setelah memesan, sebutkan Nomor Meja $_selectedTable ke kasir untuk dicek di aplikasi kasir.',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey700,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 8),
                    pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
                    pw.Text(
                      'RestoKasir Digital Self-Ordering',
                      style: const pw.TextStyle(
                          fontSize: 7.5, color: PdfColors.grey600),
                    ),
                  ],
                );
              },
            ),
          );

          return doc.save();
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mencetak stiker QR meja: $e'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    color: AppColors.primary,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code_2_rounded,
                                  color: Colors.white, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'QR Code Meja Pelanggan',
                                      style: AppFonts.display(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Text(
                                      'Scan untuk memesan menu dari meja',
                                      style: TextStyle(
                                        color: Colors.white70,
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
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Pilihan Nomor Meja
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pilih Nomor Meja:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.yellowSoftDark
                                    : AppColors.yellowSoft,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.amber.withAlpha(140)),
                              ),
                              child: Text(
                                'Meja $_selectedTable',
                                style: AppFonts.display(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppColors.yellow
                                      : AppColors.yellowText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Tombol Meja 1 s/d 15
                        SizedBox(
                          height: 38,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: 20,
                            itemBuilder: (context, index) {
                              final tableNum = index + 1;
                              final isSelected = _selectedTable == tableNum;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text('$tableNum'),
                                  selected: isSelected,
                                  showCheckmark: false,
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkText
                                            : AppColors.lightText),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedTable = tableNum;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Kartu Tampilan QR Code Meja
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: Colors.grey.shade300, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                widget.restaurantName.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'MEJA $_selectedTable',
                                  style: AppFonts.display(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Widget QR Code
                              SizedBox(
                                width: 190,
                                height: 190,
                                child: QrImageView(
                                  data: _tableMenuUrl,
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
                              const SizedBox(height: 8),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.yellowSoft,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.amber.withAlpha(120)),
                                ),
                                child: Text(
                                  'Scan QR untuk memesan. Setelah mengirim pesanan, sebutkan Nomor Meja $_selectedTable ke kasir untuk dicek.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.yellowText,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _tableMenuUrl,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.lightMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Action Buttons: Cetak Stiker Meja & Salin Link
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _printTableSticker,
                            icon: const Icon(Icons.print_rounded, size: 20),
                            label: Text(
                              'Cetak Stiker QR Meja $_selectedTable',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _tableMenuUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'URL Menu Meja $_selectedTable disalin ke clipboard!'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text(
                              'Salin URL Meja untuk Dibagikan',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

