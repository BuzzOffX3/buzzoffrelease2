import 'package:buzzoff/Citizens/migrate.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'MapsPage.dart';
import 'RegisterPage.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  Future<void> _signIn() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      _showDialog(
        title: 'Fields Required',
        titleColor: Colors.yellowAccent,
        message: 'Please fill in both email and password fields.',
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final credential = await auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = credential.user!;
      // Force refresh claims to be safe
      final idToken = await user.getIdTokenResult(true);
      String? role = (idToken.claims?['role'] as String?);

      // Fallback to Firestore users/{uid}.role if claim missing
      if (role == null) {
        final uid = user.uid;
        final snap = await firestore.collection('users').doc(uid).get();
        if (snap.exists) {
          role = (snap.data()?['role'] as String?);
        }
      }

      if (role == 'citizen') {
        // ✅ Citizens go to the mobile app (Maps)
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MapsPage()),
        );
      } else {
        // 🚫 Everyone else gets a “Use the web app” page
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MigrateToWebPage(role: role ?? 'unknown'),
          ),
        );
      }
    } catch (e) {
      _showDialog(
        title: 'Sign In Failed',
        titleColor: Colors.redAccent,
        message:
            'OH NOOOOOOOOOOOOOO! Your Account Info seems to be wrong, please try again X>',
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showDialog({
    required String title,
    required String message,
    Color titleColor = Colors.white,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(title, style: TextStyle(color: titleColor)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            child: const Text('OK', style: TextStyle(color: Color(0xFFD9ADF7))),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('images/logo.png', height: 100),
                const SizedBox(height: 30),
                const Text(
                  'Sign In',
                  style: TextStyle(
                    color: Color(0xFFD9ADF7),
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.black),
                  decoration: _inputStyle('Email'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.black),
                  decoration: _inputStyle('Password'),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5FBF),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: isLoading ? null : _signIn,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    );
                  },
                  child: const Text('No account? Register here'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black54),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
