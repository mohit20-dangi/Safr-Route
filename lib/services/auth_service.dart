import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../background/foreground_keepalive.dart';
import '../background/tracker_part.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  bool _googleReady = false;

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get user => _auth.currentUser;

  Future<void> signInWithGoogle() async {
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize();
      _googleReady = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    await _ensureUserDoc(cred.user!);
  }

  Future<void> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _ensureUserDoc(cred.user!);
  }

  Future<void> registerWithEmail(
    String name,
    String email,
    String password,
  ) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user!.updateDisplayName(name);
    await _ensureUserDoc(cred.user!, name: name);
  }

  Future<void> signOut() async {
    await TrackerPart.instance.stop();
    await ForegroundKeepAlive.stop();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> _ensureUserDoc(User u, {String? name}) async {
    await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
      'name': name ?? u.displayName ?? u.email ?? 'Me',
      'photoUrl': u.photoURL,
    }, SetOptions(merge: true));
  }
}
