import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/core/utils/responsive.dart';

enum PaperRollSize { mm58, mm80 }

class ReceiptPrintScreen extends StatefulWidget {
  final DbOrder order;
  final String restaurantName;
  final int cashAmount;

  const ReceiptPrintScreen({
    super.key,
    required this.order,
    required this.restaurantName,
    this.cashAmount = 0,
  });

  @override
  State<ReceiptPrintScreen> createState() => _ReceiptPrintScreenState();
}

class _ReceiptPrintScreenState extends State<ReceiptPrintScreen> {
  static const roll58 = PdfPageFormat(
    58 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 3 * PdfPageFormat.mm,
  );
  static const roll80 = PdfPageFormat.roll80;

  PaperRollSize _selectedPaper = PaperRollSize.mm80;

  String _formatRupiah(int value) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }

  PdfPageFormat get _currentPageFormat {
    return _selectedPaper == PaperRollSize.mm58 ? roll58 : roll80;
  }

  pw.Widget _buildPdfDashedDivider() {
    return pw.Divider(
      thickness: 0.8,
      borderStyle: pw.BorderStyle.dashed,
      color: PdfColors.grey700,
    );
  }

  pw.Widget _buildPdfMetaRow(String label, String value, bool is58mm) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: is58mm ? 7.5 : 8.5,
              color: PdfColors.grey800,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: is58mm ? 7.5 : 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryRow(String label, String value, bool is58mm) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: is58mm ? 8.0 : 9.0,
              color: PdfColors.grey900,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: is58mm ? 8.0 : 9.0,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _generatePdfReceipt(PdfPageFormat format) async {
    final pdf = pw.Document();

    final bool is58mm =
        (format.availableWidth <= 220) || (_selectedPaper == PaperRollSize.mm58);
    final targetPageFormat = is58mm ? roll58 : roll80;

    final dateOnlyFormat = DateFormat('dd/MM/yyyy', 'id_ID');
    final timeOnlyFormat = DateFormat('HH:mm WIB', 'id_ID');
    final fullDateFormat = DateFormat('dd/MM/yyyy HH:mm', 'id_ID');

    final formattedFullDate = fullDateFormat.format(widget.order.createdAt);
    final formattedDate = dateOnlyFormat.format(widget.order.createdAt);
    final formattedTime = timeOnlyFormat.format(widget.order.createdAt);

    final int changeAmount = (widget.cashAmount > widget.order.total)
        ? widget.cashAmount - widget.order.total
        : 0;

    pdf.addPage(
      pw.Page(
        pageFormat: targetPageFormat,
        build: (pw.Context context) {
          return pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: is58mm ? 6 : 14,
              vertical: is58mm ? 10 : 16,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // -------------------------------------------------------------
                // 1. HEADER RESTORAN
                // -------------------------------------------------------------
                pw.Text(
                  widget.restaurantName.trim().toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: is58mm ? 13 : 16,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'STRUK PEMBAYARAN RESMI',
                  style: pw.TextStyle(
                    fontSize: is58mm ? 7.5 : 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  formattedFullDate,
                  style: pw.TextStyle(
                    fontSize: is58mm ? 7.0 : 8.0,
                    color: PdfColors.grey700,
                  ),
                  textAlign: pw.TextAlign.center,
                ),

                pw.SizedBox(height: 8),
                _buildPdfDashedDivider(),
                pw.SizedBox(height: 6),

                // -------------------------------------------------------------
                // 2. INFORMASI TRANSAKSI
                // -------------------------------------------------------------
                _buildPdfMetaRow('No. Nota', widget.order.invoiceNo, is58mm),
                _buildPdfMetaRow('Tanggal', formattedDate, is58mm),
                _buildPdfMetaRow('Waktu', formattedTime, is58mm),
                _buildPdfMetaRow(
                  'Kasir',
                  widget.order.cashierName.isNotEmpty
                      ? widget.order.cashierName
                      : 'Kasir',
                  is58mm,
                ),
                _buildPdfMetaRow('Meja', 'Meja ${widget.order.tableNumber}', is58mm),
                _buildPdfMetaRow('Metode', widget.order.paymentMethod, is58mm),
                _buildPdfMetaRow(
                  'Status',
                  widget.order.isPaid ? 'LUNAS' : widget.order.status.toUpperCase(),
                  is58mm,
                ),

                pw.SizedBox(height: 6),
                _buildPdfDashedDivider(),
                pw.SizedBox(height: 6),

                // -------------------------------------------------------------
                // 3. DETAIL PESANAN
                // -------------------------------------------------------------
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'MENU / ITEM',
                      style: pw.TextStyle(
                        fontSize: is58mm ? 8.0 : 9.0,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'SUBTOTAL',
                      style: pw.TextStyle(
                        fontSize: is58mm ? 8.0 : 9.0,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, color: PdfColors.grey500),
                pw.SizedBox(height: 2),

                ...widget.order.items.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              child: pw.Text(
                                item.productName,
                                style: pw.TextStyle(
                                  fontSize: is58mm ? 8.5 : 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                softWrap: true,
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Text(
                              _formatRupiah(item.subtotal),
                              style: pw.TextStyle(
                                fontSize: is58mm ? 8.5 : 9.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${item.quantity} x ${_formatRupiah(item.price)}',
                          style: pw.TextStyle(
                            fontSize: is58mm ? 7.5 : 8.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                _buildPdfDashedDivider(),
                pw.SizedBox(height: 6),

                // -------------------------------------------------------------
                // 4. RINGKASAN PEMBAYARAN
                // -------------------------------------------------------------
                _buildPdfSummaryRow(
                  'Subtotal',
                  _formatRupiah(widget.order.subtotal),
                  is58mm,
                ),
                if (widget.order.serviceFee > 0)
                  _buildPdfSummaryRow(
                    'Biaya Layanan (5%)',
                    _formatRupiah(widget.order.serviceFee),
                    is58mm,
                  ),

                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1.2, color: PdfColors.black),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL',
                      style: pw.TextStyle(
                        fontSize: is58mm ? 12 : 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _formatRupiah(widget.order.total),
                      style: pw.TextStyle(
                        fontSize: is58mm ? 12 : 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Divider(thickness: 1.2, color: PdfColors.black),
                pw.SizedBox(height: 6),

                _buildPdfSummaryRow(
                  'Metode Bayar',
                  widget.order.paymentMethod,
                  is58mm,
                ),
                if (widget.cashAmount > 0) ...[
                  _buildPdfSummaryRow(
                    'Tunai Diterima',
                    _formatRupiah(widget.cashAmount),
                    is58mm,
                  ),
                  _buildPdfSummaryRow(
                    'Kembali',
                    _formatRupiah(changeAmount),
                    is58mm,
                  ),
                ],

                // -------------------------------------------------------------
                // 5. BARCODE & FOOTER ELEGAN
                // -------------------------------------------------------------
                pw.SizedBox(height: 12),
                pw.BarcodeWidget(
                  data: widget.order.invoiceNo,
                  barcode: pw.Barcode.code128(),
                  width: is58mm ? 120 : 150,
                  height: is58mm ? 26 : 32,
                  drawText: false,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  widget.order.invoiceNo,
                  style: pw.TextStyle(
                    fontSize: is58mm ? 7.5 : 8.5,
                    letterSpacing: 1.0,
                  ),
                ),

                pw.SizedBox(height: 14),
                pw.Text(
                  'TERIMA KASIH ATAS KUNJUNGAN ANDA',
                  style: pw.TextStyle(
                    fontSize: is58mm ? 8.0 : 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Selamat Menikmati Hidangan Anda!',
                  style: pw.TextStyle(
                    fontSize: is58mm ? 7.0 : 8.5,
                    color: PdfColors.grey800,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Struk ini merupakan bukti transaksi pembayaran yang sah.',
                  style: pw.TextStyle(
                    fontSize: is58mm ? 6.5 : 7.5,
                    color: PdfColors.grey700,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
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
                onLayout: (format) => _generatePdfReceipt(_currentPageFormat),
                name: 'Nota_${widget.order.invoiceNo}.pdf',
              );
            },
          ),
          IconButton(
            tooltip: 'Bagikan PDF',
            icon: const Icon(Icons.share_rounded),
            onPressed: () async {
              final pdfBytes = await _generatePdfReceipt(_currentPageFormat);
              await Printing.sharePdf(
                bytes: pdfBytes,
                filename: 'Nota_${widget.order.invoiceNo}.pdf',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Toolbar: Paper size toggle & print button
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
              ),
              child: MaxWidthBox(
                maxWidth: 800,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: LayoutBuilder(
                  builder: (context, bc) {
                    final isNarrow = bc.maxWidth < 560;

                    final paperSelector = SegmentedButton<PaperRollSize>(
                      segments: const [
                        ButtonSegment(
                          value: PaperRollSize.mm80,
                          label: Text('80mm (Standar POS)', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.receipt_long_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: PaperRollSize.mm58,
                          label: Text('58mm (Mini POS)', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.receipt_rounded, size: 16),
                        ),
                      ],
                      selected: {_selectedPaper},
                      onSelectionChanged: (Set<PaperRollSize> selection) {
                        setState(() {
                          _selectedPaper = selection.first;
                        });
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );

                    final printBtn = ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text(
                        'Cetak Struk',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        await Printing.layoutPdf(
                          onLayout: (format) => _generatePdfReceipt(_currentPageFormat),
                          name: 'Nota_${widget.order.invoiceNo}.pdf',
                        );
                      },
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: paperSelector),
                          const SizedBox(height: 10),
                          printBtn,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: paperSelector),
                        const SizedBox(width: 14),
                        printBtn,
                      ],
                    );
                  },
                ),
              ),
            ),

            // Live PDF Preview with Selected Paper Format
            Expanded(
              child: MaxWidthBox(
                maxWidth: 580,
                child: PdfPreview(
                  key: ValueKey(_selectedPaper),
                  build: (format) => _generatePdfReceipt(_currentPageFormat),
                  useActions: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  pdfFileName: 'Nota_${widget.order.invoiceNo}.pdf',
                  previewPageMargin: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
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
