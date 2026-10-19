import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../state/auth_controller.dart';

class PenaltiesScreen extends StatefulWidget {
  const PenaltiesScreen({super.key, required this.role, this.reportId});
  final String role;
  final int? reportId;

  @override
  State<PenaltiesScreen> createState() => _PenaltiesScreenState();
}

class _PenaltiesScreenState extends State<PenaltiesScreen> {
  late Future<Map<String, dynamic>> _reports;
  late Future<Map<String, dynamic>> _summary;
  String? _error;
  String _statusFilter = '';
  String _categoryFilter = '';
  final TextEditingController _searchController = TextEditingController();
  late final Razorpay _razorpay;
  Map<String, dynamic>? _checkout;
  bool _paying = false;
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedEvidence = [];

  ApiService get _api => context.read<AuthController>().api;
  String get _path {
    final params = <String, String>{
      if (_statusFilter.isNotEmpty) 'status': _statusFilter,
      if (_categoryFilter.isNotEmpty) 'category': _categoryFilter,
      if (_searchController.text.trim().isNotEmpty)
        'search': _searchController.text.trim(),
    };
    return 'penalty-reports${params.isEmpty ? '' : '?${Uri(queryParameters: params).query}'}';
  }

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _summary = widget.role == 'ADMIN'
        ? _api.get('admin/penalty-dashboard')
        : Future.value(<String, dynamic>{});
    _reports = widget.reportId == null
        ? _api.get(_path)
        : _api.get('penalty-reports/${widget.reportId}').then((result) => {
              'data': [result['data']]
            });
  }

  @override
  void dispose() {
    _razorpay.clear();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _reports = _api.get(_path));
  }

  Future<void> _decide(Map<String, dynamic> report, String decision) async {
    final form = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        final amount = TextEditingController();
        final reason = TextEditingController();
        return AlertDialog(
          title: Text(
              decision == 'warning_issued' ? 'Issue warning' : 'Review report'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (decision == 'approved')
              TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Approved amount')),
            TextField(
                controller: reason,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Decision reason')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, {
                      'reason': reason.text,
                      if (decision == 'approved')
                        'disciplinary_amount': double.tryParse(amount.text) ?? 0
                    }),
                child: const Text('Save decision'))
          ],
        );
      },
    );
    if (form == null || !mounted) return;
    try {
      await _api.post('admin/penalty-reports/${report['id']}/decision',
          {'decision': decision, ...form});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Decision saved')));
      }
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _appeal(Map<String, dynamic> report) async {
    final penalty = report['penalty'] as Map<String, dynamic>?;
    if (penalty == null) return;
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Appeal penalty'),
                content: TextField(
                    controller: reason,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Explain your appeal')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Submit'))
                ]));
    if (accepted != true || !mounted) return;
    try {
      await _api.post('resident/penalties/${penalty['id']}/appeals',
          {'reason': reason.text});
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pay(Map<String, dynamic> penalty) async {
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final result =
          await _api.post('resident/penalties/${penalty['id']}/payment', {});
      _checkout = Map<String, dynamic>.from(result['data'] as Map);
      _razorpay.open({
        'key': _checkout!['key_id'],
        'amount': _checkout!['amount'],
        'currency': _checkout!['currency'],
        'order_id': _checkout!['order_id'],
        'name': _checkout!['name'],
        'description': _checkout!['description'],
        'prefill': _checkout!['prefill'],
        'notes': {'payment_order_id': _checkout!['payment_order_id']},
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _paying = false;
        });
      }
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    try {
      final result = await _api.post('resident/payments/verify', {
        'razorpay_order_id': response.orderId ?? _checkout?['order_id'] ?? '',
        'razorpay_payment_id': response.paymentId ?? '',
        'razorpay_signature': response.signature ?? '',
      });
      final verified = (result['data'] as Map?)?['success'] == true;
      if (!verified) {
        throw const ApiException('The payment could not be verified.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment verified successfully')));
      }
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Payment needs verification: $error');
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() {
        _paying = false;
        _error = 'Payment was not completed. ${response.message ?? ''}';
      });
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (mounted) setState(() => _paying = false);
  }

  Future<void> _viewEvidence(Map<String, dynamic> evidence) async {
    try {
      final bytes = await _api.getBytes('penalty-evidence/${evidence['id']}');
      if (!mounted) return;
      final image =
          (evidence['mime_type']?.toString() ?? '').startsWith('image/');
      await showDialog<void>(
          context: context,
          builder: (context) =>
              AlertDialog(
                  title:
                      Text(evidence['original_name']?.toString() ?? 'Evidence'),
                  content: image
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 420),
                          child: Image.memory(Uint8List.fromList(bytes),
                              fit: BoxFit.contain))
                      : Text(
                          'Secure evidence loaded (${bytes.length} bytes). This document type is available to authorized users.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'))
                  ]));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _createReport() async {
    final categories = <String, List<String>>{
      'parking_vehicle': [
        'assigned_slot',
        'blocking_vehicle',
        'fire_lane',
        'no_parking',
        'visitor_parking',
        'unregistered_vehicle'
      ],
      'noise_nuisance': [
        'quiet_hours',
        'party_noise',
        'common_area_disturbance',
        'unauthorized_loudspeaker',
        'out_of_hours_construction'
      ],
      'maintenance_financial': [
        'late_maintenance',
        'late_booking',
        'unpaid_authorized_charge',
        'breached_payment_schedule'
      ],
      'property_safety': [
        'property_damage',
        'safety_equipment_tampering',
        'blocked_emergency_exit',
        'unauthorized_modification',
        'shared_property_damage',
        'restricted_room_access'
      ],
    };
    List<Map<String, dynamic>> flats = [];
    List<Map<String, dynamic>> parkingSlots = [];
    try {
      final response = await _api.get('security/visitors/options');
      final options = Map<String, dynamic>.from(response['data'] as Map);
      flats = (options['flats'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      parkingSlots = (options['parking_slots'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;
    final location = TextEditingController();
    final description = TextEditingController();
    final financialId = TextEditingController();
    int? selectedFlatId;
    int? selectedVehicleSlotId;
    var incidentAt = DateTime.now();
    _selectedEvidence = [];
    String category = categories.keys.first;
    String type = categories[category]!.first;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: const Text('Report violation'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: categories.keys
                          .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: (value) => refresh(() {
                            category = value!;
                            type = categories[category]!.first;
                          })),
                  DropdownButtonFormField<String>(
                      key: ValueKey(category),
                      initialValue: type,
                      decoration:
                          const InputDecoration(labelText: 'Violation type'),
                      items: categories[category]!
                          .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: (value) => refresh(() => type = value!)),
                  DropdownButtonFormField<int>(
                      initialValue: selectedFlatId,
                      decoration:
                          const InputDecoration(labelText: 'Affected flat'),
                      hint: const Text('Select a flat when known'),
                      items: flats
                          .map((flat) => DropdownMenuItem<int>(
                              value: flat['id'] as int,
                              child: Text(flat['label']?.toString() ??
                                  'Flat ${flat['id']}')))
                          .toList(),
                      onChanged: (value) =>
                          refresh(() => selectedFlatId = value)),
                  if (category == 'maintenance_financial')
                    TextField(
                        controller: financialId,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText:
                                'Linked maintenance bill ID (for late maintenance)')),
                  if (category == 'parking_vehicle')
                    DropdownButtonFormField<int>(
                        initialValue: selectedVehicleSlotId,
                        decoration: const InputDecoration(
                            labelText: 'Vehicle or parking slot'),
                        hint: const Text('Select when applicable'),
                        items: parkingSlots
                            .map((slot) => DropdownMenuItem<int>(
                                value: slot['id'] as int,
                                child: Text(slot['label']?.toString() ??
                                    'Slot ${slot['id']}')))
                            .toList(),
                        onChanged: (value) =>
                            refresh(() => selectedVehicleSlotId = value)),
                  TextField(
                      controller: location,
                      decoration: const InputDecoration(
                          labelText: 'Incident location')),
                  TextField(
                      controller: description,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(labelText: 'Description')),
                  TextButton.icon(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: incidentAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(incidentAt));
                        if (time != null) {
                          refresh(() => incidentAt = DateTime(date.year,
                              date.month, date.day, time.hour, time.minute));
                        }
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text('Incident: $incidentAt')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: () => _pickEvidence(refresh),
                      icon: const Icon(Icons.add_a_photo),
                      label: Text(_selectedEvidence.isEmpty
                          ? 'Attach photos'
                          : '${_selectedEvidence.length} photo(s) selected')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, {
                            'category': category,
                            'violation_type': type,
                            'location': location.text,
                            'description': description.text,
                            if (selectedFlatId != null)
                              'flat_id': selectedFlatId,
                            if (int.tryParse(financialId.text) != null)
                              'maintenance_bill_id':
                                  int.parse(financialId.text),
                            if (selectedVehicleSlotId != null)
                              'vehicle_slot_id': selectedVehicleSlotId,
                            'incident_at': incidentAt.toIso8601String()
                          }),
                      child: const Text('Submit'))
                ],
              )),
    );
    location.dispose();
    description.dispose();
    financialId.dispose();
    if (payload == null || !mounted) return;
    try {
      final fields = <String, String>{
        'category': payload['category'].toString(),
        'violation_type': payload['violation_type'].toString(),
        'location': payload['location'].toString(),
        'description': payload['description'].toString(),
        'incident_at': payload['incident_at'].toString(),
        if (payload['flat_id'] != null)
          'flat_id': payload['flat_id'].toString(),
        if (payload['maintenance_bill_id'] != null)
          'maintenance_bill_id': payload['maintenance_bill_id'].toString(),
        if (payload['vehicle_slot_id'] != null)
          'vehicle_slot_id': payload['vehicle_slot_id'].toString(),
      };
      if (_selectedEvidence.isEmpty) {
        await _api.post('penalty-reports', {
          ...fields,
          if (fields.containsKey('flat_id'))
            'flat_id': int.parse(fields['flat_id']!),
          if (fields.containsKey('maintenance_bill_id'))
            'maintenance_bill_id': int.parse(fields['maintenance_bill_id']!),
          if (fields.containsKey('vehicle_slot_id'))
            'vehicle_slot_id': int.parse(fields['vehicle_slot_id']!)
        });
      } else {
        await _api.postMultipart('penalty-reports', fields, {
          for (var i = 0; i < _selectedEvidence.length; i++)
            'evidence[$i]': _selectedEvidence[i].path
        });
      }
      _selectedEvidence = [];
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Penalty management'), actions: [
          if (widget.role == 'ADMIN')
            IconButton(
                tooltip: 'Rules and appeals',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdminPenaltyToolsScreen())),
                icon: const Icon(Icons.tune)),
          if (widget.role == 'SECURITY')
            IconButton(onPressed: _createReport, icon: const Icon(Icons.add)),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ]),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _reports,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: _reload,
                      child: Text(
                          'Could not load reports. Tap to retry. ${snapshot.error}')));
            }
            final data = snapshot.data?['data'];
            final items = data is List
                ? data
                : data is Map
                    ? data['data'] as List? ?? const []
                    : const [];
            return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  if (widget.role == 'ADMIN') _dashboardCard(),
                  if (widget.role == 'ADMIN') _filters(),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('No violation reports yet.')),
                    ),
                  for (final value in items)
                    _reportCard(value as Map<String, dynamic>)
                ]));
          },
        ),
      );

  Widget _filters() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search location or description',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _reload,
                ),
              ),
              onSubmitted: (_) => _reload(),
            ),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All')),
                    DropdownMenuItem(
                        value: 'reported', child: Text('Reported')),
                    DropdownMenuItem(
                        value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(
                        value: 'rejected', child: Text('Rejected')),
                    DropdownMenuItem(
                        value: 'warning_issued', child: Text('Warning')),
                  ],
                  onChanged: (value) {
                    setState(() => _statusFilter = value ?? '');
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _categoryFilter,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All')),
                    DropdownMenuItem(
                        value: 'parking_vehicle', child: Text('Parking')),
                    DropdownMenuItem(
                        value: 'noise_nuisance', child: Text('Noise')),
                    DropdownMenuItem(
                        value: 'maintenance_financial',
                        child: Text('Financial')),
                    DropdownMenuItem(
                        value: 'property_safety', child: Text('Safety')),
                  ],
                  onChanged: (value) {
                    setState(() => _categoryFilter = value ?? '');
                    _reload();
                  },
                ),
              ),
            ]),
          ]),
        ),
      );

  Widget _dashboardCard() => FutureBuilder<Map<String, dynamic>>(
        future: _summary,
        builder: (context, snapshot) {
          final data = snapshot.data?['data'];
          if (data is! Map) return const SizedBox.shrink();
          final counts = data['by_status'] as Map? ?? const {};
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 16, runSpacing: 8, children: [
                Text('Reports: ${data['total_reports'] ?? 0}'),
                for (final entry in counts.entries)
                  Text('${entry.key}: ${entry.value}'),
              ]),
            ),
          );
        },
      );

  Widget _reportCard(Map<String, dynamic> report) {
    final penalty = report['penalty'] as Map<String, dynamic>?;
    final appeals = penalty?['appeals'] is List
        ? (penalty!['appeals'] as List)
            .whereType<Map>()
            .map((appeal) => Map<String, dynamic>.from(appeal))
            .toList()
        : const <Map<String, dynamic>>[];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${report['category'] ?? 'Report'} · ${report['violation_type'] ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                  '${report['location'] ?? ''} · ${report['incident_at'] ?? ''}'),
              Text(report['description']?.toString() ?? ''),
              const SizedBox(height: 6),
              Text('Status: ${report['status'] ?? 'reported'}'),
              if (penalty != null) ...[
                Text(
                    'Amount: ₹${_totalPenaltyAmount(penalty)} (fine ₹${penalty['disciplinary_amount']}, late fee ₹${penalty['late_fee_amount'] ?? 0}, repair ₹${penalty['repair_cost'] ?? 0})'),
                Text(
                    'Due: ${penalty['due_date'] ?? 'Not set'} · Payment: ${penalty['payment_status']}'),
                Text(
                    'Issued: ${penalty['decided_at'] ?? report['created_at'] ?? '—'}'),
                Text('Decision: ${penalty['decision_reason'] ?? '—'}'),
                if (widget.role == 'RESIDENT' && appeals.isNotEmpty)
                  Text(
                      'Appeal status: ${appeals.last['status'] ?? 'submitted'}'),
              ],
              if (report['evidence'] is List &&
                  (report['evidence'] as List).isNotEmpty)
                Wrap(spacing: 6, children: [
                  for (final item in report['evidence'] as List)
                    ActionChip(
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: Text(
                            (item as Map)['original_name']?.toString() ??
                                'Evidence'),
                        onPressed: () =>
                            _viewEvidence(Map<String, dynamic>.from(item)))
                ]),
              if (widget.role == 'ADMIN' &&
                  const {'reported', 'under_review'}.contains(report['status']))
                Wrap(spacing: 8, children: [
                  TextButton(
                      onPressed: () => _decide(report, 'warning_issued'),
                      child: const Text('Warn')),
                  TextButton(
                      onPressed: () => _decide(report, 'rejected'),
                      child: const Text('Reject')),
                  FilledButton(
                      onPressed: () => _decide(report, 'approved'),
                      child: const Text('Approve'))
                ]),
              if (widget.role == 'RESIDENT' &&
                  penalty != null &&
                  penalty['status'] == 'approved')
                TextButton(
                    onPressed: () => _appeal(report),
                    child: const Text('Appeal')),
              if (widget.role == 'RESIDENT' &&
                  penalty != null &&
                  penalty['status'] == 'approved' &&
                  penalty['payment_status'] == 'unpaid')
                FilledButton.icon(
                    onPressed: _paying ? null : () => _pay(penalty),
                    icon: _paying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.payment),
                    label: const Text('Pay securely')),
            ])));
  }

  num _totalPenaltyAmount(Map<String, dynamic> penalty) =>
      (num.tryParse(penalty['disciplinary_amount']?.toString() ?? '') ?? 0) +
      (num.tryParse(penalty['late_fee_amount']?.toString() ?? '') ?? 0) +
      (num.tryParse(penalty['repair_cost']?.toString() ?? '') ?? 0);

  Future<void> _pickEvidence(StateSetter refresh) async {
    try {
      final photos = await _picker.pickMultiImage(imageQuality: 82, limit: 5);
      if (photos.isNotEmpty) {
        refresh(() => _selectedEvidence = photos.take(5).toList());
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not select evidence: $error');
      }
    }
  }
}

