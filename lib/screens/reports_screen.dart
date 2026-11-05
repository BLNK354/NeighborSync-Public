import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/charts.dart';
import '../widgets/responsive_bits.dart';
import '../core/permissions.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Reports & Analytics: a live overview, plus a report builder (type and
/// date range) with a monthly trend chart, a metrics table and PDF export.
/// Every number is calculated from live data for the chosen dates.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _ReportType { financial, community, occupancy }

/// Two values for one month on the trend chart.
class _MonthBucket {
  final String label;
  final double seriesA;
  final double seriesB;
  _MonthBucket(this.label, this.seriesA, this.seriesB);
}

class _ReportsScreenState extends State<ReportsScreen> with SafeSetState<ReportsScreen> {
  bool _loading = true;
  bool _generating = false;
  String? _error;

  _ReportType _reportType = _ReportType.financial;

  /// False for an officer with `bills` access only: they get the Financial
  /// Summary alone, since the other reports would show zeros for data they
  /// cannot read.
  bool _allReports = true;
  late DateTime _dateFrom;
  late DateTime _dateTo;

  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _violations = [];
  List<Map<String, dynamic>> _complaints = [];
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _lots = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _permits = [];

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    final now = DateTime.now();
    _dateTo = DateTime(now.year, now.month, now.day);
    _dateFrom = DateTime(now.year, now.month - 5, 1); // last 6 months
    _load();
    SupabaseService.instance.getMyPermissions().then((perms) {
      if (!mounted) return;
      final all = canAccessModule(perms, 'audit_logs');
      setState(() {
        _allReports = all;
        if (!all) _reportType = _ReportType.financial;
      });
    }).catchError((_) {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = SupabaseService.instance.client;
    // A blocked or failing table gives an empty list, so the page still
    // shows whatever the user can read.
    Future<List<Map<String, dynamic>>> q(Future<dynamic> f) async {
      try {
        return List<Map<String, dynamic>>.from(await f as List);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
    try {
      // Try the database function first: it works for read-limited officers.
      // If it fails, fall back to the per-table queries below.
      try {
        final rpc = await c.rpc('report_overview_data');
        if (rpc is Map) {
          final m = Map<String, dynamic>.from(rpc);
          List<Map<String, dynamic>> lst(String k) =>
              List<Map<String, dynamic>>.from((m[k] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
          final allUsers = lst('users');
          if (!mounted) return;
          setState(() {
            _bills = lst('bills');
            _payments = lst('payments');
            _violations = lst('violations');
            _complaints = lst('complaints');
            _incidents = lst('incidents');
            _users = allUsers
                .where((u) => {'member_resident', 'tenant'}.contains((u['roles'] as Map?)?['name']))
                .toList();
            _lots = lst('lots');
            _vehicles = lst('vehicles');
            _permits = lst('permits');
            _loading = false;
          });
          return;
        }
      } catch (_) {
        // Function missing or not allowed; use direct reads.
      }
      final results = await Future.wait([
        q(c.from('bills').select('amount, due_date, status')),
        q(c.from('payments').select('amount_paid, payment_date, status')),
        q(c.from('violations').select('id, status, created_at')),
        q(c.from('complaints').select('id, status, created_at')),
        q(c.from('security_incidents').select('id, status, created_at')),
        // Roles are filtered in Dart after loading.
        q(c.from('users').select('id, created_at, roles(name)')),
        q(c.from('lots').select('status')),
        q(c.from('vehicles').select('status')),
        q(c.from('permits').select('status')),
      ]);
      if (!mounted) return;
      final allUsers = List<Map<String, dynamic>>.from(results[5]);
      setState(() {
        _bills = List<Map<String, dynamic>>.from(results[0]);
        _payments = List<Map<String, dynamic>>.from(results[1]);
        _violations = List<Map<String, dynamic>>.from(results[2]);
        _complaints = List<Map<String, dynamic>>.from(results[3]);
        _incidents = List<Map<String, dynamic>>.from(results[4]);
        _users = allUsers
            .where((u) => {'member_resident', 'tenant'}
                .contains((u['roles'] as Map?)?['name']))
            .toList();
        _lots = List<Map<String, dynamic>>.from(results[6]);
        _vehicles = List<Map<String, dynamic>>.from(results[7]);
        _permits = List<Map<String, dynamic>>.from(results[8]);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  DateTime? _d(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

  bool _inRange(DateTime? d) => d != null && !d.isBefore(_dateFrom) && !d.isAfter(_dateTo.add(const Duration(days: 1)));

  /// Month keys (`2026-03`) in the date range, at most the last 12.
  List<String> get _monthKeys {
    final keys = <String>[];
    var cursor = DateTime(_dateFrom.year, _dateFrom.month);
    final end = DateTime(_dateTo.year, _dateTo.month);
    while (!cursor.isAfter(end)) {
      keys.add('${cursor.year}-${cursor.month.toString().padLeft(2, '0')}');
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return keys.length > 12 ? keys.sublist(keys.length - 12) : keys;
  }

  String _monthLabel(String key) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final parts = key.split('-');
    return names[int.parse(parts[1]) - 1];
  }

  /// One bucket per month for the selected report type.
  List<_MonthBucket> get _chartData {
    return _monthKeys.map((key) {
      switch (_reportType) {
        case _ReportType.financial:
          final billed = _bills
              .where((b) => '${_d(b['due_date'])?.year}-${_d(b['due_date'])?.month.toString().padLeft(2, '0')}' == key)
              .fold<double>(0, (s, b) => s + (num.tryParse(b['amount']?.toString() ?? '0') ?? 0));
          final collected = _payments
              .where((p) =>
                  p['status'] == 'verified' &&
                  '${_d(p['payment_date'])?.year}-${_d(p['payment_date'])?.month.toString().padLeft(2, '0')}' == key)
              .fold<double>(0, (s, p) => s + (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0));
          return _MonthBucket(_monthLabel(key), collected, billed);
        case _ReportType.community:
          final cases = _violations
              .where((v) => '${_d(v['created_at'])?.year}-${_d(v['created_at'])?.month.toString().padLeft(2, '0')}' == key)
              .length
              .toDouble();
          final complaints = _complaints
              .where((c) => '${_d(c['created_at'])?.year}-${_d(c['created_at'])?.month.toString().padLeft(2, '0')}' == key)
              .length
              .toDouble();
          return _MonthBucket(_monthLabel(key), cases, complaints);
        case _ReportType.occupancy:
          final newSignups = _users
              .where((u) => '${_d(u['created_at'])?.year}-${_d(u['created_at'])?.month.toString().padLeft(2, '0')}' == key)
              .length
              .toDouble();
          return _MonthBucket(_monthLabel(key), newSignups, 0);
      }
    }).toList();
  }

  (String, String) get _seriesLabels {
    switch (_reportType) {
      case _ReportType.financial:
        return ('Collected', 'Billed');
      case _ReportType.community:
        return ('Cases', 'Complaints');
      case _ReportType.occupancy:
        return ('New signups', '');
    }
  }

  /// Label and value rows for the metrics table.
  List<(String, String)> get _metrics {
    switch (_reportType) {
      case _ReportType.financial:
        final billed = _bills
            .where((b) => _inRange(_d(b['due_date'])))
            .fold<double>(0, (s, b) => s + (num.tryParse(b['amount']?.toString() ?? '0') ?? 0));
        final collected = _payments
            .where((p) => p['status'] == 'verified' && _inRange(_d(p['payment_date'])))
            .fold<double>(0, (s, p) => s + (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0));
        final outstanding = _bills
            .where((b) => {'pending', 'overdue', 'partial'}.contains(b['status']))
            .fold<double>(0, (s, b) => s + (num.tryParse(b['amount']?.toString() ?? '0') ?? 0));
        return [
          ('Total Billed', _money(billed)),
          ('Total Collected', _money(collected)),
          ('Outstanding (current)', _money(outstanding)),
        ];
      case _ReportType.community:
        final newCases = _violations.where((v) => _inRange(_d(v['created_at']))).length;
        final newComplaints = _complaints.where((c) => _inRange(_d(c['created_at']))).length;
        final openIncidents = _incidents.where((i) => {'open', 'investigating'}.contains(i['status'])).length;
        return [
          ('New Cases', '$newCases'),
          ('New Complaints', '$newComplaints'),
          ('Open Incidents (current)', '$openIncidents'),
        ];
      case _ReportType.occupancy:
        final residents = _users.where((u) => (u['roles'] as Map?)?['name'] == 'member_resident').length;
        final tenants = _users.where((u) => (u['roles'] as Map?)?['name'] == 'tenant').length;
        final newInRange = _users.where((u) => _inRange(_d(u['created_at']))).length;
        final occupiedLots = _lots.where((l) => l['status'] == 'occupied').length;
        return [
          ('Residents + Tenants (current)', '${residents + tenants}'),
          ('New Sign-ups (period)', '$newInRange'),
          ('Occupied Lots (current)', '$occupiedLots'),
        ];
    }
  }

  String _money(double v) {
    if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '₱${(v / 1000).toStringAsFixed(0)}k';
    return '₱${v.toStringAsFixed(0)}';
  }

  String _reportTypeLabel(_ReportType t) => switch (t) {
        _ReportType.financial => 'Financial Summary',
        _ReportType.community => 'Community Health',
        _ReportType.occupancy => 'Occupancy',
      };

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _dateFrom : _dateTo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  /// Builds the report PDF and opens the print dialog.
  Future<void> _exportPdf() async {
    setState(() => _generating = true);
    try {
      final doc = pw.Document();
      final metrics = _metrics;
      final chart = _chartData;
      final labels = _seriesLabels;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('NeighborSync -- ${_reportTypeLabel(_reportType)}',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                  '${_dateFrom.toIso8601String().split('T').first} to ${_dateTo.toIso8601String().split('T').first}',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),
              pw.Text('Metrics', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(children: [
                    _pdfCell('Metric', bold: true),
                    _pdfCell('Value', bold: true),
                  ]),
                  for (final m in metrics)
                    pw.TableRow(children: [_pdfCell(m.$1), _pdfCell(m.$2)]),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text('Monthly Trend (${labels.$1}${labels.$2.isNotEmpty ? ' vs ${labels.$2}' : ''})',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(children: [
                    _pdfCell('Month', bold: true),
                    _pdfCell(labels.$1, bold: true),
                    if (labels.$2.isNotEmpty) _pdfCell(labels.$2, bold: true),
                  ]),
                  for (final b in chart)
                    pw.TableRow(children: [
                      _pdfCell(b.label),
                      _pdfCell(b.seriesA.toStringAsFixed(0)),
                      if (labels.$2.isNotEmpty) _pdfCell(b.seriesB.toStringAsFixed(0)),
                    ]),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Text('Generated ${DateTime.now().toIso8601String().split('.').first} by NeighborSync Reports',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
        ),
      );
      // Log before the print dialog: it blocks, and cancelling still counts.
      await SupabaseService.instance.logAuditAction(
        'export',
        'reports',
        resource: _reportTypeLabel(_reportType),
      );

      await Printing.layoutPdf(onLayout: (format) => doc.save());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF export failed. ${friendlyError(e)}'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Reports & Analytics',
      activeItem: 'Reports',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Could not load reports: $_error',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 900;
                    final form = _buildForm();
                    final preview = _buildPreview();
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dashboardBand(),
                          const SizedBox(height: 28),
                          const Text('Report Builder',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(height: 16),
                          // Don't wrap this in IntrinsicHeight: the bar chart
                          // can't report one and Flutter web renders blank.
                          narrow
                              ? Column(children: [form, const SizedBox(height: 20), preview])
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 320, child: form),
                                    const SizedBox(width: 20),
                                    Expanded(child: preview),
                                  ],
                                ),
                        ],
                      ),
                    );
                  }),
                ),
    );
  }

  // ---- overview section (ignores the report type selector) ----

  double get _billedAll =>
      _bills.fold<double>(0, (s, b) => s + (num.tryParse(b['amount']?.toString() ?? '0') ?? 0));
  double get _collectedAll => _payments
      .where((p) => p['status'] == 'verified')
      .fold<double>(0, (s, p) => s + (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0));
  int get _collectionRatePct => _billedAll <= 0 ? 0 : ((_collectedAll / _billedAll) * 100).round();
  int get _openComplaints =>
      _complaints.where((c) => {'submitted', 'under_review', 'in_progress'}.contains(c['status'])).length;
  int get _openIncidents =>
      _incidents.where((i) => {'open', 'investigating'}.contains(i['status'])).length;
  int get _activePermits =>
      _permits.where((p) => {'submitted', 'under_review', 'approved'}.contains(p['status'])).length;

  /// Counts rows per value of [field].
  Map<String, int> _countBy(List<Map<String, dynamic>> rows, String field) {
    final m = <String, int>{};
    for (final r in rows) {
      final k = (r[field] ?? 'unknown').toString();
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  Widget _dashboardBand() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('A live snapshot across the community. Use the report builder below for a dated, exportable report.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        responsiveStatCards((w) => [
              DashboardStatCard(icon: Icons.people_outline, iconBg: const Color(0xFFE3F1E9), label: 'Residents + Tenants', value: '${_users.length}', width: w),
              DashboardStatCard(icon: Icons.savings_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Collection Rate', value: '$_collectionRatePct%', width: w),
              DashboardStatCard(icon: Icons.forum_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Open Complaints', value: '$_openComplaints', width: w),
              DashboardStatCard(icon: Icons.shield_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Open Incidents', value: '$_openIncidents', width: w),
              DashboardStatCard(icon: Icons.directions_car_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Registered Vehicles', value: '${_vehicles.where((v) => v['status'] == 'registered').length}', width: w),
              DashboardStatCard(icon: Icons.description_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Active Permits', value: '$_activePermits', width: w),
            ]),
        const SizedBox(height: 16),
        // On a phone the charts scroll sideways; cards are narrower than the
        // screen so the next one peeks in.
        LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          final w = narrow
              ? (constraints.maxWidth * 0.86).clamp(240.0, 340.0).toDouble()
              : 340.0;
          final cards = [
            _breakdownCard('Lots by status', _countBy(_lots, 'status'), w),
            _breakdownCard('Complaints by status', _countBy(_complaints, 'status'), w),
            _breakdownCard('Vehicles by status', _countBy(_vehicles, 'status'), w),
          ];
          if (!narrow) {
            return Wrap(spacing: 16, runSpacing: 16, children: cards);
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  cards[i],
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  /// A donut card showing the share of each status.
  Widget _breakdownCard(String title, Map<String, int> counts, [double width = 340]) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return SizedBox(
      width: width,
      child: ChartCard(
        title: title,
        series: const [],
        height: 150,
        isEmpty: entries.isEmpty,
        emptyMessage: 'No data yet.',
        chart: DonutChart(
          centerLabel: 'Total',
          slices: [
            for (var i = 0; i < entries.length; i++)
              DonutSlice(
                _titleCase(entries[i].key),
                entries[i].value.toDouble(),
                kSeriesColors[i % kSeriesColors.length],
              ),
          ],
        ),
      ),
    );
  }

  String _titleCase(String s) => s
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Generate Report', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 18),
          const Text('Report Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          DropdownButtonFormField<_ReportType>(
            initialValue: _reportType,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            items: _ReportType.values
                .where((t) => _allReports || t == _ReportType.financial)
                .map((t) => DropdownMenuItem(value: t, child: Text(_reportTypeLabel(t))))
                .toList(),
            onChanged: (v) => setState(() => _reportType = v ?? _reportType),
          ),
          const SizedBox(height: 16),
          const Text('Date From', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          _dateField(_dateFrom, () => _pickDate(isFrom: true)),
          const SizedBox(height: 16),
          const Text('Date To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          _dateField(_dateTo, () => _pickDate(isFrom: false)),
          const SizedBox(height: 16),
          const Text('Format', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.picture_as_pdf_outlined, size: 18, color: AppColors.textPrimary),
            SizedBox(width: 6),
            Text('PDF', style: TextStyle(fontSize: 13)),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _generating ? null : _exportPdf,
              child: Text(_generating ? 'Generating…' : 'Generate Report'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(DateTime value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 13)),
            const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  /// Turns the month buckets into chart series, dropping the second one
  /// when the report only has a single metric (occupancy).
  List<ChartSeries> _series(List<_MonthBucket> chart, (String, String) labels) {
    return [
      ChartSeries(
          label: labels.$1,
          color: kSeriesColors[0],
          values: [for (final b in chart) b.seriesA]),
      if (labels.$2.isNotEmpty)
        ChartSeries(
            label: labels.$2,
            color: kSeriesColors[1],
            values: [for (final b in chart) b.seriesB]),
    ];
  }

  Widget _buildPreview() {
    final chart = _chartData;
    final labels = _seriesLabels;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitleActionRow(
            title: const Text('Preview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            actions: [
              _legendDot(kSeriesColors[0], labels.$1),
              if (labels.$2.isNotEmpty) _legendDot(kSeriesColors[1], labels.$2),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: chart.isEmpty
                ? const Center(child: Text('No data in this range.', style: TextStyle(color: AppColors.textMuted)))
                // Money shows as a line; counts show as bars.
                : _reportType == _ReportType.financial
                    ? TrendLineChart(
                        labels: [for (final b in chart) b.label],
                        series: _series(chart, labels),
                        formatValue: _money,
                      )
                    : GroupedBarChart(
                        labels: [for (final b in chart) b.label],
                        series: _series(chart, labels),
                      ),
          ),
          const SizedBox(height: 24),
          const Row(children: [
            SizedBox(width: 180, child: Text('METRIC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            Expanded(child: Text('VALUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
          ]),
          const Divider(height: 24),
          for (final m in _metrics) ...[
            Row(children: [
              SizedBox(width: 180, child: Text(m.$1, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
              Expanded(child: Text(m.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
            ]),
            const Divider(height: 20),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _generating ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(_generating ? 'Generating…' : 'Export PDF'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
    ]);
  }
}
