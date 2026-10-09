import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/member.dart';
import '../services/group_service.dart';

class GroupAdminScreen extends StatelessWidget {
  GroupAdminScreen({super.key, required this.groupId, required this.groupName});
  final String groupId, groupName;
  final _svc = GroupService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(groupName)),
      body: ListView(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _svc.groupStream(groupId),
            builder: (context, snap) {
              final code = snap.data?.data()?['inviteCode'] ?? '......';
              final topic = snap.data?.data()?['ntfyTopic'] ?? '';
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.vpn_key),
                    title: Text('Invite code: $code'),
                    subtitle: const Text('Tap to copy and share with family'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active),
                    title: Text('iPhone alerts topic: $topic'),
                    subtitle: const Text(
                      'iPhone guardians: install the ntfy app and subscribe to this topic. Tap to copy.',
                    ),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: topic));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                  ),
                ],
              );
            },
          ),
          const Divider(),
          StreamBuilder<List<Member>>(
            stream: _svc.members(groupId),
            builder: (context, snap) {
              final all = snap.data ?? [];
              final pending = all.where((m) => !m.active).toList();
              final active = all.where((m) => m.active).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending.isNotEmpty) ...[
                    const _Header('Waiting for approval'),
                    for (final m in pending) _PendingTile(m, groupId, _svc),
                  ],
                  const _Header('Members'),
                  for (final m in active)
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(m.name),
                      subtitle: Text(m.role == Role.admin ? 'admin' : 'member'),
                      trailing: m.role == Role.admin
                          ? null
                          : IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.person_remove),
                              onPressed: () =>
                                  _svc.removeMember(groupId, m.uid),
                            ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _PendingTile extends StatelessWidget {
  const _PendingTile(this.m, this.groupId, this.svc);
  final Member m;
  final String groupId;
  final GroupService svc;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.hourglass_empty),
    title: Text(m.name),
    subtitle: const Text('Wants to join'),
    trailing: Wrap(
      spacing: 4,
      children: [
        FilledButton(
          onPressed: () => svc.approve(groupId, m.uid, Role.guardian),
          child: const Text('Approve'),
        ),
        IconButton(
          tooltip: 'Reject',
          icon: const Icon(Icons.close),
          onPressed: () => svc.removeMember(groupId, m.uid),
        ),
      ],
    ),
  );
}
