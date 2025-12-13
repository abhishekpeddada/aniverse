import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;

class AuthService {
  FirebaseAuth? _auth;
  bool _isFirebaseAvailable = false;

  AuthService() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        _auth = FirebaseAuth.instance;
        _isFirebaseAvailable = true;
      } catch (e) {
        debugPrint('Firebase Auth not available: $e');
        _isFirebaseAvailable = false;
      }
    } else {
      debugPrint('Firebase Auth disabled on desktop platform');
      _isFirebaseAvailable = false;
    }
  }

  Stream<User?> get authStateChanges {
    if (!_isFirebaseAvailable || _auth == null) {
      return Stream.value(null);
    }
    return _auth!.authStateChanges();
  }

  User? get currentUser {
    if (!_isFirebaseAvailable || _auth == null) return null;
    return _auth!.currentUser;
  }

  Future<UserCredential?> signInWithGoogle() async {
    if (!_isFirebaseAvailable || _auth == null) {
      debugPrint('Google Sign-In not available on desktop');
      return null;
    }

    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        return await _auth!.signInWithPopup(googleProvider);
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) return null;

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        return await _auth!.signInWithCredential(credential);
      }
    } catch (e) {
      debugPrint('❌ Sign in error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (!_isFirebaseAvailable || _auth == null) return;

    try {
      if (!kIsWeb) {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      }
      await _auth!.signOut();
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
      rethrow;
    }
  }

  String? get userEmail => currentUser?.email;
  String? get userName => currentUser?.displayName;
  String? get userPhotoUrl => currentUser?.photoURL;
  String? get userId => currentUser?.uid;
}
