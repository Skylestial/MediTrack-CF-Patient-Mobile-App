import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/medicine_service.dart';
import '../models/daily_log.dart';
import '../services/risk_service.dart';

class GraphsScreen extends StatefulWidget {
  const GraphsScreen({super.key});

  @override
  State<GraphsScreen> createState() => _GraphsScreenState();
}

class _GraphsScreenState extends State<GraphsScreen> {
  final _authService = AuthService();
  late MedicineService _medicineService;
  List<DailyLog> _logs = [];
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    final userId = _authService.currentUserId;
    if (userId != null) {
      _medicineService = MedicineService(userId);
      _loadData();
    }
  }

  void _loadData() {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: _selectedDays - 1));
    _medicineService
        .getDailyLogsStream(
          DateFormat('yyyy-MM-dd').format(startDate),
          DateFormat('yyyy-MM-dd').format(endDate),
        )
        .listen((logs) {
      if (mounted) setState(() => _logs = logs);
    });
  }

  Color _riskColor(int adherence) {
    final risk = RiskService.calculateRisk(adherence);
    switch (risk) {
      case RiskLevel.low:      return Colors.green;
      case RiskLevel.moderate: return Colors.amber;
      case RiskLevel.high:     return Colors.red;
    }
  }

  double _getAverageAdherence() {
    if (_logs.isEmpty) return 0;
    return _logs.fold<int>(0, (s, l) => s + l.adherence) / _logs.length;
  }

  /// Only plot days that have actual log data (no fake zeros)
  List<FlSpot> _getSpots() {
    final startDate = DateTime.now().subtract(Duration(days: _selectedDays - 1));
    final logMap = {for (final l in _logs) l.date: l};
    final spots = <FlSpot>[];
    for (int i = 0; i < _selectedDays; i++) {
      final date = startDate.add(Duration(days: i));
      final log = logMap[DateFormat('yyyy-MM-dd').format(date)];
      if (log != null) spots.add(FlSpot(i.toDouble(), log.adherence.toDouble()));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final average = _getAverageAdherence();
    final risk = RiskService.calculateRisk(average.round());
    final spots = _getSpots();
    final startDate = DateTime.now().subtract(Duration(days: _selectedDays - 1));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final axisColor = isDark ? Colors.white70 : Colors.black54;
    final gridColor = isDark ? Colors.white12 : Colors.black12;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // â”€â”€ Period selector â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _periodChip('7 Days', 7),
              const SizedBox(width: 8),
              _periodChip('30 Days', 30),
            ],
          ),
          const SizedBox(height: 20),

          // â”€â”€ Average adherence card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Card(
            elevation: 0,
            color: _riskColor(average.round()).withAlpha(25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(children: [
                Text('Average Adherence',
                    style: TextStyle(fontSize: 14, color: axisColor)),
                const SizedBox(height: 6),
                Text('${average.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: _riskColor(average.round()),
                    )),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: _riskColor(average.round()),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    risk == RiskLevel.low
                        ? 'Low Risk'
                        : risk == RiskLevel.moderate
                            ? 'Moderate Risk'
                            : 'High Risk',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          // â”€â”€ Line chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Text('Daily Adherence',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d').format(DateTime.now())}',
            style: TextStyle(fontSize: 12, color: axisColor),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: spots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart_rounded,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text('No adherence data yet'),
                      ],
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (_selectedDays - 1).toDouble(),
                      minY: 0,
                      maxY: 100,
                      clipData: const FlClipData.all(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: Colors.indigo,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, ___) =>
                                FlDotCirclePainter(
                              radius: 5,
                              color: _riskColor(spot.y.round()),
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                Colors.indigo.withAlpha(60),
                                Colors.indigo.withAlpha(0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                      // â”€â”€ Reference lines at thresholds â”€â”€
                      extraLinesData: ExtraLinesData(horizontalLines: [
                        HorizontalLine(
                          y: 80,
                          color: Colors.green.withAlpha(120),
                          strokeWidth: 1.2,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.only(right: 4, bottom: 2),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.green),
                            labelResolver: (_) => '80% Low',
                          ),
                        ),
                        HorizontalLine(
                          y: 50,
                          color: Colors.amber.withAlpha(120),
                          strokeWidth: 1.2,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.only(right: 4, bottom: 2),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.amber),
                            labelResolver: (_) => '50% Mod',
                          ),
                        ),
                      ]),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 46,
                            interval: 25,
                            getTitlesWidget: (value, _) => Text(
                              '${value.toInt()}%',
                              style: TextStyle(fontSize: 11, color: axisColor),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: _selectedDays <= 7 ? 1 : 5,
                            getTitlesWidget: (value, meta) {
                              final date = startDate
                                  .add(Duration(days: value.toInt()));
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(
                                  DateFormat(_selectedDays <= 7 ? 'E' : 'M/d')
                                      .format(date),
                                  style: TextStyle(
                                      fontSize: 10, color: axisColor),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: gridColor, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(color: gridColor, width: 1),
                          left: BorderSide(color: gridColor, width: 1),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          tooltipBgColor: Colors.black87,
                          getTooltipItems: (spots) => spots.map((s) {
                            final date = startDate
                                .add(Duration(days: s.x.toInt()));
                            return LineTooltipItem(
                              '${DateFormat('MMM d').format(date)}\n',
                              const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                              children: [
                                TextSpan(
                                  text: '${s.y.toInt()}%',
                                  style: TextStyle(
                                    color: _riskColor(s.y.round()),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                )
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // â”€â”€ Legend â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem('Low Risk\n(>80%)', Colors.green),
              _legendItem('Moderate Risk\n(50-79%)', Colors.amber),
              _legendItem('High Risk\n(<50%)', Colors.red),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _periodChip(String label, int days) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedDays == days,
      onSelected: (on) {
        if (on) {
          setState(() => _selectedDays = days);
          _loadData();
        }
      },
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }
}
