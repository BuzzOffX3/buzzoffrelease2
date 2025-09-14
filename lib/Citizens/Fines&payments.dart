// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'MapsPage.dart'; // for Map nav
import 'complains.dart';
import 'analytics.dart';
import 'EditProfile.dart';
import 'package:buzzoff/Citizens/SigInPage.dart';

// A standalone, static help page explaining how to use the map.
// Navigate with:
// Navigator.push(context, MaterialPageRoute(builder: (_) => const MapHowToPage()));
class MapHowToPage extends StatefulWidget {
  const MapHowToPage({super.key});

  @override
  State<MapHowToPage> createState() => _MapHowToPageState();
}

class _MapHowToPageState extends State<MapHowToPage> {
  String _username = 'User';

  @override
  void initState() {
    super.initState();
    _fetchUsername();
  }

  Future<void> _fetchUsername() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      final name = (doc.data()?['username'] as String?)?.trim();
      setState(
        () => _username = (name != null && name.isNotEmpty) ? name : 'User',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
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
                    isSelected: false, // we're on Help page
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
                    label: 'Help',
                    asset: 'fines_and_payments', // reusing your icon asset
                    isSelected: true, // current tab
                    onTap: () {}, // already here
                  ),
                ],
              ),

              const SizedBox(height: 30),

              const Center(
                child: Text(
                  'HOW TO USE THE MAP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _heroPanel(),

              const SizedBox(height: 16),
              _howToCard(
                title: '1) Pick your location source',
                body:
                    'Use the toggle to switch between Current Location (GPS) and Profile Address (your saved address). '
                    'If GPS permission is denied, either enable it or use your saved profile address.',
                asset: 'images/howto_toggle.png',
              ),

              const SizedBox(height: 12),
              _howToCard(
                title: '2) Understand the red circles',
                body:
                    'Red circles mark reported dengue case areas (300m radius) for the current month. '
                    'No personal details are shown — only affected zones.',
                asset: 'images/howto_circles.png',
              ),

              const SizedBox(height: 12),
              _howToCard(
                title: '3) Navigate the map',
                body:
                    'Pinch to zoom or use the + / – buttons. '
                    'Tap the target icon to re-center on your chosen location source.',
                asset: 'images/howto_controls.png',
              ),

              const SizedBox(height: 12),
              _howToCard(
                title: '4) Safety notice',
                body:
                    'If you are inside any 300m zone, a warning banner will appear. '
                    'Take precautions: remove standing water, use repellent, and watch for symptoms.',
                asset: 'images/howto_warning.png',
              ),

              const SizedBox(height: 20),
              _tipsPanel(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- HOW-TO UI blocks ----

  Widget _heroPanel() {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isNarrow = constraints.maxWidth < 720;

        final img = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: const Color(0xFF1E1E26),
            child: AspectRatio(
              aspectRatio: isNarrow ? 16 / 9 : 4 / 3,
              child: Image.asset(
                'images/howto_hero.png',
                fit: BoxFit.contain, // show full image without cropping
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.map_outlined,
                    color: Colors.white38,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        );

        // text block (no Expanded here)
        final textBlock = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'See Dengue Patients Close to You',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This page explains how to read the map, understand case zones, and keep yourself safe.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2C2C35)),
          ),
          padding: const EdgeInsets.all(16),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [img, const SizedBox(height: 12), textBlock],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 220, child: img),
                    const SizedBox(width: 16),
                    // only expand in Row (bounded height)
                    Expanded(child: textBlock),
                  ],
                ),
        );
      },
    );
  }

  Widget _howToCard({
    required String title,
    required String body,
    required String asset,
  }) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isNarrow = constraints.maxWidth < 720;

        final imageBox = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: const Color(0xFF1E1E26),
            child: AspectRatio(
              aspectRatio: isNarrow
                  ? 16 / 9
                  : 4 / 3, // wide on mobile, balanced on desktop
              child: Padding(
                padding: const EdgeInsets.all(6), // small gutter around image
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain, // keep full image visible
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final textCol = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ],
        );

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2C2C35)),
          ),
          padding: const EdgeInsets.all(14),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    imageBox,
                    const SizedBox(height: 12),
                    textCol, // no Expanded in Column (unbounded height)
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 180, child: imageBox),
                    const SizedBox(width: 12),
                    Expanded(child: textCol), // expand only in Row
                  ],
                ),
        );
      },
    );
  }

  Widget _tipsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C35)),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Safety Tips',
            style: TextStyle(
              color: Color(0xFFDAA8F4),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          _TipItem('• Remove standing water around your home.'),
          _TipItem('• Use mosquito repellent and wear long sleeves.'),
          _TipItem('• Keep doors/windows screened or closed.'),
          _TipItem('• Seek medical advice if symptoms appear.'),
        ],
      ),
    );
  }
}

// ===== Pretty Profile Menu + Sign-out helper (copied to keep file standalone) =====
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

// ---- small text row item
class _TipItem extends StatelessWidget {
  final String text;
  const _TipItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13.5),
      ),
    );
  }
}
