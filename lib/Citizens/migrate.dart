import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MigrateToWebPage extends StatelessWidget {
  final String role;
  const MigrateToWebPage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.desktop_windows,
                size: 64,
                color: Color(0xFFD9ADF7),
              ),
              const SizedBox(height: 16),
              Text(
                'Use the Web Portal',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'re registered as "$role". The mobile app is only for citizens. '
                'Please continue on the BuzzOff web portal.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final uri = Uri.parse(
                    'https://your-web-app-url.example',
                  ); // TODO: set your web URL
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5FBF),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('Open Web Portal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
