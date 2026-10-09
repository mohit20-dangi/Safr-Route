import 'package:cloud_firestore/cloud_firestore.dart';

enum Role { admin, guardian, traveler }

class Member {
  final String uid, name;
  final Role role;
  final bool active;
  const Member(this.uid, this.name, this.role, this.active);

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Member(
      d.id,
      m['name'] ?? 'Unknown',
      Role.values.firstWhere(
        (r) => r.name == m['role'],
        orElse: () => Role.guardian,
      ),
      m['status'] == 'active',
    );
  }
}
