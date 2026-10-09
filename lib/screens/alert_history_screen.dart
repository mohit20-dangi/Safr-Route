import 'package:flutter/material.dart';

import '../services/alert_service.dart';

class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day}/${t.month}  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent alerts')),
      body: FutureBuilder<List<({DateTime at, String title, String body})>>(
        future: AlertService.history(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('No alerts on this phone yet.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active_rounded),
                      title: Text(a.title),
                      subtitle: Text('${a.body}\n${_fmt(a.at)}'),
                      isThreeLine: true,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
