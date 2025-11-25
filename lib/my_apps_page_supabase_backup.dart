import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'add_app_page.dart';
import 'app_detail_page.dart';

class MyAppsPage extends StatefulWidget {
  const MyAppsPage({super.key});

  @override
  State<MyAppsPage> createState() => _MyAppsPageState();
}

class _MyAppsPageState extends State<MyAppsPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];

  @override
  void initState() {
    super.initState();
    _loadMyApps();
  }

  Future<void> _loadMyApps() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      final appsResponse = await supabase
          .from('apps')
          .select('id, name, description, icon_url')
          .eq('publisher_id', user.id);

      final appsList = List<Map<String, dynamic>>.from(appsResponse);

      for (var app in appsList) {
        final installsResponse = await supabase
            .from('installs')
            .select('id')
            .eq('app_id', app['id']);
        app['download_count'] = installsResponse.length;
      }

      setState(() => _apps = appsList);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading apps: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B2735),
        title: const Text(
          "My Apps",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: "Refresh",
            onPressed: _loadMyApps,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF80D8FF)),
            tooltip: "Add New App",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddAppPage()),
              ).then((_) => _loadMyApps());
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(color: Colors.white),
      )
          : _apps.isEmpty
          ? const Center(
        child: Text(
          "No apps yet.\nTap + to add your first one!",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _apps.length,
        itemBuilder: (context, index) {
          final app = _apps[index];
          final downloadCount = app['download_count'] ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2735),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppDetailPage(app: app),
                  ),
                ).then((_) => _loadMyApps());
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: app['icon_url'] != null
                          ? Image.network(
                        app['icon_url'],
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      )
                          : Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.apps,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app['name'] ?? 'Unnamed App',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            app['description'] ?? 'No description',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.download_rounded,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Downloads: $downloadCount",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}