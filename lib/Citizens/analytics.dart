import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'MapsPage.dart';
import 'complains.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String _username = '';
  String? _mohArea; // from users.moh_area

  // chart / KPI controls
  int _rangeDays = 90; // 30 or 90
  bool _showMA = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _fetchUser();
    setState(() {});
  }

  Future<void> _fetchUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!doc.exists) return;
    final data = doc.data();
    setState(() {
      _username = (data?['username'] ?? 'User').toString();
      _mohArea = (data?['moh_area'] ?? '').toString().trim().isEmpty
          ? null
          : (data?['moh_area'] as String);
    });
  }

  Color _statusColor(String level) {
    switch (level.toLowerCase()) {
      case 'red':
        return const Color(0xFFFF5A5A);
      case 'amber':
        return const Color(0xFFFFC857);
      case 'green':
        return const Color(0xFF45D483);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = const Color(0xFFDAA8F4);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0615), Color(0xFF1C0E22)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Good morning\n${_username.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 20,
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundImage: AssetImage('images/pfp.png'),
                          radius: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _username,
                          style: const TextStyle(color: Colors.white),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                          ),
                          color: Colors.grey[900],
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit Profile'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete Profile'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ---- Nav
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavIcon(
                      label: 'Map',
                      asset: 'map',
                      isSelected: false,
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const MapsPage()),
                      ),
                    ),
                    _NavIcon(
                      label: 'Complains',
                      asset: 'complains',
                      isSelected: false,
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ComplainsPage(),
                        ),
                      ),
                    ),
                    _NavIcon(
                      label: 'Analytics',
                      asset: 'analytics',
                      isSelected: true,
                      onTap: () {},
                    ),
                    _NavIcon(
                      label: 'Fines',
                      asset: 'fines_and_payments',
                      isSelected: false,
                      onTap: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 1) Outbreak Status (same logic)
                _OutbreakStatusFromMohActions(
                  mohArea: _mohArea,
                  colorFor: _statusColor,
                ),

                const SizedBox(height: 16),

                // 2) KPIs (UPDATED: cases in my area + cases in Sri Lanka)
                _KpisAreaAndNational(mohArea: _mohArea, rangeDays: _rangeDays),

                const SizedBox(height: 16),

                // 3) Trend: Daily New Cases (FIXED styling)
                _TrendFromMohActions(
                  mohArea: _mohArea,
                  rangeDays: _rangeDays,
                  showMA: _showMA,
                  onRangeChanged: (d) => setState(() => _rangeDays = d),
                  onMAChanged: (v) => setState(() => _showMA = v),
                ),

                const SizedBox(height: 16),

                // 4) Advisory (text only)
                _AdvisoryCard(mohArea: _mohArea),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// OUTBREAK (unchanged logic)
// ---------------------------------------------------------
// OUTBREAK — clearer & larger layout
class _OutbreakStatusFromMohActions extends StatelessWidget {
  final String? mohArea;
  final Color Function(String) colorFor;
  const _OutbreakStatusFromMohActions({
    required this.mohArea,
    required this.colorFor,
  });

