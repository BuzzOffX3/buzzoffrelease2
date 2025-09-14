import 'dart:async'; // debounce + overlay
import 'dart:convert';
import 'dart:math'; // for session token
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:http/http.dart' as http;

import 'MapsPage.dart';
import 'analytics.dart';
import 'SigInPage.dart';

class ComplainsPage extends StatefulWidget {
  const ComplainsPage({super.key});

  @override
  State<ComplainsPage> createState() => _ComplainsPageState();
}

class _ComplainsPageState extends State<ComplainsPage> {
  bool _isAnonymous = false;
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  File? _selectedImage;
  String _username = '';
  bool _isSubmitting = false;

  // picked coordinates (required)
  LatLng? _pickedLatLng;

  // last selected Google placeId (optional but useful)
  String? _lastPlaceId;

  // -------- Places Web Service key (pass via --dart-define) --------
  static const String _kPlacesApiKey = String.fromEnvironment(
    'PLACES_API_KEY',
    defaultValue: '',
  );

  // inline autocomplete state (overlay under the location field)
  final LayerLink _locFieldLink = LayerLink();
  OverlayEntry? _locOverlay;
  List<_PlacePrediction> _locSuggestions = [];
  bool _locSearching = false;
  Timer? _locDebounce;

  // per-typing session token (improves billing + quality)
  String? _placesSessionToken;
  String _newSessionToken() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
  // ---------------------------------------------------------------

  // -------- Colombo District MOH areas (editable) --------
  String? _selectedMohArea;
  final List<String> _mohAreas = const [
    'Colombo (CMC)',
    'Borella (CMC)',
    'Kollupitiya (CMC)',
    'Kotahena (CMC)',
    'Bambalapitiya (CMC)',
    'Wellawatte (CMC)',
    'Thimbirigasyaya',
    'Dehiwala',
    'Rathmalana',
    'Maharagama',
    'Kotte (Sri Jayawardenepura)',
    'Kolonnawa',
    'Kaduwela',
    'Homagama',
    'Kesbewa (Piliyandala)',
    'Moratuwa',
    'Padukka',
    'Seethawaka (Avissawella)',
  ];
  // -------------------------------------------------------

  @override
  void initState() {
    super.initState();
    fetchUsername();
  }

