import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/transaction.dart';

class PdfService {
  // Cache for loaded fonts
  pw.Font? _regularFont;
  pw.Font? _boldFont;

  Future<Uint8List> generateLedgerPdf({
    required String residentName,
    required String flatNumber,
    String? email,
    String? mobile,
    required List<ResidentTransaction> transactions,
    required TransactionSummary summary,
    required String filterType,
  }) async {
    // Load fonts that support Unicode (including ₹ symbol)
    await _loadFonts();
    
    final pdf = pw.Document();
    
    // Date formatter
    final dateFormat = DateFormat('dd MMM yyyy');
    final generatedDate = dateFormat.format(DateTime.now());
    
    // Split transactions into pages if needed
    const transactionsPerPage = 15;
    final totalPages = (transactions.length / transactionsPerPage).ceil();
    if (totalPages == 0) {
      // At least one page even if empty
      pdf.addPage(_buildPage(
        pageNumber: 1,
        totalPages: 1,
        residentName: residentName,
        flatNumber: flatNumber,
        email: email,
        mobile: mobile,
        generatedDate: generatedDate,
        filterType: filterType,
        transactions: transactions,
        summary: summary,
        isLastPage: true,
      ));
    } else {
      for (int i = 0; i < totalPages; i++) {
        final startIndex = i * transactionsPerPage;
        final endIndex = (startIndex + transactionsPerPage).clamp(0, transactions.length);
        final pageTransactions = transactions.sublist(startIndex, endIndex);
        final isLastPage = i == totalPages - 1;
        
        pdf.addPage(_buildPage(
          pageNumber: i + 1,
          totalPages: totalPages,
          residentName: residentName,
          flatNumber: flatNumber,
          email: email,
          mobile: mobile,
          generatedDate: generatedDate,
          filterType: filterType,
          transactions: pageTransactions,
          summary: isLastPage ? summary : null,
          isLastPage: isLastPage,
        ));
      }
    }
    
    return pdf.save();
  }
  
  /// Load fonts that support Unicode characters including ₹ symbol
  Future<void> _loadFonts() async {
    if (_regularFont == null || _boldFont == null) {
      // Load bundled Noto Sans fonts - excellent Unicode support including Indian Rupee symbol
      final regularFontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final boldFontData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      
      _regularFont = pw.Font.ttf(regularFontData);
      _boldFont = pw.Font.ttf(boldFontData);
    }
  }
  