  @override
  Widget build(BuildContext context) {
    if (mohArea == null) {
      return _ShellCard(
        title: 'Outbreak Status',
        child: _EmptyText('Set your MOH area in profile to see local status'),
      );
    }

    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final last7Start = today0.subtract(const Duration(days: 6));
    final prev7Start = today0.subtract(const Duration(days: 13));
    final prev7End = today0.subtract(const Duration(days: 7));

    final q = FirebaseFirestore.instance
        .collection('moh_actions')
        .where('action', isEqualTo: 'new_case')
        .where('patient_moh_area', isEqualTo: mohArea)
        .where(
          'date_of_admission',
          isGreaterThanOrEqualTo: Timestamp.fromDate(prev7Start),
        );

    String fmtRange(DateTime a, DateTime b) =>
        '${DateFormat.MMMd().format(a)}–${DateFormat.MMMd().format(b)}';

    return _Card(
      title: 'Outbreak Status — $mohArea',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          int last7 = 0, prev7 = 0;
          if (snap.hasData) {
            for (final doc in snap.data!.docs) {
              final ts = doc.data()['date_of_admission'];
              final dt = (ts is Timestamp)
                  ? ts.toDate()
                  : DateTime.tryParse('$ts');
              if (dt == null) continue;
              final d0 = DateTime(dt.year, dt.month, dt.day);
              if (d0.isAfter(last7Start.subtract(const Duration(days: 1)))) {
                last7++;
              } else if (!d0.isAfter(prev7End)) {
                prev7++;
              }
            }
          }

          // thresholds
          String level = 'Green';
          if (last7 >= 20 || (prev7 > 0 && (last7 - prev7) / prev7 >= 0.5)) {
            level = 'Red';
          } else if (last7 >= 10 ||
              (prev7 > 0 && (last7 - prev7) / prev7 >= 0.1)) {
            level = 'Amber';
          }

          final c = colorFor(level);
          final deltaPct = (prev7 == 0)
              ? null
              : ((last7 - prev7) / prev7.toDouble()) * 100;
          final deltaText = deltaPct == null
              ? '—'
              : '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}%';
          final IconData deltaIcon = deltaPct == null
              ? Icons.horizontal_rule
              : (deltaPct >= 0 ? Icons.arrow_upward : Icons.arrow_downward);
          final Color deltaColor = deltaPct == null
              ? Colors.white70
              : (deltaPct >= 0
                    ? const Color(0xFFFF5A5A)
                    : const Color(0xFF45D483));

          String tagline;
          switch (level) {
            case 'Red':
              tagline = 'High activity — take precautions today.';
              break;
            case 'Amber':
              tagline = 'Rising activity — be extra careful.';
              break;
            default:
              tagline = 'Low activity — keep habitats dry.';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: big status pill + tagline
              Row(
                children: [
                  _StatusPill(level: level, color: c),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tagline,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Row 2: three metric boxes
              Row(
                children: [
                  Expanded(
                    child: _MetricBox(label: 'Last 7 days', value: '$last7'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricBox(
                      label: 'Previous 7 days',
                      value: '$prev7',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricBox(
                      label: 'Change',
                      value: deltaText,
                      icon: deltaIcon,
                      iconColor: deltaColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Row 3: exact date ranges for clarity
              Text(
                '${fmtRange(last7Start, today0)} vs ${fmtRange(prev7Start, prev7End)}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }
}

// pill like [ ● RED ]
class _StatusPill extends StatelessWidget {
  final String level;
  final Color color;
  const _StatusPill({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            level.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// little metric card used inside the status card
class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  const _MetricBox({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A21),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242A36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    icon,
                    size: 16,
                    color: iconColor ?? Colors.white70,
                  ),
                ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// KPIs (UPDATED):
//   - Cases in my area (last X days)
//   - Cases in Sri Lanka (all-time)
// ---------------------------------------------------------
class _KpisAreaAndNational extends StatelessWidget {
  final String? mohArea;
  final int rangeDays;
  const _KpisAreaAndNational({required this.mohArea, required this.rangeDays});

  @override
  Widget build(BuildContext context) {
    if (mohArea == null) {
      return _ShellCard(title: 'KPIs', child: _EmptyText('Set MOH area'));
    }

    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: rangeDays - 1));

    // My area, last X days
    final myAreaQ = FirebaseFirestore.instance
        .collection('moh_actions')
        .where('action', isEqualTo: 'new_case')
        .where('patient_moh_area', isEqualTo: mohArea)
        .where(
          'date_of_admission',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .orderBy('date_of_admission'); // <- needs the composite index

    // Sri Lanka total (all-time) – aggregate count
    final nationalCountQ = FirebaseFirestore.instance
        .collection('moh_actions')
        .where('action', isEqualTo: 'new_case')
        .count();

    return Row(
      children: [
        // Cases in my area (last X days)
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: myAreaQ.snapshots(),
            builder: (context, snap) {
              final n = snap.hasData ? snap.data!.docs.length : 0;
              return _MiniKpiCard(
                title: 'Cases in my area',
                value: '$n',
                subtitle: 'Last $rangeDays days',
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        // Cases in Sri Lanka (all-time total)
        Expanded(
          child: FutureBuilder<AggregateQuerySnapshot>(
            future: nationalCountQ.get(),
            builder: (context, snap) {
              final total = (snap.hasData ? snap.data!.count : null);
              return _MiniKpiCard(
                title: 'Cases in Sri Lanka',
                value: total == null ? '—' : '$total',
                subtitle: 'All-time total',
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------
// TREND (FIXED look & ticks)
// ---------------------------------------------------------
class _TrendFromMohActions extends StatelessWidget {
  final String? mohArea;
  final int rangeDays;
  final bool showMA;
  final ValueChanged<int> onRangeChanged;
  final ValueChanged<bool> onMAChanged;

  const _TrendFromMohActions({
    required this.mohArea,
    required this.rangeDays,
    required this.showMA,
    required this.onRangeChanged,
    required this.onMAChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (mohArea == null) {
      return _ShellCard(
        title: 'Daily New Cases',
        child: _EmptyText('Set MOH area'),
      );
    }

    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: (rangeDays - 1)));
    final q = FirebaseFirestore.instance
        .collection('moh_actions')
        .where('action', isEqualTo: 'new_case')
        .where('patient_moh_area', isEqualTo: mohArea)
        .where(
          'date_of_admission',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .orderBy('date_of_admission'); // composite index needed

    return _Card(
      title: 'Daily New Cases',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceChip(
            label: const Text('30d'),
            selected: rangeDays == 30,
            onSelected: (_) => onRangeChanged(30),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('90d'),
            selected: rangeDays == 90,
            onSelected: (_) => onRangeChanged(90),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              const Text('7d MA', style: TextStyle(color: Colors.white70)),
              Switch(value: showMA, onChanged: onMAChanged),
            ],
          ),
        ],
      ),
      child: SizedBox(
        height: 230,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(),
          builder: (context, snap) {
            // bucket by day
            final counts = <DateTime, int>{};
            if (snap.hasData) {
              for (final doc in snap.data!.docs) {
                final ts = doc.data()['date_of_admission'];
                final dt = (ts is Timestamp)
                    ? ts.toDate()
                    : DateTime.tryParse('$ts');
                if (dt == null) continue;
                final d0 = DateTime(dt.year, dt.month, dt.day);
                counts[d0] = (counts[d0] ?? 0) + 1;
              }
            }
            final days = List<DateTime>.generate(
              rangeDays,
              (i) => DateTime(
                start.year,
                start.month,
                start.day,
              ).add(Duration(days: i)),
            );
            final values = days
                .map((d) => (counts[d] ?? 0).toDouble())
                .toList();

            // build spots
            final spots = <FlSpot>[];
            for (int i = 0; i < values.length; i++) {
              spots.add(FlSpot(i.toDouble(), values[i]));
            }

            // moving average
            final maSpots = <FlSpot>[];
            if (showMA && values.length >= 7) {
              final ma = _movingAverage(values, 7);
              for (int i = 0; i < ma.length; i++) {
                maSpots.add(FlSpot(i.toDouble(), ma[i]));
              }
            }

            // nicer axes
            final maxY = (values.isEmpty
                ? 1.0
                : values.reduce((a, b) => a > b ? a : b));
            final paddedMaxY = maxY <= 1 ? 3.5 : (maxY + (maxY * 0.25));

            String labelForX(double x) {
              final idx = x.round().clamp(0, days.length - 1);
              return DateFormat('MMM d').format(days[idx]); // e.g., "Sep 10"
            }

            return LineChart(
              LineChartData(
                minX: 0,
                maxX: (rangeDays - 1).toDouble(),
                minY: 0,
                maxY: paddedMaxY, // <- padding so tall spikes look good
                clipData: const FlClipData.all(), // avoid overdraw on edges
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: const Color(0xFF171A21),
                    getTooltipItems: (ts) => ts
                        .map(
                          (s) => LineTooltipItem(
                            '${labelForX(s.x)}\n${s.y.toStringAsFixed(0)} cases',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  getTouchedSpotIndicator: (bar, idxs) => idxs
                      .map(
                        (_) => TouchedSpotIndicatorData(
                          FlLine(color: Colors.white24, strokeWidth: 1),
                          FlDotData(
                            show: true,
                            getDotPainter: (s, p, b, i2) => FlDotCirclePainter(
                              radius: 3,
                              strokeWidth: 2,
                              color: Colors.white,
                              strokeColor: Colors.purpleAccent,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _niceYInterval(spots),
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.white12, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32, // more space so labels don’t collide
                      interval: (rangeDays / 4)
                          .floorToDouble()
                          .clamp(1, 999)
                          .toDouble(),
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labelForX(value),
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: _niceYInterval(spots),
                      getTitlesWidget: (v, m) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  // main series with gradient fill
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.purpleAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    preventCurveOverShooting: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.purpleAccent.withOpacity(0.25),
                          Colors.purpleAccent.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                  if (maSpots.isNotEmpty)
                    LineChartBarData(
                      spots: maSpots,
                      isCurved: true,
                      color: Colors.white70,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static double _niceYInterval(List<FlSpot> spots) {
    if (spots.isEmpty) return 1;
    final maxY = spots.map((e) => e.y).fold<double>(0, (m, v) => v > m ? v : m);
    final raw = (maxY / 4).clamp(1, 1000);
    if (raw <= 5) return 1;
    if (raw <= 10) return 2;
    if (raw <= 25) return 5;
    if (raw <= 50) return 10;
    if (raw <= 100) return 20;
    return 50;
  }

  static List<double> _movingAverage(List<double> v, int w) {
    final out = <double>[];
    double sum = 0;
    for (int i = 0; i < v.length; i++) {
      sum += v[i];
      if (i >= w) sum -= v[i - w];
      final denom = (i + 1) < w ? (i + 1) : w;
      out.add(sum / denom);
    }
    return out;
  }
}

// ---------------------------------------------------------
// Advisory (text only)
// ---------------------------------------------------------
class _AdvisoryCard extends StatelessWidget {
  final String? mohArea;
  const _AdvisoryCard({required this.mohArea});

  @override
  Widget build(BuildContext context) {
    if (mohArea == null) {
      return _ShellCard(
        title: 'Advisory',
        child: _EmptyText('Set your MOH area to see the current advisory'),
      );
    }

    final docRef = FirebaseFirestore.instance
        .collection('moh_contacts')
        .doc(mohArea);
    return _Card(
      title: 'Advisory',
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          String advisory =
              'Keep your home dry: empty trays, cover tanks, use repellent.';
          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data()!;
            if (d['advisory'] is String &&
                d['advisory'].toString().trim().isNotEmpty) {
              advisory = d['advisory'];
            }
          }
          return Text(advisory, style: const TextStyle(color: Colors.white70));
        },
      ),
    );
  }
}

// ---------------------------------------------------------
// Reusable shells
// ---------------------------------------------------------
class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Card({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cardColor = const Color(0xFF171A21);
    final border = const Color(0xFF242A36);
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ShellCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ShellCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final cardColor = const Color(0xFF171A21);
    final border = const Color(0xFF242A36);
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String msg;
  const _EmptyText(this.msg);
  @override
  Widget build(BuildContext context) {
    return Text(msg, style: const TextStyle(color: Colors.white54));
  }
}

class _MiniKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  const _MiniKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = const Color(0xFF171A21);
    final border = const Color(0xFF242A36);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final String label;
  final String asset;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavIcon({
    required this.label,
    required this.asset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLightBox = !isSelected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 90,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D1237) : const Color(0xFFCA9CDB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/$asset.png', width: 38, height: 38),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isLightBox ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
