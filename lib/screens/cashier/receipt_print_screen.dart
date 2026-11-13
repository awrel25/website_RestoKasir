import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/core/utils/responsive.dart';

class ReceiptPrintScreen extends StatelessWidget {
  final DbOrder order;
  final String restaurantName;
  final int cashAmount;

  const ReceiptPrintScreen({
    super.key,
    required this.order,
    required this.restaurantName,
    this.cashAmount = 0,
  });

  String _formatRupiah(int value) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }

  Future<Uint8List> _generatePdfReceipt(PdfPageFormat format) async {
    final pdf = pw.Document();

    // Standard receipt roll width (typically 58mm or 80mm)
    final receiptFormat = PdfPageFormat.roll80;

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');
    final formattedDate = dateFormat.format(order.createdAt);

    final int changeAmount = (cashAmount > order.total) ? cashAmount - order.total : 0;

    pdf.addPage(
      pw.Page(
        pageFormat: receiptFormat,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Header
                pw.Text(
                  restaurantName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Struk Resmi Pembayaran Restoran',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),

                // Order Meta
                pw.SizedBox(height: 4),
                _buildPdfMetaRow('No. Nota', order.invoiceNo),
                _buildPdfMetaRow('Waktu', formattedDate),
                _buildPdfMetaRow('Kasir', order.cashierName),
                _buildPdfMetaRow('Meja', 'Meja ${order.tableNumber}'),
                _buildPdfMetaRow('Status', order.status.toUpperCase()),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 4),

                // Items Table
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Menu', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Total', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 4),
                ...order.items.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          item.productName,
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '${item.quantity} x ${_formatRupiah(item.price)}',
                              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                            ),
                            pw.Text(
                              _formatRupiah(item.subtotal),
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 4),

                // Payment Summary
                _buildPdfSummaryRow('Subtotal', _formatRupiah(order.subtotal)),
                _buildPdfSummaryRow('Biaya Layanan (5%)', _formatRupiah(order.serviceFee)),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      _formatRupiah(order.total),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 4),

                _buildPdfSummaryRow('Metode Bayar', order.paymentMethod),
                if (cashAmount > 0) ...[
                  _buildPdfSummaryRow('Tunai Diterima', _formatRupiah(cashAmount)),
                  _buildPdfSummaryRow('Kembali', _formatRupiah(changeAmount)),
                ],

                pw.SizedBox(height: 10),
                pw.BarcodeWidget(
                  data: order.invoiceNo,
                  barcode: pw.Barcode.code128(),
                  width: 140,
                  height: 35,
                  drawText: false,
                ),
                pw.SizedBox(height: 4),
                pw.Text(order.invoiceNo, style: const pw.TextStyle(fontSize: 8)),

                pw.SizedBox(height: 10),
                pw.Text(
                  'Terima Kasih Atas Kunjungan Anda!',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Simpan struk ini sebagai bukti pembayaran.',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
          pw.Text(value, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDark(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cetak Struk Nota',
          style: AppFonts.display(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Cetak Langsung ke Printer',
            icon: const Icon(Icons.print_rounded),
            onPressed: () async {
              await Printing.layoutPdf(
                onLayout: (format) => _generatePdfReceipt(format),
                name: 'Nota_${order.invoiceNo}.pdf',
              );
            },
          ),
          IconButton(
            tooltip: 'Bagikan PDF',
            icon: const Icon(Icons.share_rounded),
            onPressed: () async {
              final pdfBytes = await _generatePdfReceipt(PdfPageFormat.roll80);
              await Printing.sharePdf(
                bytes: pdfBytes,
                filename: 'Nota_${order.invoiceNo}.pdf',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: isDark ? AppColors.darkCard : AppColors.lightBorder.withAlpha(80),
              child: MaxWidthBox(
                maxWidth: 800,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: LayoutBuilder(
                  builder: (context, bc) {
                    final isNarrow = bc.maxWidth < 460;
                    final printBtn = ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Cetak Nota'),
                      onPressed: () async {
                        await Printing.layoutPdf(
                          onLayout: (format) => _generatePdfReceipt(format),
                          name: 'Nota_${order.invoiceNo}.pdf',
                        );
                      },
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(35),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.print_outlined, color: AppColors.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Koneksikan Printer POS',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark ? AppColors.darkText : AppColors.lightText,
                                      ),
                                    ),
                                    Text(
                                      'Bluetooth, USB POS, WiFi Thermal',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          printBtn,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.print_outlined, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Koneksikan Printer POS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isDark ? AppColors.darkText : AppColors.lightText,
                                ),
                              ),
                              Text(
                                'Mendukung Printer Thermal Bluetooth, USB POS, WiFi, & Cetak Sistem.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        printBtn,
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: MaxWidthBox(
                maxWidth: 600,
                child: PdfPreview(
                  build: (format) => _generatePdfReceipt(format),
                  useActions: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  pdfFileName: 'Nota_${order.invoiceNo}.pdf',
                  previewPageMargin: const EdgeInsets.all(16),
                  loadingWidget: const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
