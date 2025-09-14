import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'MapsPage.dart';
import 'complains.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String _username = '';

  @override
  void initState() {
    super.initState();
    fetchUsername();
  }

  void fetchUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _username = data?['username'] ?? 'User';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Good morning\n${_username.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Color(0xFFDAA8F4),
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
                          onSelected: (value) {},
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
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavIcon(
                      label: 'Map',
                      asset: 'map',
                      isSelected: false,
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MapsPage()),
                        );
                      },
                    ),
                    _NavIcon(
                      label: 'Complains',
                      asset: 'complains',
                      isSelected: false,
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ComplainsPage(),
                          ),
                        );
                      },
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
                const SizedBox(height: 30),
                Column(
                  children: const [
                    _StatCard(
                      value: '20',
                      label: 'Number of Dengue Patients in Sri Lanka',
                      iconPath: 'images/sl.ana.png',
                    ),
                    _StatCard(
                      value: '2',
                      label: 'Number of Dengue Patients in Your Area',
                      iconPath: 'images/map.ana.png',
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          tooltipBgColor: Colors.black,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              return const LineTooltipItem(
                                '83,234',
                                TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }).toList();
                          },
                        ),
                        getTouchedSpotIndicator: (barData, indexes) {
                          return indexes.map((index) {
                            return TouchedSpotIndicatorData(
                              FlLine(color: Colors.purple, strokeWidth: 1),
                              FlDotData(show: true),
                            );
                          }).toList();
                        },
                      ),
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(show: true),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            FlSpot(10, 40),
                            FlSpot(11, 60),
                            FlSpot(12, 45),
                            FlSpot(13, 58),
                            FlSpot(14, 62),
                            FlSpot(15, 50),
                            FlSpot(16, 83),
                            FlSpot(17, 55),
                            FlSpot(18, 65),
                            FlSpot(19, 58),
                            FlSpot(20, 52),
                            FlSpot(21, 54),
                            FlSpot(22, 59),
                            FlSpot(23, 60),
                            FlSpot(24, 58),
                          ],
                          isCurved: true,
                          color: Colors.purpleAccent,
                          belowBarData: BarAreaData(show: false),
                          dotData: FlDotData(show: true),
                          showingIndicators: [6],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'District        | Reported Dengue Cases (2023)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Divider(color: Colors.grey),
                _buildTableRow('Colombo', '17,803'),
                _buildTableRow('Gampaha', '18,401'),
                _buildTableRow('Kalutara', '5,122'),
                _buildTableRow('Kandy', '7,482'),
                _buildTableRow('Batticaloa', '2,818'),
                _buildTableRow('Jaffna', '2,157'),
                _buildTableRow('Galle', '315'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableRow(String district, String count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(district, style: const TextStyle(color: Colors.white)),
          Text(count, style: const TextStyle(color: Color(0xFFDAA8F4))),
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

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final String iconPath;

  const _StatCard({
    required this.value,
    required this.label,
    required this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        height: 100,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFCA9CDB),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              offset: const Offset(0, 4),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -22,
              right: -26,
              child: Container(
                width: 65,
                height: 65,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                child: Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFCA9CDB),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(iconPath, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 70,
                top: 20,
                bottom: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
