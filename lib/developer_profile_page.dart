// lib/services/developer_profile_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_detail_page.dart';
import 'edit_developer_profile_page.dart';

class DeveloperProfilePage extends StatefulWidget {
  final String developerId;

  const DeveloperProfilePage({super.key, required this.developerId});

  @override
  State<DeveloperProfilePage> createState() => _DeveloperProfilePageState();
}

class _DeveloperProfilePageState extends State<DeveloperProfilePage> {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> _fetchDev() async {
    try {
      final dev = await supabase
          .from('developers')
          .select('id, org_name, bio, website, contact_email, profile_picture_url, banner_url')
          .eq('id', widget.developerId)
          .maybeSingle();

      final prof = await supabase
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', widget.developerId)
          .maybeSingle();

      String displayName = (prof?['display_name'] ??
          prof?['username'] ??
          dev?['org_name'] ??
          'Developer')
          .toString();

      final orgName = dev?['org_name'] as String?;
      if (orgName != null && orgName.isNotEmpty && !orgName.contains('@')) {
        displayName = orgName;
      }

      return {
        'id': widget.developerId,
        'org_name': displayName,
        'bio': dev?['bio'],
        'website': dev?['website'],
        'contact_email': dev?['contact_email'],
        'profile_picture_url': dev?['profile_picture_url'] ?? prof?['avatar_url'],
        'banner_url': dev?['banner_url'],
      };
    } catch (e) {
      debugPrint('❌ fetch dev: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchApps() async {
    try {
      final rows = await supabase
          .from('apps')
          .select('id, name, description, icon_url, publisher_id')
          .eq('publisher_id', widget.developerId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('❌ fetch apps: $e');
      return [];
    }
  }

  void _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser;

    return FutureBuilder(
      future: Future.wait([_fetchDev(), _fetchApps()]),
      builder: (context, AsyncSnapshot<List<dynamic>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0C1E),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        final dev = snap.data?[0] as Map<String, dynamic>?;
        final apps = (snap.data?[1] as List<Map<String, dynamic>>?) ?? [];
        final name = (dev?['org_name'] ?? 'Developer') as String;
        final bio = dev?['bio'] as String?;
        final website = dev?['website'] as String?;
        final email = dev?['contact_email'] as String?;
        final avatar = dev?['profile_picture_url'] as String?;
        final banner = dev?['banner_url'] as String?;
        final isOwner = me?.id == widget.developerId;

        return Scaffold(
          backgroundColor: const Color(0xFF0B0C1E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1B2735),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (isOwner)
                IconButton(
                  tooltip: 'Edit Profile',
                  icon: const Icon(Icons.edit, color: Color(0xFF80D8FF)),
                  onPressed: () async {
                    final changed = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditDeveloperProfilePage()),
                    );
                    if (changed == true && mounted) setState(() {});
                  },
                ),
            ],
          ),

          body: ListView(
            children: [
              // 🎬 Banner
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2735),
                        image: banner != null
                            ? DecorationImage(
                          image: NetworkImage(banner),
                          fit: BoxFit.cover,
                        )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: -40,
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 42,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                        (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                        child: (avatar == null || avatar.isEmpty)
                            ? const Icon(Icons.person, size: 40, color: Colors.black45)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // 🧩 Info Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2735),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (bio != null && bio.isNotEmpty)
                        Text(
                          bio,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (website != null && website.isNotEmpty)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF80D8FF)),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _openUrl(website),
                              icon: const Icon(Icons.public),
                              label: const Text("Website"),
                            ),
                          if (email != null && email.isNotEmpty)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF80D8FF)),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _openUrl('mailto:$email'),
                              icon: const Icon(Icons.mail),
                              label: const Text("Email"),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 💫 Apps section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "More by $name",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (apps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("No apps yet.", style: TextStyle(color: Colors.white70)),
                )
              else
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: apps.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final app = apps[i];
                      return _AppTileMini(
                        app: app,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AppDetailPage(app: app)),
                          );
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),
              // Removed the "Additional Information" section as it was replaced by the Info Card
            ],
          ),
        );
      },
    );
  }
}

class _AppTileMini extends StatelessWidget {
  final Map<String, dynamic> app;
  final VoidCallback onTap;

  const _AppTileMini({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final iconUrl = app['icon_url'] as String?;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1B2735),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: iconUrl != null && iconUrl.isNotEmpty
                  ? Image.network(iconUrl, height: 100, width: 100, fit: BoxFit.cover)
                  : Container(
                height: 100,
                width: 100,
                color: Colors.grey.shade800,
                child: const Icon(Icons.apps, color: Colors.white54, size: 40),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (app['name'] ?? 'App') as String,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}