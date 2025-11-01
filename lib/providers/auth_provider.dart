import 'dart:async'; // Required for Completer
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final Logger _logger = Logger();

  User? get user => _auth.currentUser;

  bool isLoading = false;
  String? error;

  // Store verification ID for OTP flow
  String? _verificationId;

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void _setError(String? msg) {
    error = msg;
    notifyListeners();
  }

  /// Sign up with email and password
  Future<bool> signUpWithEmail(String email, String password) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Attempting signup with email: $email');

      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      _logger.i('Signup successful: ${userCredential.user?.uid}');
      return true;
    } on FirebaseAuthException catch (e) {
      String errorMessage = _handleFirebaseError(e);
      _logger.e('Signup error: $errorMessage (Code: ${e.code})');
      _setError(errorMessage);
      return false;
    } catch (e) {
      _logger.e('Unexpected signup error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Login with email and password
  Future<bool> loginWithEmail(String email, String password) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Attempting login with email: $email');

      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      _logger.i('Login successful: ${userCredential.user?.uid}');
      return true;
    } on FirebaseAuthException catch (e) {
      String errorMessage = _handleFirebaseError(e);
      _logger.e('Login error: $errorMessage (Code: ${e.code})');
      _setError(errorMessage);
      return false;
    } catch (e) {
      _logger.e('Unexpected login error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Google Sign-In
  Future<bool> signInWithGoogle() async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Starting Google Sign-In');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _logger.w('Google Sign-In cancelled by user');
        _setError('Sign-in cancelled');
        return false;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      _logger.i('Google Sign-In successful: ${userCredential.user?.uid}');
      return true;
    } on FirebaseAuthException catch (e) {
      String errorMessage = _handleFirebaseError(e);
      _logger.e('Google Sign-In error: $errorMessage (Code: ${e.code})');
      _setError(errorMessage);
      return false;
    } catch (e) {
      _logger.e('Google Sign-In error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Send OTP (for manual flow)
  Future<void> sendOTP(
    String phoneNumber,
    Function(String verificationId) onCodeSent,
    Function(String error) onError,
  ) async {
    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Sending OTP to: $phoneNumber');

      if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
        _logger.w('Phone auth may fail on emulator. Use real device!');
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          _logger.i('Auto-verification completed');
          await _signInWithPhoneCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = _handlePhoneError(e);
          _logger.e('Phone verification failed: $errorMessage (Code: ${e.code})');
          _setError(errorMessage);
          onError(errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _logger.i('OTP sent. verificationId stored.');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _logger.d('Auto-retrieval timeout: $verificationId');
        },
      );
    } catch (e) {
      _logger.e('Unexpected error sending OTP: $e');
      _setError(e.toString());
      onError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Verify OTP (manual)
  Future<bool> verifyOTP(String verificationId, String smsCode) async {
    // Prefer passed verificationId, fall back to stored _verificationId if not provided.
    final id = (verificationId.isNotEmpty ? verificationId : (_verificationId ?? ''));

    if (id.isEmpty || smsCode.isEmpty) {
      _setError('Invalid verification ID or OTP');
      return false;
    }

    try {
      _setLoading(true);
      _setError(null);
      _logger.d('Verifying OTP: $smsCode');

      final credential = PhoneAuthProvider.credential(
        verificationId: id,
        smsCode: smsCode.trim(),
      );

      return await _signInWithPhoneCredential(credential);
    } catch (e) {
      _logger.e('OTP verification failed: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Sign in with Phone (with dialog) - FULLY FIXED
  Future<bool> signInWithPhone(String phone, BuildContext context) async {
    _verificationId = null;
    _setError(null);

    final completer = Completer<bool>();

    try {
      _setLoading(true);
      _logger.d('Starting phone authentication for: $phone');

      if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
        _logger.w('Phone auth may fail on emulator. Use real device!');
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          _logger.i('Auto-verification completed');
          final success = await _signInWithPhoneCredential(credential);
          if (!completer.isCompleted) completer.complete(success);
        },
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = _handlePhoneError(e);
          _logger.e('Phone verification failed: $errorMessage (Code: ${e.code})');
          _setError(errorMessage);
          if (!completer.isCompleted) completer.complete(false);
        },
        codeSent: (String verificationId, int? resendToken) async {
          _verificationId = verificationId;
          _logger.i('OTP sent. Showing dialog...');

          final smsCode = await _showOTPDialog(context);
          if (smsCode != null && smsCode.length == 6) {
            final success = await verifyOTP(verificationId, smsCode);
            if (!completer.isCompleted) completer.complete(success);
          } else {
            _setError('Invalid or missing OTP');
            if (!completer.isCompleted) completer.complete(false);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _logger.d('Auto-retrieval timeout: $verificationId');
        },
      );

      return await completer.future;
    } catch (e) {
      _logger.e('Unexpected phone auth error: $e');
      _setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Shared method to sign in with phone credential
  Future<bool> _signInWithPhoneCredential(PhoneAuthCredential credential) async {
    try {
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      _logger.i('Phone sign-in successful: ${userCredential.user?.uid}');
      _setError(null);
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      String errorMessage = _handleFirebaseError(e);
      _logger.e('Phone sign-in failed: $errorMessage (Code: ${e.code})');
      _setError(errorMessage);
      return false;
    } catch (e) {
      _logger.e('Phone sign-in error: $e');
      _setError(e.toString());
      return false;
    }
  }

  /// Show OTP dialog
  Future<String?> _showOTPDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Enter OTP"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("We sent a 6-digit code to your phone."),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: "123456",
                border: OutlineInputBorder(),
                counterText: "",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text.trim();
              if (code.length == 6) {
                Navigator.pop(context, code);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please enter 6-digit OTP")),
                );
              }
            },
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }

  /// Sign out
  Future<void> logout() async {
    try {
      _logger.d('Signing out user');
      await _googleSignIn.signOut();
      await _auth.signOut();
      _verificationId = null;
      _setError(null);
      _logger.i('Sign out successful');
      notifyListeners();
    } catch (e) {
      _logger.e('Sign out error: $e');
      _setError(e.toString());
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helper: Handle Firebase Errors
  // ─────────────────────────────────────────────────────────────
  String _handleFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
        return 'Invalid email or password. Please check and try again.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'invalid-verification-code':
        return 'Invalid OTP. Please check and try again.';
      case 'invalid-verification-id':
        return 'Session expired. Please request a new OTP.';
      case 'invalid-phone-number':
        return 'Invalid phone number format. Use +91XXXXXXXXXX';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Try again later.';
      case 'invalid-app-credential':
        return 'App verification failed. Add SHA-1 & SHA-256 in Firebase Console.';
      case 'captcha-check-failed':
        return 'reCAPTCHA failed. Test on a real device with internet.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helper: Handle Phone-Specific Errors
  // ─────────────────────────────────────────────────────────────
  String _handlePhoneError(FirebaseAuthException e) {
    if (e.code == 'invalid-app-credential') {
      return 'App not verified. Add SHA-1 & SHA-256 in Firebase Console → Project Settings → Your Apps.';
    }
    if (e.code == 'captcha-check-failed') {
      return 'reCAPTCHA failed. Test on a real device (not emulator).';
    }
    return _handleFirebaseError(e);
  }
}