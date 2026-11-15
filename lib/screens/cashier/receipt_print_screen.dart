import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:my_app/models/models.dart';
import 'package:my_app/core/theme/theme_controller.dart';
import 'package:my_app/core/utils/responsive.dart';

enum PaperRollSize { mm80, wide, mm58 }

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
  // Format roll lebar maksimal dengan margin minimal agar teks struk membentang luas
  static const roll80 = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginLeft: 2 * PdfPageFormat.mm,
    marginRight: 2 * PdfPageFormat.mm,
    marginTop: 4 * PdfPageFormat.mm,
    marginBottom: 6 * PdfPageFormat.mm,
  );

  static const rollWide = PdfPageFormat(
    100 * PdfPageFormat.mm,
    double.infinity,
    marginLeft: 3 * PdfPageFormat.mm,
    marginRight: 3 * PdfPageFormat.mm,
    marginTop: 4 * PdfPageFormat.mm,
    marginBottom: 6 * PdfPageFormat.mm,
  );

  static const roll58 = PdfPageFormat(
    58 * PdfPageFormat.mm,
    double.infinity,
    marginLeft: 1.5 * PdfPageFormat.mm,
    marginRight: 1.5 * PdfPageFormat.mm,
    marginTop: 3 * PdfPageFormat.mm,
    marginBottom: 5 * PdfPageFormat.mm,
  );

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
    switch (_selectedPaper) {
      case PaperRollSize.wide:
        return rollWide;
      case PaperRollSize.mm58:
        return roll58;
      case PaperRollSize.mm80:
        return roll80;
    }
  }

  pw.Widget _buildPdfDashedDivider() {
    return pw.Divider(
      thickness: 0.8,
      borderStyle: pw.BorderStyle.dashed,
      color: PdfColors.grey700,
    );
  }

  pw.Widget _buildPdfMetaRow(String label, String value, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              color: PdfColors.grey800,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryRow(String label, String value, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              color: PdfColors.grey900,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _generatePdfReceipt(PdfPageFormat format) async {
    final pdf = pw.Document();

    final targetPageFormat = _currentPageFormat;
    final double availWidth = targetPageFormat.availableWidth;

    final bool is58mm = (_selectedPaper == PaperRollSize.mm58) || (availWidth <= 190);
    final bool isWide = (_selectedPaper == PaperRollSize.wide) || (availWidth >= 260);

    // Tipografi dinamis agar struk memanfaatkan seluruh lebar kertas secara maksimal
    final double titleSize = isWide ? 18.0 : (is58mm ? 13.0 : 16.0);
    final double subtitleSize = isWide ? 10.0 : (is58mm ? 7.5 : 8.5);
    final double dateSize = isWide ? 9.5 : (is58mm ? 7.0 : 8.0);
    final double metaSize = isWide ? 9.5 : (is58mm ? 7.5 : 8.5);
    final double itemTitleSize = isWide ? 10.5 : (is58mm ? 8.5 : 9.5);
    final double itemSubSize = isWide ? 9.0 : (is58mm ? 7.5 : 8.5);
    final double totalSize = isWide ? 16.0 : (is58mm ? 12.0 : 14.5);
    final double footerSize = isWide ? 10.0 : (is58mm ? 8.0 : 9.0);
    final double barcodeWidth = isWide ? 180.0 : (is58mm ? 120.0 : 150.0);

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
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: isWide ? 6 : (is58mm ? 2 : 4),
              vertical: 8,
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
                    fontSize: titleSize,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'STRUK PEMBAYARAN RESMI',
                  style: pw.TextStyle(
                    fontSize: subtitleSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  formattedFullDate,
                  style: pw.TextStyle(
                    fontSize: dateSize,
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
                _buildPdfMetaRow('No. Nota', widget.order.invoiceNo, metaSize),
                _buildPdfMetaRow('Tanggal', formattedDate, metaSize),
                _buildPdfMetaRow('Waktu', formattedTime, metaSize),
                _buildPdfMetaRow(
                  'Kasir',
                  widget.order.cashierName.isNotEmpty
                      ? widget.order.cashierName
                      : 'Kasir',
                  metaSize,
                ),
                _buildPdfMetaRow('Meja', 'Meja ${widget.order.tableNumber}', metaSize),
                _buildPdfMetaRow('Metode', widget.order.paymentMethod, metaSize),
                _buildPdfMetaRow(
                  'Status',
                  widget.order.isPaid ? 'LUNAS' : widget.order.status.toUpperCase(),
                  metaSize,
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
                        fontSize: metaSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'SUBTOTAL',
                      style: pw.TextStyle(
                        fontSize: metaSize,
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
                              flex: 3,
                              child: pw.Text(
                                item.productName,
                                style: pw.TextStyle(
                                  fontSize: itemTitleSize,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                softWrap: true,
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Text(
                              _formatRupiah(item.subtotal),
                              style: pw.TextStyle(
                                fontSize: itemTitleSize,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${item.quantity} x ${_formatRupiah(item.price)}',
                          style: pw.TextStyle(
                            fontSize: itemSubSize,
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
                  metaSize,
                ),
                if (widget.order.serviceFee > 0)
                  _buildPdfSummaryRow(
                    'Biaya Layanan (5%)',
                    _formatRupiah(widget.order.serviceFee),
                    metaSize,
                  ),

                pw.SizedBox(height: 6),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 1),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(width: 1.4, color: PdfColors.black),
                      bottom: pw.BorderSide(width: 1.4, color: PdfColors.black),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL PEMBAYARAN',
                        style: pw.TextStyle(
                          fontSize: totalSize,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _formatRupiah(widget.order.total),
                        style: pw.TextStyle(
                          fontSize: totalSize,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),

                _buildPdfSummaryRow(
                  'Metode Bayar',
                  widget.order.paymentMethod,
                  metaSize,
                ),
                if (widget.cashAmount > 0) ...[
                  _buildPdfSummaryRow(
                    'Tunai Diterima',
                    _formatRupiah(widget.cashAmount),
                    metaSize,
                  ),
                  _buildPdfSummaryRow(
                    'Kembali',
                    _formatRupiah(changeAmount),
                    metaSize,
                  ),
                ],

                // -------------------------------------------------------------
                // 5. BARCODE & FOOTER ELEGAN
                // -------------------------------------------------------------
                pw.SizedBox(height: 12),
                pw.BarcodeWidget(
                  data: widget.order.invoiceNo,
                  barcode: pw.Barcode.code128(),
                  width: barcodeWidth,
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
                    fontSize: footerSize,
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
                maxWidth: 860,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: LayoutBuilder(
                  builder: (context, bc) {
                    final isNarrow = bc.maxWidth < 620;

                    final paperSelector = SegmentedButton<PaperRollSize>(
                      segments: const [
                        ButtonSegment(
                          value: PaperRollSize.mm80,
                          label: Text('80mm (Standar POS)', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.receipt_long_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: PaperRollSize.wide,
                          label: Text('100mm (Ekstra Lebar)', style: TextStyle(fontSize: 12)),
                          icon: Icon(Icons.aspect_ratio_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: PaperRollSize.mm58,
                          label: Text('58mm (Mini)', style: TextStyle(fontSize: 12)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

            // Live PDF Preview with Full Width and Interactive Zoom Controls
            Expanded(
              child: MaxWidthBox(
                maxWidth: 680,
                child: PdfPreview(
                  key: ValueKey(_selectedPaper),
                  build: (format) => _generatePdfReceipt(_currentPageFormat),
                  useActions: true,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  maxPageWidth: 540,
                  pdfFileName: 'Nota_${widget.order.invoiceNo}.pdf',
                  previewPageMargin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
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
