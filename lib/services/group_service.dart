import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/member.dart';

class GroupService {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _name {
    final u = FirebaseAuth.instance.currentUser!;
    return u.displayName ?? u.email ?? 'Me';
  }

  DocumentReference<Map<String, dynamic>> _group(String g) =>
      _db.collection('groups').doc(g);
  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(_uid);

  static String _random(int n, String chars) {
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // No 0/O/1/I to avoid confusion when reading a code aloud.
  static String newInviteCode() =>
      _random(6, 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789');

  /// Order matters for the security rules:
  /// group -> own member doc (active admin) -> invite code.
  Future<String> createGroup(String name) async {
    final ref = _db.collection('groups').doc();
    final code = newInviteCode();
    await ref.set({
      'name': name,
      'createdBy': _uid,
      'inviteCode': code,
      'ntfyTopic':
          'saferoute-${_random(24, 'abcdefghijkmnpqrstuvwxyz23456789')}',
      'settings': {
        'corridorM': 300,
        'rerouteToleranceMin': 15,
        'stopAlertMin': 10,
        'staleAlertMin': 5,
        'lowBatteryPct': 15,
        'arriveRadiusM': 50,
      },
    });
    await ref.collection('members').doc(_uid).set({
      'name': _name,
      'role': 'admin',
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('inviteCodes').doc(code).set({
      'groupId': ref.id,
      'groupName': name,
    });
    await _addToUser(ref.id, name);
    return ref.id;
  }

  /// Returns the group name, or throws if the code is unknown.
  Future<String> joinWithCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    final inv = await _db.collection('inviteCodes').doc(code).get();
    if (!inv.exists) throw Exception('Invite code not found');
    final gid = inv['groupId'] as String;
    final gname = inv['groupName'] as String;
    await _group(gid).collection('members').doc(_uid).set({
      'name': _name,
      'role': 'guardian',
      'status': 'pending',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await _addToUser(gid, gname);
    return gname;
  }

  Future<void> _addToUser(String gid, String gname) => _userDoc.set({
    'groupIds': FieldValue.arrayUnion([gid]),
    'groupNames': {gid: gname},
  }, SetOptions(merge: true));

  Future<void> approve(String gid, String uid, Role role) =>
      _group(gid)
          .collection('members')
          .doc(uid)
          .update({'status': 'active', 'role': role.name});

  Future<void> setRole(String gid, String uid, Role role) =>
      _group(gid).collection('members').doc(uid).update({'role': role.name});

  Future<void> removeMember(String gid, String uid) =>
      _group(gid).collection('members').doc(uid).delete();

  Future<void> leave(String gid) async {
    await _group(gid).collection('members').doc(_uid).delete();
    await _userDoc.update({
      'groupIds': FieldValue.arrayRemove([gid]),
      'groupNames.$gid': FieldValue.delete(),
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> userStream() =>
      _userDoc.snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> myMembership(String gid) =>
      _group(gid).collection('members').doc(_uid).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> groupStream(String gid) =>
      _group(gid).snapshots();

  Stream<List<Member>> members(String gid) =>
      _group(gid)
          .collection('members')
          .snapshots()
          .map((s) => s.docs.map(Member.fromDoc).toList());
}
