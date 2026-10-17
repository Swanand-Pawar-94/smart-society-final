import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../state/auth_controller.dart';
import '../services/pdf_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  TransactionHistoryResponse? _data;
  String? _error;
  bool _loading = true;
  String _filterType = 'ALL'; // ALL, DEBIT, CREDIT
  int _currentPage = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
    });

    try {
      final api = context.read<AuthController>().api;
      final params = _buildQueryParams();
      final path = 'resident/transaction-history${params.isNotEmpty ? '?$params' : ''}';
      final response = await api.get(path);
      
      if (mounted) {
        setState(() {
          _data = TransactionHistoryResponse.fromJson(response);
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_data == null || !_data!.pagination.hasNextPage || _loading) return;

    setState(() => _loading = true);

    try {
      final api = context.read<AuthController>().api;
      final nextPage = _currentPage + 1;
      final params = _buildQueryParams(page: nextPage);
      final path = 'resident/transaction-history${params.isNotEmpty ? '?$params' : ''}';
      final response = await api.get(path);
      
      if (mounted) {
        final newData = TransactionHistoryResponse.fromJson(response);
        setState(() {
          _data = TransactionHistoryResponse(
            summary: newData.summary,
            transactions: [..._data!.transactions, ...newData.transactions],
            pagination: newData.pagination,
          );
          _currentPage = nextPage;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load more: $error')),
        );
      }
    }
  }

  String _buildQueryParams({int? page}) {
    final params = <String>[];
    if (_filterType != 'ALL') {
      params.add('transaction_type=$_filterType');
    }
    if (page != null) {
      params.add('page=$page');
    }
    return params.join('&');
  }

  void _changeFilter(String filter) {
    if (_filterType != filter) {
      setState(() => _filterType = filter);
      _load();
    }
  }

  Future<void> _exportToPdf() async {
    if (_data == null || _data!.transactions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No ledger transactions available to export.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Generating PDF...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Get user info
      final auth = context.read<AuthController>();
      final sessionUser = auth.session?.user;
      
      // Fetch resident profile for additional details
      Map<String, dynamic>? profile;
      try {
        final response = await auth.api.get('resident/profile');
        profile = response['data'] as Map<String, dynamic>?;
      } catch (e) {
        // If profile fetch fails, continue with basic session data
        profile = null;
      }
      
      final residentName = sessionUser?.name ?? 'Resident';
      final email = sessionUser?.email;
      
      // Get flat info from profile if available
      final flatInfo = profile?['flat'] as Map<String, dynamic>?;
      final flatNumber = flatInfo != null 
          ? '${flatInfo['building'] ?? ''} ${flatInfo['flat_number'] ?? ''}'.trim()
          : 'N/A';
      
      // Get mobile from profile if available
      final mobile = profile?['user']?['phone']?.toString();

      // Generate PDF
      final pdfService = PdfService();
      final pdfBytes = await pdfService.generateLedgerPdf(
        residentName: residentName,
        flatNumber: flatNumber,
        email: email,
        mobile: mobile,
        transactions: _data!.transactions,
        summary: _data!.summary,
        filterType: _filterType,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Generate filename
      final dateFormat = DateFormat('yyyyMMdd');
      final dateStr = dateFormat.format(DateTime.now());
      final sanitizedName = residentName.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      final filename = 'Nivora_Ledger_${sanitizedName}_$dateStr.pdf';

      // Share PDF
      if (mounted) {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: filename,
        );

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ledger PDF generated successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (error) {
      // Close loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to generate ledger PDF. Please try again. Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger History'),
        elevation: 0,
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final data = _data!;
    final summary = data.summary;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Filter Chips
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('DEBIT', 'Debit'),
                  const SizedBox(width: 8),
                  _buildFilterChip('CREDIT', 'Credit'),
                ],
              ),
            ),
          ),

          // Ledger Header with Export Button
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction Ledger',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _exportToPdf,
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('Export PDF'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Table Header
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Date',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Debit',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Credit',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Balance',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Transaction Rows
          data.transactions.isEmpty
              ? const SliverFillRemaining(
                  child: Center(child: Text('No transactions found.')),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == data.transactions.length) {
                        return _loading
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : const SizedBox.shrink();
                      }
                      return _buildTransactionRow(data.transactions[index], index);
                    },
                    childCount: data.transactions.length + (_loading ? 1 : 0),
                  ),
                ),

          // Summary Section
          if (data.transactions.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildSummaryRow(
                      'Outstanding Balance',
                      summary.outstandingAmount,
                      isOutstanding: true,
                    ),
                    const Divider(height: 24),
                    _buildSummaryRow(
                      'Total Debit',
                      summary.totalDebit,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryRow(
                      'Total Credit',
                      summary.totalCredit,
                      color: Colors.green.shade700,
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _changeFilter(value),
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  Widget _buildTransactionRow(ResidentTransaction transaction, int index) {
    final isDebit = transaction.isDebit;
    final bgColor = index.isEven ? Colors.white : Colors.grey.shade50;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(transaction.transactionDate),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Description - Increased flex and removed truncation
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  softWrap: true,
                ),
                if (transaction.referenceNumber != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    transaction.referenceNumber!,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Debit
          Expanded(
            flex: 2,
            child: Text(
              isDebit ? _formatMoney(transaction.amount) : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDebit ? Colors.red.shade700 : Colors.grey.shade400,
              ),
            ),
          ),
          // Credit
          Expanded(
            flex: 2,
            child: Text(
              !isDebit ? _formatMoney(transaction.amount) : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: !isDebit ? Colors.green.shade700 : Colors.grey.shade400,
              ),
            ),
          ),
          // Balance
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(transaction.balanceAfter),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String amount, {Color? color, bool isOutstanding = false}) {
    final displayColor = color ?? (isOutstanding ? Colors.orange.shade700 : Colors.grey.shade800);
    final fontSize = isOutstanding ? 18.0 : 15.0;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isOutstanding ? 15 : 14,
            fontWeight: isOutstanding ? FontWeight.w700 : FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          _formatMoney(amount),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: displayColor,
          ),
        ),
      ],
    );
  }

  String _formatMoney(String amount) {
    final value = double.tryParse(amount) ?? 0;
    return '₹${value.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}';
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load transactions',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