  pw.Page _buildPage({
    required int pageNumber,
    required int totalPages,
    required String residentName,
    required String flatNumber,
    String? email,
    String? mobile,
    required String generatedDate,
    required String filterType,
    required List<ResidentTransaction> transactions,
    TransactionSummary? summary,
    required bool isLastPage,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header (only on first page)
            if (pageNumber == 1) ...[
              _buildHeader(
                residentName: residentName,
                flatNumber: flatNumber,
                email: email,
                mobile: mobile,
                generatedDate: generatedDate,
                filterType: filterType,
              ),
              pw.SizedBox(height: 20),
            ],
            
            // Table Header
            _buildTableHeader(),
            
            // Transactions
            ...transactions.map((t) => _buildTransactionRow(t)),
            
            // Add spacing before summary if last page
            if (isLastPage && summary != null) ...[
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 10),
              _buildSummary(summary),
            ],
            
            // Page footer
            pw.Spacer(),
            _buildFooter(pageNumber, totalPages),
          ],
        );
      },
    );
  }
  
  pw.Widget _buildHeader({
    required String residentName,
    required String flatNumber,
    String? email,
    String? mobile,
    required String generatedDate,
    required String filterType,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'NIVORA',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            font: _boldFont,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Ledger History',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            font: _boldFont,
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Resident: $residentName', style: pw.TextStyle(fontSize: 11, font: _regularFont)),
              pw.SizedBox(height: 3),
              pw.Text('Flat/Unit: $flatNumber', style: pw.TextStyle(fontSize: 11, font: _regularFont)),
              if (email != null) ...[
                pw.SizedBox(height: 3),
                pw.Text('Email: $email', style: pw.TextStyle(fontSize: 11, font: _regularFont)),
              ],
              if (mobile != null) ...[
                pw.SizedBox(height: 3),
                pw.Text('Mobile: $mobile', style: pw.TextStyle(fontSize: 11, font: _regularFont)),
              ],
              pw.SizedBox(height: 3),
              pw.Text('Statement Date: $generatedDate', style: pw.TextStyle(fontSize: 11, font: _regularFont)),
              pw.SizedBox(height: 3),
              pw.Text('Transaction Type: $filterType', style: pw.TextStyle(fontSize: 11, font: _regularFont)),
            ],
          ),
        ),
      ],
    );
  }
  
  pw.Widget _buildTableHeader() {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
        border: pw.Border(
          bottom: pw.BorderSide(width: 2, color: PdfColors.grey800),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 60,
            child: pw.Text(
              'Date',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: _boldFont),
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'Description',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: _boldFont),
            ),
          ),
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              'Debit',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: _boldFont),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              'Credit',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: _boldFont),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.SizedBox(
            width: 75,
            child: pw.Text(
              'Balance',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: _boldFont),
            ),
          ),
        ],
      ),
    );
  }
  
  pw.Widget _buildTransactionRow(ResidentTransaction transaction) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final date = dateFormat.format(transaction.transactionDate);
    final isDebit = transaction.isDebit;
    
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Date
          pw.SizedBox(
            width: 60,
            child: pw.Text(
              date,
              style: pw.TextStyle(fontSize: 9, font: _regularFont),
            ),
          ),
          // Description
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  transaction.description,
                  style: pw.TextStyle(fontSize: 9, font: _regularFont),
                ),
                if (transaction.referenceNumber != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    transaction.referenceNumber!,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                      font: _regularFont,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Debit
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              isDebit ? _formatMoney(transaction.amount) : '—',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isDebit ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isDebit ? PdfColors.red700 : PdfColors.grey600,
                font: isDebit ? _boldFont : _regularFont,
              ),
            ),
          ),
          pw.SizedBox(width: 5),
          // Credit
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              !isDebit ? _formatMoney(transaction.amount) : '—',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: !isDebit ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: !isDebit ? PdfColors.green700 : PdfColors.grey600,
                font: !isDebit ? _boldFont : _regularFont,
              ),
            ),
          ),
          pw.SizedBox(width: 5),
          // Balance
          pw.SizedBox(
            width: 75,
            child: pw.Text(
              _formatMoney(transaction.balanceAfter),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                font: _boldFont,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  pw.Widget _buildSummary(TransactionSummary summary) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Summary',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              font: _boldFont,
            ),
          ),
          pw.SizedBox(height: 8),
          _buildSummaryRow('Total Debit', summary.totalDebit, PdfColors.red700),
          pw.SizedBox(height: 5),
          _buildSummaryRow('Total Credit', summary.totalCredit, PdfColors.green700),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 5),
          _buildSummaryRow('Outstanding Balance', summary.outstandingAmount, PdfColors.orange700, isBold: true, fontSize: 12),
        ],
      ),
    );
  }
  
  pw.Widget _buildSummaryRow(String label, String amount, PdfColor color, {bool isBold = false, double fontSize = 10}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            font: isBold ? _boldFont : _regularFont,
          ),
        ),
        pw.Text(
          _formatMoney(amount),
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
            color: color,
            font: _boldFont,
          ),
        ),
      ],
    );
  }
  
  pw.Widget _buildFooter(int pageNumber, int totalPages) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by Nivora',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, font: _regularFont),
          ),
          pw.Text(
            'Page $pageNumber of $totalPages',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, font: _regularFont),
          ),
        ],
      ),
    );
  }
  
  String _formatMoney(String amount) {
    final value = double.tryParse(amount) ?? 0;
    final formatter = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 2,
      locale: 'en_IN',
    );
    return formatter.format(value);
  }
}
