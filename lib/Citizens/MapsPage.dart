import 'dart:async';
import 'package:buzzoff/Citizens/SigInPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:intl/intl.dart';
import 'complains.dart';
import 'analytics.dart';
import 'EditProfile.dart';

// ====== Small model for resolved case points ======
class CasePoint {
  final String id;
  final LatLng pos;
  final DateTime? admissionDate;
  final String status;
  final String debugSource; // GeoPoint | lat/lng | geocode
  CasePoint(
    this.id,
    this.pos,
    this.admissionDate,
    this.status,
    this.debugSource,
  );
}

class MapsPage extends StatefulWidget {
  const MapsPage({super.key});

  @override
  State<MapsPage> createState() => _MapsPageState();
}

class _MapsPageState extends State<MapsPage> {
  // Tips carousel state (no full rebuilds)
  final PageController _pageController = PageController();
  final ValueNotifier<int> _tipsPage = ValueNotifier<int>(0);

  String _username = '';

  GoogleMapController? _mapCtrl;

  // Location sources
  LatLng? _userLatLng; // from device GPS
  bool _locDenied = false;

  String? _profileAddress; // from users collection
  LatLng? _addrLatLng; // geocoded address
  bool _addrGeocodeFailed = false;

  // Toggle: false = current location, true = profile address
  bool _useProfileAddress = false;

  // cache: address/adress string -> LatLng (avoid re-geocoding)
  final Map<String, LatLng> _geoCache = {};

  @override
  void initState() {
    super.initState();
    _fetchUserProfileAndAddress();
    _bootstrapGps();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tipsPage.dispose();
    super.dispose();
  }