class AdminPenaltyToolsScreen extends StatefulWidget {
  const AdminPenaltyToolsScreen({super.key});

  @override
  State<AdminPenaltyToolsScreen> createState() =>
      _AdminPenaltyToolsScreenState();
}

class _AdminPenaltyToolsScreenState extends State<AdminPenaltyToolsScreen> {
  static const categories = <String, List<String>>{
    'parking_vehicle': [
      'assigned_slot',
      'blocking_vehicle',
      'fire_lane',
      'no_parking',
      'visitor_parking',
      'unregistered_vehicle'
    ],
    'noise_nuisance': [
      'quiet_hours',
      'party_noise',
      'common_area_disturbance',
      'unauthorized_loudspeaker',
      'out_of_hours_construction'
    ],
    'maintenance_financial': [
      'late_maintenance',
      'late_booking',
      'unpaid_authorized_charge',
      'breached_payment_schedule'
    ],
    'property_safety': [
      'property_damage',
      'safety_equipment_tampering',
      'blocked_emergency_exit',
      'unauthorized_modification',
      'shared_property_damage',
      'restricted_room_access'
    ],
  };

  ApiService get api => context.read<AuthController>().api;

  Future<List<dynamic>> _load(String path) async {
    final response = await api.get(path);
    final data = response['data'];
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }

  Future<void> _editRule([Map<String, dynamic>? existing]) async {
    var category = existing?['category']?.toString() ?? categories.keys.first;
    var type =
        existing?['violation_type']?.toString() ?? categories[category]!.first;
    final minimum = TextEditingController(
        text: existing?['minimum_amount']?.toString() ?? '0');
    final maximum = TextEditingController(
        text: existing?['maximum_amount']?.toString() ?? '');
    final lateFee = TextEditingController(
        text: existing?['late_fee_amount']?.toString() ?? '');
    final grace = TextEditingController(
        text: existing?['grace_period_days']?.toString() ?? '0');
    final description =
        TextEditingController(text: existing?['description']?.toString() ?? '');
    var evidence = existing?['requires_evidence'] != false;
    var active = existing?['active'] != false;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text(existing == null
                        ? 'Configure penalty rule'
                        : 'Edit penalty rule'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                          items: categories.keys
                              .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v.replaceAll('_', ' '))))
                              .toList(),
                          onChanged: (v) => update(() {
                                category = v!;
                                type = categories[category]!.first;
                              })),
                      DropdownButtonFormField<String>(
                          key: ValueKey(category),
                          initialValue: type,
                          decoration: const InputDecoration(
                              labelText: 'Violation type'),
                          items: categories[category]!
                              .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v.replaceAll('_', ' '))))
                              .toList(),
                          onChanged: (v) => update(() => type = v!)),
                      TextField(
                          controller: minimum,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Minimum disciplinary amount')),
                      TextField(
                          controller: maximum,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText:
                                  'Maximum disciplinary amount (optional)')),
                      TextField(
                          controller: lateFee,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Fixed late fee (optional)')),
                      TextField(
                          controller: grace,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Grace period in days')),
                      TextField(
                          controller: description,
                          decoration:
                              const InputDecoration(labelText: 'Rule notes')),
                      SwitchListTile(
                          value: evidence,
                          title: const Text('Require evidence'),
                          onChanged: (v) => update(() => evidence = v)),
                      if (existing != null)
                        SwitchListTile(
                            value: active,
                            title: const Text('Rule active'),
                            onChanged: (v) => update(() => active = v)),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, {
                                'category': category,
                                'violation_type': type,
                                'minimum_amount':
                                    double.tryParse(minimum.text) ?? 0,
                                'maximum_amount': double.tryParse(maximum.text),
                                'late_fee_amount':
                                    double.tryParse(lateFee.text),
                                'grace_period_days':
                                    int.tryParse(grace.text) ?? 0,
                                'description': description.text,
                                'requires_evidence': evidence,
                                'active': active
                              }),
                          child: const Text('Save rule'))
                    ])));
    minimum.dispose();
    maximum.dispose();
    lateFee.dispose();
    grace.dispose();
    description.dispose();
    if (result == null || !mounted) return;
    try {
      final path = existing == null
          ? 'admin/penalty-rules'
          : 'admin/penalty-rules/${existing['id']}';
      if (existing == null) {
        await api.post(path, result);
      } else {
        await api.put(path, result);
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _decideAppeal(Map<String, dynamic> appeal) async {
    final reason = TextEditingController();
    final amount = TextEditingController();
    var decision = 'upheld';
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: const Text('Decide appeal'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: decision,
                          items: const [
                            DropdownMenuItem(
                                value: 'upheld', child: Text('Uphold penalty')),
                            DropdownMenuItem(
                                value: 'adjusted',
                                child: Text('Adjust amount')),
                            DropdownMenuItem(
                                value: 'waived', child: Text('Waive penalty')),
                            DropdownMenuItem(
                                value: 'rejected', child: Text('Reject appeal'))
                          ],
                          onChanged: (v) => update(() => decision = v!)),
                      if (decision == 'adjusted')
                        TextField(
                            controller: amount,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Adjusted amount')),
                      TextField(
                          controller: reason,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'Decision reason'))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, {
                                'decision': decision,
                                'reason': reason.text,
                                if (decision == 'adjusted')
                                  'disciplinary_amount':
                                      double.tryParse(amount.text) ?? 0
                              }),
                          child: const Text('Record decision'))
                    ])));
    reason.dispose();
    amount.dispose();
    if (result == null || !mounted) return;
    try {
      await api.post('admin/penalty-appeals/${appeal['id']}/decision', result);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Penalty rules and appeals'),
            bottom:
                const TabBar(tabs: [Tab(text: 'Rules'), Tab(text: 'Appeals')]),
          ),
          body: TabBarView(children: [_rulesTab(), _appealsTab()]),
        ),
      );

  Widget _rulesTab() => Column(children: [
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _load('admin/penalty-rules'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Could not load rules: ${snapshot.error}'));
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return const Center(
                    child: Text(
                        'No rules configured. Reports can be reviewed, but cannot be fined until an administrator configures a rule.'));
              }
              return ListView(children: [
                for (final row in rows)
                  Card(
                      child: ListTile(
                    title:
                        Text('${row['category']} · ${row['violation_type']}'),
                    subtitle: Text(
                        '₹${row['minimum_amount']}–${row['maximum_amount'] ?? 'no maximum'} · late fee ₹${row['late_fee_amount'] ?? '—'} · grace ${row['grace_period_days']} days · ${row['active'] == true ? 'active' : 'inactive'}'),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _editRule(Map<String, dynamic>.from(row as Map))),
                  ))
              ]);
            },
          ),
        ),
        Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
                onPressed: () => _editRule(),
                icon: const Icon(Icons.add),
                label: const Text('Add rule'))),
      ]);

  Widget _appealsTab() => FutureBuilder<List<dynamic>>(
        future: _load('admin/penalty-appeals'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load appeals: ${snapshot.error}'));
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('No appeals submitted.'));
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final item in rows)
              _appealCard(Map<String, dynamic>.from(item as Map))
          ]);
        },
      );

  Widget _appealCard(Map<String, dynamic> appeal) {
    final penalty = appeal['penalty'] as Map<String, dynamic>? ?? {};
    final report = penalty['report'] as Map<String, dynamic>? ?? {};
    final resident = penalty['resident'] as Map<String, dynamic>? ?? {};
    final residentUser = resident['user'] as Map<String, dynamic>? ?? {};
    return Card(
        child: ListTile(
            title: Text(
                '${residentUser['name'] ?? 'Resident'} · ₹${penalty['disciplinary_amount'] ?? ''}'),
            subtitle: Text(
                '${report['category'] ?? ''} / ${report['violation_type'] ?? ''}\n${appeal['reason'] ?? ''}\nStatus: ${appeal['status']}'),
            isThreeLine: true,
            trailing: appeal['status'] == 'submitted'
                ? IconButton(
                    tooltip: 'Decide appeal',
                    icon: const Icon(Icons.gavel),
                    onPressed: () => _decideAppeal(appeal))
                : null));
  }
}
