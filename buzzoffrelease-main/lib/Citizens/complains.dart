import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'MapsPage.dart';
import 'analytics.dart';

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

  // -------- Colombo District MOH areas (editable) --------
  String? _selectedMohArea;
  final List<String> _mohAreas = const [
    // CMC & nearby
    'Colombo (CMC)',
    'Borella (CMC)',
    'Kollupitiya (CMC)',
    'Kotahena (CMC)',
    'Bambalapitiya (CMC)',
    'Wellawatte (CMC)',
    'Thimbirigasyaya',
    // Colombo District MOH divisions
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

  Future<void> _submitComplaint() async {
    if (_descriptionController.text.isEmpty ||
        _locationController.text.isEmpty ||
        _selectedMohArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields (including MOH Area)'),
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

    final complaintData = {
      'uid': user.uid,
      'description': _descriptionController.text.trim(),
      'location': _locationController.text.trim(),
      'moh_area': _selectedMohArea,
      'isAnonymous': _isAnonymous,
      'imageUrl': imageUrl,
      'status': 'Pending', // default status
      'timestamp': FieldValue.serverTimestamp(),
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
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                        ),
                        color: Colors.grey[900],
                        onSelected: _handleMenuSelection,
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
                  child: Center(
                    child: _selectedImage != null
                        ? Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
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
              const SizedBox(height: 15),

              // ---------- Searchable MOH Area (Autocomplete) ----------
              _MohAutocomplete(
                label: 'MOH Area (Colombo District)',
                areas: _mohAreas,
                initialValue: _selectedMohArea,
                onChanged: (val) => setState(() => _selectedMohArea = val),
                themeBorder: themeBorder,
              ),
              const SizedBox(height: 15),
              // --------------------------------------------------------

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

              // Location Field
              TextField(
                controller: _locationController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Location',
                  filled: true,
                  fillColor: Colors.white,
                  hintStyle: const TextStyle(color: Colors.grey),
                  border: themeBorder,
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
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // keep our controller in sync
        controller.text = _controller.text;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );

        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (t) =>
              widget.onChanged(t.isEmpty ? null : t), // allow clearing to null
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
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.white,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 280),
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