  @override
  void dispose() {
    _locDebounce?.cancel();
    _hideLocOverlay();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void fetchUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        setState(() {
          _username = (doc.data()?['username'] as String?) ?? 'User';
        });
      }
    }
  }

  void _handleMenuSelection(String value) {}

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _openLocationPicker() async {
    LatLng? start = _pickedLatLng;
    if (start == null) {
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          start = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {}
    }

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(initialCenter: start),
      ),
    );

    if (result != null) {
      setState(() {
        _pickedLatLng = result['latlng'] as LatLng?;
        _locationController.text = (result['address'] as String?) ?? '';
        _lastPlaceId = result['placeId'] as String?;
      });
    }
  }

  Future<void> _submitComplaint() async {
    // require a real map pick (lat/lng present)
    if (_descriptionController.text.isEmpty ||
        _locationController.text.isEmpty ||
        _selectedMohArea == null ||
        _pickedLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all fields and pick a valid location (choose a suggestion or use the map).',
          ),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not logged in')));
      return;
    }

    setState(() => _isSubmitting = true);

    String? imageUrl;
    if (_selectedImage != null) {
      try {
        final fileName =
            'complaints/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child(fileName);
        await ref.putFile(_selectedImage!);
        imageUrl = await ref.getDownloadURL();
      } on FirebaseException catch (e) {
        debugPrint('Storage error: ${e.code} — ${e.message}');
        imageUrl = null; // allow complaint without image
      } catch (e) {
        debugPrint('Storage unknown error: $e');
        imageUrl = null;
      }
    }

    final complaintData = <String, dynamic>{
      'uid': user.uid,
      'description': _descriptionController.text.trim(),
      'location': _locationController.text.trim(),
      'patient_moh_area': _selectedMohArea,
      'isAnonymous': _isAnonymous,
      'imageUrl': imageUrl,
      'status': 'Pending',
      'timestamp': FieldValue.serverTimestamp(),
      'lat': _pickedLatLng!.latitude,
      'lng': _pickedLatLng!.longitude,
      if (_lastPlaceId != null) 'placeId': _lastPlaceId,
    };

    try {
      await FirebaseFirestore.instance
          .collection('complaints')
          .add(complaintData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complaint submitted successfully!')),
      );

      _descriptionController.clear();
      _locationController.clear();

      setState(() {
        _selectedImage = null;
        _isAnonymous = false;
        _isSubmitting = false;
        _selectedMohArea = null;
        _pickedLatLng = null;
        _lastPlaceId = null;
        _locSuggestions = [];
      });
    } on FirebaseException catch (e) {
      debugPrint('Firestore error: ${e.code} — ${e.message}');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: ${e.code}')));
      setState(() => _isSubmitting = false);
    } catch (e) {
      debugPrint('Unknown error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to submit.')));
      setState(() => _isSubmitting = false);
    }
  }

  // ===== Inline Places Autocomplete (under the location field) =====

  void _onLocationChanged(String txt) {
    _locDebounce?.cancel();
    _locDebounce = Timer(const Duration(milliseconds: 250), () async {
      final q = txt.trim();
      if (q.isEmpty || _kPlacesApiKey.isEmpty) {
        _placesSessionToken = null;
        _hideLocOverlay();
        return;
      }
      _placesSessionToken ??= _newSessionToken();
      await _fetchPlacesAutocomplete(q);
      if (!mounted) return;
      if (_locSuggestions.isNotEmpty) {
        _showLocOverlay();
      } else {
        _hideLocOverlay();
      }
    });
  }

  Future<void> _fetchPlacesAutocomplete(String input) async {
    setState(() => _locSearching = true);
    try {
      final params = {
        'input': input,
        // bias to Sri Lanka
        'components': 'country:lk',
        'sessiontoken': _placesSessionToken ?? '',
        'key': _kPlacesApiKey,
      };
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        params,
      );
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? 'ZERO_RESULTS';
      if (status == 'OK') {
        final preds = (data['predictions'] as List)
            .map(
              (e) => _PlacePrediction(
                description: e['description'] ?? '',
                placeId: e['place_id'] ?? '',
              ),
            )
            .toList();
        _locSuggestions = preds;
      } else {
        _locSuggestions = [];
        if (mounted && status == 'REQUEST_DENIED') {
          final msg =
              (data['error_message'] as String?) ??
              'Places API request denied. Check API key & restrictions.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (_) {
      _locSuggestions = [];
    } finally {
      if (mounted) setState(() => _locSearching = false);
    }
  }

  void _showLocOverlay() {
    _hideLocOverlay();
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _locOverlay = OverlayEntry(
      builder: (context) {
        // this width matches the page (20px padding left+right)
        final width = MediaQuery.of(context).size.width - 40;
        return Positioned.fill(
          child: Stack(
            children: [
              // tap outside to dismiss
              GestureDetector(
                onTap: _hideLocOverlay,
                behavior: HitTestBehavior.opaque,
              ),
              CompositedTransformFollower(
                link: _locFieldLink,
                showWhenUnlinked: false,
                offset: const Offset(0, 56), // below the field
                child: Material(
                  elevation: 8,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 280,
                      minWidth: width,
                    ),
                    child: (_locSuggestions.isEmpty)
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _locSuggestions.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFEEEEEE),
                            ),
                            itemBuilder: (context, i) {
                              final p = _locSuggestions[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.place,
                                  color: Colors.black87,
                                ),
                                title: Text(
                                  p.description,
                                  style: const TextStyle(color: Colors.black87),
                                ),
                                onTap: () => _selectLocPrediction(p),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_locOverlay!);
  }

  void _hideLocOverlay() {
    _locOverlay?.remove();
    _locOverlay = null;
  }

  Future<void> _selectLocPrediction(_PlacePrediction p) async {
    _hideLocOverlay();
    _locationController.text = p.description;
    _lastPlaceId = p.placeId;

    try {
      final params = {
        'place_id': p.placeId,
        'fields': 'geometry',
        'sessiontoken': _placesSessionToken ?? '',
        'key': _kPlacesApiKey,
      };
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        params,
      );
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['status'] == 'OK') {
        final loc = data['result']['geometry']['location'];
        setState(() {
          _pickedLatLng = LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          );
        });
      }
    } catch (_) {
      // ignore
    } finally {
      // end the session after a successful selection
      _placesSessionToken = null;
    }
  }

  // =========================================================

  void _showImagePickerOptions(BuildContext context) {
    showModalBottomSheet(
      backgroundColor: Colors.grey[900],
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera, color: Colors.white),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.white),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );

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
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // Navigation Row
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
                    isSelected: true,
                    onTap: () {},
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
                  'Complain Form',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDAA8F4),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Image Picker
              GestureDetector(
                onTap: () => _showImagePickerOptions(context),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Center(
                      child: _selectedImage != null
                          ? Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Image.asset(
                              'images/image_placeholder.png',
                              width: 80,
                              height: 80,
                              color: Colors.purple[900],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // MOH Area (Autocomplete)
              _MohAutocomplete(
                label: 'MOH Area (Colombo District)',
                areas: _mohAreas,
                initialValue: _selectedMohArea,
                onChanged: (val) => setState(() => _selectedMohArea = val),
                themeBorder: themeBorder,
              ),
              const SizedBox(height: 15),

              // Description Field
              TextField(
                controller: _descriptionController,
                maxLines: 5,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Description',
                  filled: true,
                  fillColor: Colors.white,
                  hintStyle: const TextStyle(color: Colors.grey),
                  contentPadding: const EdgeInsets.all(16),
                  border: themeBorder,
                ),
              ),
              const SizedBox(height: 15),

              // Location box — editable with inline Places Autocomplete
              CompositedTransformTarget(
                link: _locFieldLink,
                child: TextField(
                  controller: _locationController,
                  readOnly: false,
                  onChanged: _onLocationChanged,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Type an address (or tap map icon)',
                    filled: true,
                    fillColor: Colors.white,
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: themeBorder,
                    contentPadding: const EdgeInsets.all(16),
                    suffixIcon: IconButton(
                      tooltip: 'Pick on map',
                      icon: const Icon(Icons.map, color: Colors.black87),
                      onPressed: _openLocationPicker,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Anonymous Checkbox
              Row(
                children: [
                  Checkbox(
                    value: _isAnonymous,
                    onChanged: (value) => setState(() => _isAnonymous = value!),
                    activeColor: Colors.deepPurple,
                    checkColor: Colors.white,
                  ),
                  const Text(
                    'Be Anonymous',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitComplaint,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Submit', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MohAutocomplete extends StatefulWidget {
  final String label;
  final List<String> areas;
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final InputBorder themeBorder;

  const _MohAutocomplete({
    required this.label,
    required this.areas,
    required this.initialValue,
    required this.onChanged,
    required this.themeBorder,
  });

  @override
  State<_MohAutocomplete> createState() => _MohAutocompleteState();
}

class _MohAutocompleteState extends State<_MohAutocomplete> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void didUpdateWidget(covariant _MohAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        _controller.text != (widget.initialValue ?? '')) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.initialValue ?? ''),
      optionsBuilder: (TextEditingValue value) {
        final q = value.text.toLowerCase().trim();
        if (q.isEmpty) return widget.areas;
        return widget.areas.where((a) => a.toLowerCase().contains(q));
      },
      onSelected: (val) {
        _controller.text = val;
        widget.onChanged(val);
      },
      fieldViewBuilder: (context, controller, focusNode, _) {
        controller.text = _controller.text;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );

        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (t) => widget.onChanged(t.isEmpty ? null : t),
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: const TextStyle(color: Colors.grey),
            hintText: 'Type to search…',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: widget.themeBorder,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((controller.text).isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.black87),
                    onPressed: () {
                      controller.clear();
                      widget.onChanged(null);
                      FocusScope.of(context).requestFocus(focusNode);
                    },
                  ),
                const Icon(Icons.keyboard_arrow_down, color: Colors.black87),
              ],
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final width = MediaQuery.of(context).size.width - 40; // page padding
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.white,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 260, minWidth: width),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      opt,
                      style: const TextStyle(color: Colors.black),
                    ),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
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

/// ================================================
/// LocationPickerPage: full-screen map with crosshair
/// + Google Places Autocomplete (live dropdown)
/// + Find-Place-From-Text + Geocode fallback (LK bias)
/// ================================================
class LocationPickerPage extends StatefulWidget {
  final LatLng? initialCenter;
  const LocationPickerPage({super.key, this.initialCenter});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  // same PLACES key for picker autocomplete/details
  static const String _kPlacesApiKey = String.fromEnvironment(
    'PLACES_API_KEY',
    defaultValue: '',
  );

  GoogleMapController? _ctrl;
  LatLng? _center;
  String _address = 'Fetching address…';
  bool _loading = true;
  bool _locDenied = false;

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  List<_PlacePrediction> _predictions = [];

  // Remember the selected placeId (if picked via autocomplete or find-place)
  String? _selectedPlaceId;

  // session token for this picker interaction
  String? _sessionToken;
  String _newSessionToken() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    LatLng? start = widget.initialCenter;

    if (start == null) {
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          _locDenied = true;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          start = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {
        _locDenied = true;
      }
    }

    // fallback: Colombo Fort
    start ??= const LatLng(6.9355, 79.8487);

    setState(() {
      _center = start;
      _loading = false;
    });

    _reverseGeocode(start);
  }

  // Reverse geocode the map center to an address
  Future<void> _reverseGeocode(LatLng p) async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
      if (placemarks.isNotEmpty) {
        final m = placemarks.first;
        final parts = <String>[
          if ((m.street ?? '').trim().isNotEmpty) m.street!,
          if ((m.subLocality ?? '').trim().isNotEmpty) m.subLocality!,
          if ((m.locality ?? '').trim().isNotEmpty) m.locality!,
          if ((m.administrativeArea ?? '').trim().isNotEmpty)
            m.administrativeArea!,
          if ((m.postalCode ?? '').trim().isNotEmpty) m.postalCode!,
        ];
        setState(() => _address = parts.join(', '));
      } else {
        setState(() => _address = 'Unknown location');
      }
    } catch (_) {
      setState(() => _address = 'Unknown location');
    }
  }

  // ---------- NEW HELPERS: smarter text lookup ----------

  String _slQuery(String input) {
    final t = input.trim();
    if (t.toLowerCase().contains('sri lanka')) return t;
    return '$t, Sri Lanka';
  }

  /// Prefer Places "Find Place From Text" for messy human text
  Future<LatLng?> _findPlaceFromText(String input) async {
    try {
      if (_kPlacesApiKey.isEmpty) return null;
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/findplacefromtext/json',
        {
          'input': _slQuery(input),
          'inputtype': 'textquery',
          'fields': 'geometry,place_id,formatted_address,name',
          'region': 'lk',
          'key': _kPlacesApiKey,
        },
      );
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? 'ZERO_RESULTS';
      if (status == 'OK' && (data['candidates'] as List).isNotEmpty) {
        final cand = data['candidates'][0];
        final loc = cand['geometry']['location'];
        _selectedPlaceId = cand['place_id'] as String?;
        return LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
      } else {
        if (mounted && status == 'REQUEST_DENIED') {
          final msg =
              (data['error_message'] as String?) ??
              'FindPlace denied. Check API key & restrictions.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Geocoding fallback with LK bias
  Future<LatLng?> _geocodeByText(String input) async {
    try {
      if (_kPlacesApiKey.isEmpty) return null;
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': _slQuery(input),
        'region': 'lk',
        'key': _kPlacesApiKey,
      });
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? 'ZERO_RESULTS';
      if (status == 'OK') {
        final loc = data['results'][0]['geometry']['location'];
        return LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
      } else {
        if (mounted && status == 'REQUEST_DENIED') {
          final msg =
              (data['error_message'] as String?) ??
              'Geocoding denied. Check API key & restrictions.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ===== Places API =====
  Future<void> _fetchAutocomplete(String input) async {
    final q = input.trim();
    if (q.isEmpty || _kPlacesApiKey.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    _sessionToken ??= _newSessionToken();
    setState(() => _searching = true);
    try {
      final params = {
        'input': q,
        'components': 'country:lk',
        'sessiontoken': _sessionToken!,
        'key': _kPlacesApiKey,
      };
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        params,
      );
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'ZERO_RESULTS';

      if (status == 'OK') {
        setState(() {
          _predictions = (data['predictions'] as List)
              .map(
                (e) => _PlacePrediction(
                  description: e['description'] ?? '',
                  placeId: e['place_id'] ?? '',
                ),
              )
              .toList();
        });
      } else {
        setState(() => _predictions = []);
        if (mounted && status == 'REQUEST_DENIED') {
          final msg =
              (data['error_message'] as String?) ??
              'Places API request denied. Check API key & restrictions.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (_) {
      setState(() => _predictions = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectPrediction(_PlacePrediction p) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchCtrl.text = p.description;
      _predictions = [];
      _searching = true;
      _selectedPlaceId = p.placeId;
    });
    try {
      final params = {
        'place_id': p.placeId,
        'fields': 'geometry',
        'sessiontoken': _sessionToken ?? '',
        'key': _kPlacesApiKey,
      };
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        params,
      );
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['status'] == 'OK') {
        final loc = data['result']['geometry']['location'];
        final latLng = LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
        _center = latLng;
        await _ctrl?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
        await _reverseGeocode(latLng);
      } else if (mounted && data['status'] == 'REQUEST_DENIED') {
        final msg =
            (data['error_message'] as String?) ??
            'Place details denied. Check API key & restrictions.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      // ignore
    } finally {
      _sessionToken = null; // end this session
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _recenterToMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final p = LatLng(pos.latitude, pos.longitude);
      _center = p;
      _selectedPlaceId = null; // using raw GPS
      _sessionToken = null;
      _ctrl?.animateCamera(CameraUpdate.newLatLngZoom(p, 16));
      await _reverseGeocode(p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dropdownMaxWidth = MediaQuery.of(context).size.width - 24 - 24;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161C),
        title: const Text('Pick Location'),
        actions: [
          IconButton(
            tooltip: 'My Location',
            onPressed: _recenterToMyLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: _loading || _center == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _center!,
                    zoom: 16,
                  ),
                  myLocationEnabled: !_locDenied,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  zoomGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  onMapCreated: (c) => _ctrl = c,
                  onCameraMove: (pos) => _center = pos.target,
                  onCameraIdle: () {
                    if (_center != null) _reverseGeocode(_center!);
                  },
                ),

                // Crosshair
                const IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.location_on,
                      size: 36,
                      color: Colors.redAccent,
                    ),
                  ),
                ),

                // SEARCH BAR overlay
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      Material(
                        elevation: 3,
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.black87),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  textInputAction: TextInputAction.search,
                                  onChanged: _fetchAutocomplete,
                                  onSubmitted: _fetchAutocomplete,
                                  style: const TextStyle(color: Colors.black),
                                  decoration: const InputDecoration(
                                    hintText: 'Search address or place',
                                    hintStyle: TextStyle(color: Colors.grey),
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              if (_searchCtrl.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.black87,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {
                                      _predictions = [];
                                      _sessionToken = null;
                                    });
                                  },
                                  tooltip: 'Clear',
                                ),
                              const SizedBox(width: 4),
                              _searching
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.black87,
                                      ),
                                      onPressed: () async {
                                        final q = _searchCtrl.text.trim();
                                        if (q.isEmpty) return;

                                        await _fetchAutocomplete(q);

                                        if (_predictions.isEmpty) {
                                          // Try Places find-place first, then Geocoding
                                          LatLng? loc =
                                              await _findPlaceFromText(q);
                                          loc ??= await _geocodeByText(q);

                                          if (loc != null) {
                                            _center = loc;
                                            await _ctrl?.animateCamera(
                                              CameraUpdate.newLatLngZoom(
                                                loc,
                                                16,
                                              ),
                                            );
                                            await _reverseGeocode(loc);
                                          } else {
                                            if (mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Couldn’t find that address.',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      },
                                      tooltip: 'Search',
                                    ),
                            ],
                          ),
                        ),
                      ),
                      if (_predictions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: dropdownMaxWidth,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: _predictions.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFEEEEEE),
                            ),
                            itemBuilder: (context, i) {
                              final p = _predictions[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.place,
                                  color: Colors.black87,
                                ),
                                title: Text(
                                  p.description,
                                  style: const TextStyle(color: Colors.black),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectPrediction(p),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // Bottom sheet info + confirm
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161C),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2C2C35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.place,
                              color: Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _address,
                                style: const TextStyle(color: Colors.white),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (_searchCtrl.text.trim().isNotEmpty &&
                                  _selectedPlaceId == null) {
                                LatLng? loc = await _findPlaceFromText(
                                  _searchCtrl.text.trim(),
                                );
                                loc ??= await _geocodeByText(
                                  _searchCtrl.text.trim(),
                                );
                                if (loc != null) {
                                  _center = loc;
                                  await _reverseGeocode(loc);
                                }
                              }
                              if (!mounted) return;
                              Navigator.pop<Map<String, dynamic>>(context, {
                                'latlng': _center,
                                'address': _address,
                                'placeId': _selectedPlaceId,
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text(
                              'Use this location',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PlacePrediction {
  final String description;
  final String placeId;
  _PlacePrediction({required this.description, required this.placeId});
}