  // ---------- Init helpers ----------
  Future<void> _bootstrapGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locDenied = true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _userLatLng = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      _locDenied = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchUserProfileAndAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!doc.exists) return;
    final data = doc.data();
    setState(() => _username = (data?['username'] as String?) ?? 'User');

    // read address/adress
    final addrRaw = (data?['address'] ?? data?['adress'])?.toString();
    if (addrRaw != null && addrRaw.trim().isNotEmpty) {
      _profileAddress = addrRaw.trim();
      final p = await _geocodeAddress(_profileAddress!);
      setState(() {
        _addrLatLng = p;
        _addrGeocodeFailed = p == null;
      });
    }
  }

  // ---------- Helpers ----------
  Color _statusBg(String s) {
    switch (s.toLowerCase()) {
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
    switch (s.toLowerCase()) {
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

  String _fmt(DateTime? dt) =>
      dt == null ? '-' : DateFormat('yyyy-MM-dd • HH:mm').format(dt);

  Widget _statusChip(String status) => Container(
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

  // Firestore stream
  Stream<QuerySnapshot<Map<String, dynamic>>> _casesStreamRaw() {
    return FirebaseFirestore.instance
        .collection('dengue_cases')
        .limit(200)
        .snapshots();
  }

  // Convert any date shape (Timestamp | int(s/ms) | ISO string) to DateTime
  DateTime? _toDate(dynamic v) {
    try {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is int) {
        if (v > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(v);
        if (v > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(v * 1000);
        }
        return null;
      }
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          for (final fmt in [
            'yyyy/MM/dd HH:mm',
            'yyyy-MM-dd HH:mm',
            'yyyy/MM/dd',
            'yyyy-MM-dd',
          ]) {
            try {
              return DateFormat(fmt).parse(v);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // Geocode address/adress with Sri Lanka bias + cache
  Future<LatLng?> _geocodeAddress(String raw) async {
    final key = raw.trim();
    if (key.isEmpty) return null;
    if (_geoCache.containsKey(key)) return _geoCache[key];

    Future<LatLng?> tryQuery(String q) async {
      try {
        final locs = await geocoding.locationFromAddress(q);
        if (locs.isNotEmpty) {
          return LatLng(locs.first.latitude, locs.first.longitude);
        }
      } catch (_) {}
      return null;
    }

    LatLng? p = await tryQuery('$key, Sri Lanka');
    p ??= await tryQuery(key);

    // small dev fallback for Gothami typo testing
    if (p == null && key.toLowerCase().contains('gothami')) {
      p = const LatLng(6.9029, 79.8762);
    }

    if (p != null) _geoCache[key] = p;
    return p;
  }

  Future<List<CasePoint>> _resolveCasePoints(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final out = <CasePoint>[];

    for (final d in docs) {
      final data = d.data();
      LatLng? pos;
      var src = 'unknown';

      // 1) GeoPoint field 'location'
      final loc = data['location'];
      if (loc is GeoPoint) {
        pos = LatLng(loc.latitude, loc.longitude);
        src = 'GeoPoint';
      }

      // 2) Numeric 'lat'/'lng'
      if (pos == null) {
        final lat = data['lat'];
        final lng = data['lng'];
        if (lat is num && lng is num) {
          pos = LatLng(lat.toDouble(), lng.toDouble());
          src = 'lat/lng';
        }
      }

      // 3) Geocode 'address' or 'adress'
      if (pos == null) {
        final a = (data['address'] ?? data['adress'])?.toString() ?? '';
        if (a.trim().isNotEmpty) {
          final g = await _geocodeAddress(a);
          if (g != null) {
            pos = g;
            src = 'geocode';
          }
        }
      }

      if (pos == null) continue;

      // Use date_of_admission (fallback to timestamp if present)
      final dt = _toDate(data['date_of_admission'] ?? data['timestamp']);
      final status = (data['status'] ?? 'Reported').toString();
      out.add(CasePoint(d.id, pos, dt, status, src));
    }

    return out;
  }

  // Active center based on toggle
  LatLng? _activeCenter() {
    if (_useProfileAddress) return _addrLatLng ?? _userLatLng;
    return _userLatLng;
  }

  // Fit camera to include a set of points (handles single-point safely)
  Future<void> _fitToAll(Iterable<LatLng> points) async {
    if (_mapCtrl == null) return;
    final pts = points.toList();
    if (pts.isEmpty) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final sameLat = (minLat == maxLat);
    final sameLng = (minLng == maxLng);
    await Future.delayed(const Duration(milliseconds: 200));
    if (sameLat && sameLng) {
      await _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 14.5),
      );
    } else {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      await _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }
  }

  // ---------- Map section ----------
  Widget _buildMapSection() {
    final center = _activeCenter();

    // If toggle is "current location" and permission denied, hint user to use address toggle
    final showPermWarning = !_useProfileAddress && _locDenied && center == null;

    // Loading state until we have *some* center to show
    if (center == null && !showPermWarning) {
      return _panel(
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    // If we can’t get a center due to denied GPS and no address, show hint panel
    if (showPermWarning) {
      return _panel(
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Location permission denied and no profile address found.\nSwitch the toggle to "Profile Address" after adding an address in your profile.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final myPos = center!;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _casesStreamRaw(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final hasError = snap.hasError;

        // Build sets & banner message
        final Set<Marker> markers = {};
        final Set<Circle> circles = {};
        String? bannerMsg;
        bool insideAny = false;

        // User marker (keep this)
        markers.add(
          Marker(
            markerId: const MarkerId('me'),
            position: myPos,
            infoWindow: InfoWindow(
              title: _useProfileAddress ? 'Your Address' : 'You',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _useProfileAddress
                  ? BitmapDescriptor.hueViolet
                  : BitmapDescriptor.hueAzure,
            ),
          ),
        );

        // Ensure initial camera centers to the active source
        Future<void>.microtask(() async {
          if (_mapCtrl != null) {
            await _mapCtrl!.moveCamera(CameraUpdate.newLatLngZoom(myPos, 14.5));
          }
        });

        if (hasError) {
          bannerMsg = 'Failed to load dengue cases.';
        } else if (!loading) {
          final allDocs = snap.data?.docs ?? [];

          // Client-side month window using date_of_admission
          final now = DateTime.now();
          final monthStart = DateTime(now.year, now.month, 1);
          final monthEnd = (now.month == 12)
              ? DateTime(now.year + 1, 1, 1)
              : DateTime(now.year, now.month + 1, 1);

          final docs = allDocs.where((d) {
            final dt = _toDate(
              d.data()['date_of_admission'] ?? d.data()['timestamp'],
            );
            return dt != null &&
                !dt.isBefore(monthStart) &&
                dt.isBefore(monthEnd);
          }).toList();

          return FutureBuilder<List<CasePoint>>(
            future: _resolveCasePoints(docs),
            builder: (context, fb) {
              final resolving = fb.connectionState != ConnectionState.done;
              final points = fb.data ?? [];

              if (!resolving) {
                if (points.isEmpty) {
                  bannerMsg = 'No dengue cases found this month.';
                } else {
                  // Draw ONLY circles (no red markers)
                  const radiusM = 300.0;
                  for (final cp in points) {
                    circles.add(
                      Circle(
                        circleId: CircleId('c_${cp.id}'),
                        center: cp.pos,
                        radius: radiusM,
                        fillColor: const Color(0x22FF5252),
                        strokeColor: const Color(0xFFFF5252),
                        strokeWidth: 2,
                      ),
                    );

                    final dist = Geolocator.distanceBetween(
                      myPos.latitude,
                      myPos.longitude,
                      cp.pos.latitude,
                      cp.pos.longitude,
                    );
                    if (dist <= radiusM) insideAny = true;
                  }

                  // Fit camera to all once after create
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (_mapCtrl != null) {
                      await _fitToAll([myPos, ...points.map((e) => e.pos)]);
                    }
                  });
                }
              }

              final camPos = CameraPosition(target: myPos, zoom: 14.5);

              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: GoogleMap(
                      initialCameraPosition: camPos,
                      myLocationEnabled: !_useProfileAddress, // only when GPS
                      myLocationButtonEnabled: false,
                      compassEnabled: true,
                      zoomGesturesEnabled: true,
                      zoomControlsEnabled: false, // custom buttons below
                      markers: markers,
                      circles: circles,
                      mapToolbarEnabled: false,
                      onMapCreated: (c) async {
                        _mapCtrl = c;
                      },
                    ),
                  ),

                  // Warning if inside any 300m circle
                  if (insideAny)
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: _alertBanner(
                        "⚠️ You are within 300 m of a reported dengue case.",
                      ),
                    ),

                  // Info banner (errors / no data / loading)
                  if (bannerMsg != null)
                    Positioned(
                      top: insideAny ? 56 : 10,
                      left: 10,
                      right: 10,
                      child: _infoBanner(bannerMsg!),
                    ),

                  // Zoom & recenter controls
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Column(
                      children: [
                        _roundMapBtn(
                          icon: Icons.add,
                          tooltip: 'Zoom in',
                          onTap: _zoomIn,
                        ),
                        const SizedBox(height: 8),
                        _roundMapBtn(
                          icon: Icons.remove,
                          tooltip: 'Zoom out',
                          onTap: _zoomOut,
                        ),
                        const SizedBox(height: 8),
                        _roundMapBtn(
                          icon: Icons.my_location,
                          tooltip: 'Re-center',
                          onTap: () async {
                            if (_mapCtrl != null) {
                              await _mapCtrl!.animateCamera(
                                CameraUpdate.newLatLngZoom(myPos, 15),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        }

        // Loading/initial map (still explorable)
        final camPos = CameraPosition(target: myPos, zoom: 14.5);

        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GoogleMap(
                initialCameraPosition: camPos,
                myLocationEnabled: !_useProfileAddress,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                zoomGesturesEnabled: true,
                zoomControlsEnabled: false,
                markers: markers,
                circles: circles,
                mapToolbarEnabled: false,
                onMapCreated: (c) async {
                  _mapCtrl = c;
                },
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: _infoBanner('Loading dengue cases…'),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Column(
                children: [
                  _roundMapBtn(
                    icon: Icons.add,
                    tooltip: 'Zoom in',
                    onTap: _zoomIn,
                  ),
                  const SizedBox(height: 8),
                  _roundMapBtn(
                    icon: Icons.remove,
                    tooltip: 'Zoom out',
                    onTap: _zoomOut,
                  ),
                  const SizedBox(height: 8),
                  _roundMapBtn(
                    icon: Icons.my_location,
                    tooltip: 'Re-center',
                    onTap: () async {
                      if (_mapCtrl != null) {
                        await _mapCtrl!.animateCamera(
                          CameraUpdate.newLatLngZoom(myPos, 15),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Map UI helpers
  Widget _roundMapBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: const Color(0xFF1F1F27),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Future<void> _zoomIn() async {
    if (_mapCtrl == null) return;
    await _mapCtrl!.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    if (_mapCtrl == null) return;
    await _mapCtrl!.animateCamera(CameraUpdate.zoomOut());
  }

  Widget _panel(Widget child) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF16161C),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF2C2C35)),
    ),
    height: 320,
    child: child,
  );

  Widget _alertBanner(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3CD),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFEEBA)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF856404),
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.center,
    ),
  );

  Widget _infoBanner(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF334155)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
    ),
  );

  // ---------- Complaints as CARDS (only this user's) ----------
  Color _complaintStatusColor(String s) {
    final v = s.toLowerCase().trim();
    if (v == 'reviewed') return const Color(0xFF22C55E); // green
    if (v == 'pending') return const Color(0xFFEF4444); // red
    if (v == 'under review' || v == 'review' || v == 'under investigation') {
      return const Color(0xFFF59E0B); // yellow/amber
    }
    return const Color(0xFF64748B); // default slate
  }

  Color _complaintStatusTextColor(String s) {
    final bg = _complaintStatusColor(s).value;
    // yellow gets dark text, others get white
    if (bg == const Color(0xFFF59E0B).value) return Colors.black;
    return Colors.white;
  }

  Widget _buildComplaintsCards() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    final stream = FirebaseFirestore.instance
        .collection('complaints')
        .where('uid', isEqualTo: user.uid) // only this user's complaints
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

        DateTime? toDateLocal(dynamic v) => _toDate(v);

        // Responsive grid
        return LayoutBuilder(
          builder: (context, constraints) {
            int cross = 1;
            if (constraints.maxWidth >= 1000) {
              cross = 3;
            } else if (constraints.maxWidth >= 650)
              cross = 2;

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF16161C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2C2C35)),
              ),
              padding: const EdgeInsets.all(14),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.9,
                ),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>? ?? {};

                  final ts = toDateLocal(data['timestamp']);
                  final desc = (data['description'] ?? '') as String;
                  final moh = (data['patient_moh_area'] ?? '-') as String;
                  final loc = (data['location'] ?? '-') as Object?;
                  final status = ((data['status'] ?? 'Pending') as String);
                  final imageUrl = data['imageUrl'] as String?;

                  final statusBg = _complaintStatusColor(status);
                  final statusFg = _complaintStatusTextColor(status);

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2C2C35)),
                    ),
                    child: Row(
                      children: [
                        // Colored status rail
                        Container(
                          width: 6,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(16),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: date + status chip
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _fmt(ts),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusBg,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: statusFg,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Description
                                Text(
                                  desc.isEmpty
                                      ? 'No description provided'
                                      : desc,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // Meta
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        loc.toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.local_hospital_outlined,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        moh,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // Actions
                                Row(
                                  children: [
                                    if (imageUrl != null)
                                      TextButton.icon(
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
                                        icon: const Icon(
                                          Icons.image_outlined,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'View Image',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                      )
                                    else
                                      const Text(
                                        'No image',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final toggleLabels = ['Current Location', 'Profile Address'];
    final selected = [_useProfileAddress == false, _useProfileAddress == true];

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
                        onEdit: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditAccountPage(),
                          ),
                        ),
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
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const ComplainsPage()),
                    ),
                  ),
                  _NavIcon(
                    label: 'Analytics',
                    asset: 'analytics',
                    isSelected: false,
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const AnalyticsPage()),
                    ),
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

              const SizedBox(height: 12),

              // ===== Location Source Toggle =====
              Center(
                child: ToggleButtons(
                  isSelected: selected,
                  onPressed: (i) async {
                    final useAddress = (i == 1);
                    setState(() => _useProfileAddress = useAddress);

                    // If switching to current location and we never grabbed GPS
                    if (!useAddress && _userLatLng == null && !_locDenied) {
                      await _bootstrapGps();
                    }

                    // If switching to address but not geocoded yet
                    if (useAddress &&
                        _addrLatLng == null &&
                        _profileAddress != null &&
                        !_addrGeocodeFailed) {
                      final p = await _geocodeAddress(_profileAddress!);
                      setState(() {
                        _addrLatLng = p;
                        _addrGeocodeFailed = p == null;
                      });
                    }

                    // Recenter to new source
                    final c = _activeCenter();
                    if (c != null && _mapCtrl != null) {
                      await _mapCtrl!.animateCamera(
                        CameraUpdate.newLatLngZoom(c, 14.5),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  selectedColor: Colors.white,
                  fillColor: const Color(0xFF2D1237),
                  color: Colors.black,
                  constraints: const BoxConstraints(
                    minHeight: 36,
                    minWidth: 150,
                  ),
                  children: toggleLabels
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            t,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

              const SizedBox(height: 12),

              // LIVE MAP
              SizedBox(height: 320, child: _buildMapSection()),

              const SizedBox(height: 24),

              // ---------- Your Complaints (cards) ----------
              const Text(
                'Your Complaints',
                style: TextStyle(
                  color: Color(0xFFDAA8F4),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildComplaintsCards(),

              const SizedBox(height: 28),

              // Tips carousel (no page rebuilds)
              SizedBox(
                height: 170,
                child: Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: 13,
                        onPageChanged: (index) => _tipsPage.value = index,
                        itemBuilder: (context, index) => Container(
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
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: _tipsPage,
                      builder: (_, current, __) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          13,
                          (index) => Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: current == index
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                            ),
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
