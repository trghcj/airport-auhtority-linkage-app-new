import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:airport_auhtority_linkage_app/pages/login_page.dart';
import 'package:airport_auhtority_linkage_app/providers/auth_provider.dart';
import 'package:logger/logger.dart'; // Ensure this is imported

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  bool loading = false;
  final Logger _logger = Logger(); // Initialize Logger instance

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/airplane.webp',
              fit: BoxFit.cover,
            ),
          ),

          // Blur effect
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: const SizedBox(),
              ),
            ),
          ),

          // Sign-up card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Welcome to",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "AIRPORT AUTHORITY OF INDIA",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Sign Up",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        errorText: null,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password",
                        errorText: null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: loading
                          ? null
                          : () async {
                              final email = emailController.text.trim();
                              final password = passwordController.text.trim();
                              if (email.isEmpty || password.isEmpty) {
                                _showError("Please enter both email and password");
                                return;
                              }
                              _logger.d('Signup button pressed: email=$email, password=$password');
                              setState(() => loading = true);
                              bool success = await authProvider.signUpWithEmail(email, password);
                              if (!mounted) return;
                              setState(() => loading = false);
                              if (success) {
                                _logger.i('Signup successful, navigating to home');
                                // Navigate to home page or next screen (e.g., Navigator.pushReplacementNamed(context, '/home'))
                              } else {
                                _showError(authProvider.error ?? "Signup failed");
                              }
                            },
                      child: loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Sign Up"),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        _logger.d('Google Sign-In button pressed');
                        bool success = await authProvider.signInWithGoogle();
                        if (!mounted) return;
                        if (success) {
                          _logger.i('Google Sign-In successful, navigating to home');
                          // Navigate to home page or next screen (e.g., Navigator.pushReplacementNamed(context, '/home'))
                        } else {
                          _showError(authProvider.error ?? "Google Sign-In failed");
                        }
                      },
                      icon: const Icon(Icons.login),
                      label: const Text("Sign in with Google"),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: "Phone Number (e.g., +91xxxxxxxxxx)",
                        errorText: null,
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final phone = phoneController.text.trim();
                        if (phone.isEmpty) {
                          _showError("Please enter a phone number");
                          return;
                        }
                        if (!phone.startsWith('+')) {
                          _showError("Phone number must include country code (e.g., +91)");
                          return;
                        }
                        _logger.d('Phone Sign-In button pressed: phone=$phone');
                        bool success = await authProvider.signInWithPhone(phone, context);
                        if (!mounted) return;
                        if (success) {
                          _logger.i('Phone Sign-In successful, navigating to home');
                          // Navigate to home page or next screen (e.g., Navigator.pushReplacementNamed(context, '/home'))
                        } else {
                          _showError(authProvider.error ?? "Phone Sign-In failed");
                        }
                      },
                      icon: const Icon(Icons.phone_android),
                      label: const Text("Sign in with Phone OTP"),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        _logger.d('Navigating to LoginPage');
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text("Already have an account? Login"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}