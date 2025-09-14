import 'package:buzzoff/Citizens/SigInPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ✅ NEW
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'complains.dart';
import 'analytics.dart';
import 'EditProfile.dart';

class MapsPage extends StatefulWidget {
  const MapsPage({super.key});

  @override
  State<MapsPage> createState() => _MapsPageState();
}

class _MapsPageState extends State<MapsPage> {
  int _currentPage = 0;
  final PageController _pageController = PageController();
  String _username = '';

  // ✅ NEW: map state
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  LatLng? _userLatLng;
  bool _inAnyZone = false;
  String? _userMoh;

  @override
  void initState() {
    super.initState();
    fetchUsername();
    _ensureLocationAndInit(); // ✅ start location + map flow
  }

  Future<void> fetchUsername() async {
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
          _userMoh = (data?['moh_area'] as String?)?.trim();
        });
      }
    }
  }

  // ---------- Map helpers (NEW) ----------
  Future<void> _ensureLocationAndInit() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied)
      p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever)
      return;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() => _userLatLng = LatLng(pos.latitude, pos.longitude));
    await _loadCasesAndRender();
  }

  Future<void> _loadCasesAndRender() async {
    // query dengue cases in same MOH; distance-check locally
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'dengue_cases',
    );
    if ((_userMoh ?? '').isNotEmpty)
      q = q.where('moh_area', isEqualTo: _userMoh);
    final snap = await q.get();

    final m = <Marker>{};
    final c = <Circle>{};
    bool inZone = false;

    for (final doc in snap.docs) {
      final d = doc.data();
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final casePos = LatLng(lat, lng);

      m.add(
        Marker(
          markerId: MarkerId('case_${doc.id}'),
          position: casePos,
          infoWindow: InfoWindow(
            title: 'Dengue case',
            snippet: (d['status'] ?? 'Reported').toString(),
          ),
        ),
      );

      c.add(
        Circle(
          circleId: CircleId('ring_${doc.id}'),
          center: casePos,
          radius: 300, // meters
          fillColor: const Color(0x44FF3B30),
          strokeColor: const Color(0xFFFF3B30),
          strokeWidth: 1,
        ),
      );

      if (_userLatLng != null) {
        final dist = Geolocator.distanceBetween(
          _userLatLng!.latitude,
          _userLatLng!.longitude,
          casePos.latitude,
          casePos.longitude,
        );
        if (dist <= 300) inZone = true;
      }
    }

    if (_userLatLng != null) {
      m.add(
        Marker(
          markerId: const MarkerId('me'),
          position: _userLatLng!,
          infoWindow: const InfoWindow(title: 'You are here'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(m);
      _circles
        ..clear()
        ..addAll(c);
      _inAnyZone = inZone;
    });

    if (_mapController != null && _userLatLng != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _userLatLng!, zoom: 15.5),
        ),
      );
    }
  }

  // ---------- Helpers ----------
  Color _statusBg(String s) {
    switch ((s).toLowerCase()) {
      case 'pending':
        return const Color(0xFF3A2A52);
      case 'review':
        return const Color(0xFF324559);
      case 'under investigation':
        return const Color(0xFF5A3D2E);
      case 'reviewed':
        return const Color(0xFF2F4A3A);
      default:
        return const Color(0xFF444444);
    }
  }

  Color _statusText(String s) {
    switch ((s).toLowerCase()) {
      case 'pending':
        return const Color(0xFFE4CCFF);
      case 'review':
        return const Color(0xFFBFD9FF);
      case 'under investigation':
        return const Color(0xFFF3D1B8);
      case 'reviewed':
        return const Color(0xFFBFE8CF);
      default:
        return Colors.white;
    }
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '-';
    return DateFormat('yyyy-MM-dd • HH:mm').format(ts.toDate());
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _statusBg(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _statusText(status),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  // ---------- Complaints Table ----------
  Widget _buildComplaintsTable() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    final stream = FirebaseFirestore.instance
        .collection('complaints')
        .where('uid', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        if (snap.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Failed to load your complaints.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                "You haven't made any complaints yet.",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        final rows = docs.map((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final ts = data['timestamp'] as Timestamp?;
          final desc = (data['description'] ?? '') as String;
          final moh = (data['moh_area'] ?? '-') as String;
          final loc = (data['location'] ?? '-') as String;
          final status = ((data['status'] ?? 'Pending') as String);
          final imageUrl = data['imageUrl'] as String?;

          return DataRow(
            cells: [
              DataCell(
                Text(_fmtTs(ts), style: const TextStyle(color: Colors.white)),
              ),
              DataCell(
                Tooltip(
                  message: desc,
                  child: SizedBox(
                    width: 220,
                    child: Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              DataCell(Text(moh, style: const TextStyle(color: Colors.white))),
              DataCell(
                SizedBox(
                  width: 160,
                  child: Text(
                    loc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              DataCell(_statusChip(status)),
              DataCell(
                imageUrl == null
                    ? const Text('-', style: TextStyle(color: Colors.white70))
                    : TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              backgroundColor: Colors.black,
                              child: InteractiveViewer(
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'View',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            ],
          );
        }).toList();

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2C2C35)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 68,
              columnSpacing: 20,
              headingTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              headingRowColor: WidgetStateColor.resolveWith(
                (_) => const Color(0xFF1C1C22),
              ),
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('MOH Area')),
                DataColumn(label: Text('Location')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Image')),
              ],
              rows: rows,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                      _ProfileMenu(
                        onEdit: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EditAccountPage(),
                            ),
                          );
                        },
                        onSignOut: () => _signOutAndGoToLogin(context),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 25),

              // Nav Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavIcon(
                    label: 'Map',
                    asset: 'map',
                    isSelected: true,
                    onTap: () {},
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
                    isSelected: false,
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AnalyticsPage(),
                        ),
                      );
                    },
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

              const Center(
                child: Text(
                  'SEE DENGUE PATIENTS CLOSE TO YOU',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ✅ REPLACED: static image → live Google Map + banner
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 320,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _userLatLng == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: _userLatLng!,
                                zoom: 15.5,
                              ),
                              onMapCreated: (c) => _mapController = c,
                              myLocationEnabled: true,
                              myLocationButtonEnabled: true,
                              zoomControlsEnabled: false,
                              compassEnabled: true,
                              mapToolbarEnabled: false,
                              markers: _markers,
                              circles: _circles,
                            ),
                    ),
                  ),
                  if (_inAnyZone) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F4A3A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF4D7A60)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You are within 300 m of a reported dengue case',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),

              // ---------- Your Complaints ----------
              const Text(
                'Your Complaints',
                style: TextStyle(
                  color: Color(0xFFDAA8F4),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildComplaintsTable(),

              const SizedBox(height: 28),

              // Tips Section (carousel)
              SizedBox(
                height: 170,
                child: Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: 13,
                        onPageChanged: (index) =>
                            setState(() => _currentPage = index),
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'images/tips${index + 1}.png',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        13,
                        (index) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

// ===== Pretty Profile Menu + Sign-out helper =====

enum _ProfileAction { edit, signOut }

Future<void> _signOutAndGoToLogin(BuildContext context) async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
  if (context.mounted) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SignInPage()),
      (_) => false,
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onSignOut;

  const _ProfileMenu({required this.onEdit, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ProfileAction>(
      tooltip: 'Profile menu',
      offset: const Offset(0, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2C2C35)),
      ),
      elevation: 6,
      color: const Color(0xFF16161C),
      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
      itemBuilder: (context) => [
        PopupMenuItem<_ProfileAction>(
          value: _ProfileAction.edit,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.edit_outlined, color: Colors.white),
            title: const Text(
              'Edit Profile',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Update your details',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            dense: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<_ProfileAction>(
          value: _ProfileAction.signOut,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFFF6B6B)),
            title: const Text(
              'Sign out',
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'See you soon! 👋',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            dense: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case _ProfileAction.edit:
            onEdit();
            break;
          case _ProfileAction.signOut:
            onSignOut();
            break;
        }
      },
    );
  }
}
