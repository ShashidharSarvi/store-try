import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'profile_page.dart';
import 'add_app_page.dart';
import 'app_detail_page.dart';
import 'services/user_service.dart';

// Helper class for SliverPersistentHeader (Required for the sticky chips)
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _SliverAppBarDelegate({required this.minHeight, required this.maxHeight, required this.child});

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Ensuring the background color is correct when pinned
    return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SizedBox.expand(child: child)
    );
  }

  @override
  bool shouldRebuild(covariant _SliverAppBarDelegate oldDelegate) {
    return oldDelegate.maxHeight != maxHeight || oldDelegate.minHeight != minHeight || oldDelegate.child != child;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  String _searchQuery = "";
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadCategories(), _loadAppsWithRatings()]);
    await Future.delayed(const Duration(milliseconds: 200));
    setState(() => _loading = false);
  }

  Future<void> _loadCategories() async {
    try {
      final res = await supabase.from('categories').select().order('name');
      if (res is List) {
        _categories = res.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _categories = [];
      }
    } catch (e) {
      debugPrint('❌ Failed to load categories: $e');
      _categories = [];
    }
  }

  // ✅ Fixed: only fetch listed apps, sorted by created_at desc
  Future<void> _loadAppsWithRatings() async {
    try {
      final appsRes = await supabase
          .from('apps')
          .select('''
      id,
      name,
      description,
      icon_url,
      banner_url,
      banner_video_url,
      category_id,
      publisher_id,
      is_listed,
      created_at
    ''')
          .eq('is_listed', true)
          .order('created_at', ascending: false);

      if (appsRes is! List || appsRes.isEmpty) {
        _apps = [];
        return;
      }

      final rawApps = appsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final List<Map<String, dynamic>> enriched = [];

      for (final app in rawApps) {
        try {
          final appId = app['id'];
          final ratingsRes = await supabase.from('reviews').select('rating').eq('app_id', appId);

          double? avgRating;
          int ratingsCount = 0;

          if (ratingsRes is List && ratingsRes.isNotEmpty) {
            ratingsCount = ratingsRes.length;
            final sum = ratingsRes.fold<int>(0, (prev, item) {
              final r = (item as Map)['rating'];
              return prev + (r is int ? r : int.tryParse('$r') ?? 0);
            });
            avgRating = ratingsCount > 0 ? sum / ratingsCount : null;
          }

          enriched.add({
            ...app,
            'avg_rating': avgRating,
            'ratings_count': ratingsCount,
          });
        } catch (e) {
          debugPrint('❌ Rating load error for ${app['id']}: $e');
          enriched.add({...app, 'avg_rating': null, 'ratings_count': 0});
        }
      }

      _apps = enriched;
    } catch (e) {
      debugPrint('❌ Failed to load apps: $e');
      _apps = [];
    }
  }

  void _onRefresh() => _loadAll();

  List<Map<String, dynamic>> get _filteredApps {
    final q = _searchQuery.trim().toLowerCase();
    return _apps.where((app) {
      final name = (app['name'] ?? '').toString().toLowerCase();
      final desc = (app['description'] ?? '').toString().toLowerCase();
      final matchesSearch = q.isEmpty || name.contains(q) || desc.contains(q);
      final matchesCategory = _selectedCategoryId == null || app['category_id'] == _selectedCategoryId;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  int? _categoryIdByName(String name) {
    final match = _categories.firstWhere(
          (c) => (c['name'] ?? '').toString().toLowerCase() == name.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    if (match.isEmpty || match['id'] == null) return null;
    return match['id'] is int ? match['id'] as int : int.tryParse(match['id'].toString());
  }

  Widget _buildTopFilters() {
    final chips = <Widget>[
      Padding(
        padding: const EdgeInsets.only(left: 12), // Adjusted for horizontal spacing consistency
        child: ChoiceChip(
          label: const Text('All'),
          selected: _selectedCategoryId == null,
          onSelected: (_) => setState(() => _selectedCategoryId = null),
          selectedColor: const Color(0xFF6366F1),
          labelStyle: TextStyle(
            color: _selectedCategoryId == null ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: Colors.white.withOpacity(0.2),
        ),
      )
    ];

    for (final cat in _categories) {
      chips.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: ChoiceChip(
          label: Text(cat['name'] ?? ''),
          selected: _selectedCategoryId == cat['id'],
          onSelected: (_) => setState(() => _selectedCategoryId = cat['id'] as int?),
          selectedColor: const Color(0xFF6366F1),
          labelStyle: TextStyle(
            color: _selectedCategoryId == cat['id'] ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: Colors.white.withOpacity(0.2),
        ),
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Row(children: chips),
    );
  }

  Widget _buildBannerApp(Map<String, dynamic> app) {
    final image = app['video_thumbnail'] ?? app['icon_url'];
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailPage(app: app))),
      child: Container(
        width: 320,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          image: image != null
              ? DecorationImage(image: NetworkImage(image), fit: BoxFit.cover)
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [Colors.black.withOpacity(0.6), Colors.transparent],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                app['name'] ?? 'App Name',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppRow(String title, List<Map<String, dynamic>> apps) {
    if (apps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16), // Used 16 for better alignment
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16), // Used 16 for better alignment
              itemCount: apps.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildSmallAppTile(apps[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallAppTile(Map<String, dynamic> app) {
    final iconUrl = app['icon_url'];
    final rating = app['avg_rating']?.toStringAsFixed(1) ?? '—';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppDetailPage(app: app))),
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: iconUrl != null && iconUrl.isNotEmpty
                  ? Image.network(iconUrl, height: 80, width: 80, fit: BoxFit.cover)
                  : Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.apps, color: Colors.white54, size: 36),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              app['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 12),
                const SizedBox(width: 3),
                Text(rating, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannersSection() {
    final featured = _filteredApps.take(5).toList();
    if (featured.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 0), // Removed left padding here for list view padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              'Featured & Events',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16), // Applied list padding here
              itemCount: featured.length,
              itemBuilder: (_, i) => _buildBannerApp(featured[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------
  // NEW: Footer Links Section
  // ------------------------------
  Widget _buildFooterLinks(BuildContext context) {
    const textStyle = TextStyle(color: Colors.white70, fontSize: 12);
    const linkStyle = TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.underline);

    // Helper to build a column of links
    Widget buildLinkColumn(String title, List<String> links) {
      return Padding(
        padding: const EdgeInsets.only(right: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...links.map((link) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () {
                  // Handle link taps (e.g., launch a URL or navigate internally)
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tapped: $link')));
                },
                child: Text(link, style: textStyle.copyWith(color: Colors.white70)),
              ),
            )).toList(),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF121620), // Slightly darker footer background
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildLinkColumn(
                'Bock Store',
                ['Play Pass', 'Play Points', 'Gift cards', 'Redeem', 'Refund policy'],
              ),
              buildLinkColumn(
                'Children and family',
                ['Parent guide', 'Family sharing'],
              ),
              // Add more columns here if needed
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),

          // Bottom row (Terms, Privacy, Developers, Location)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    InkWell(onTap: () {}, child: Text('Terms of Service', style: linkStyle)),
                    InkWell(onTap: () {}, child: Text('Privacy', style: linkStyle)),
                    InkWell(onTap: () {}, child: Text('About Bock Store', style: linkStyle)),
                    InkWell(onTap: () {}, child: Text('Developers', style: linkStyle)),
                    InkWell(onTap: () {}, child: Text('All prices include GST.', style: textStyle)),
                  ],
                ),
              ),
              Row(
                children: [
                  Text('India (English [India])', style: textStyle),
                  const SizedBox(width: 8),
                  // Placeholder for a country flag/icon
                  const Icon(Icons.flag_rounded, color: Colors.white70, size: 16),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Calculate the height of the FlexibleSpaceBar content (16 padding + 42 search bar + 16 padding = 74)
    // PLUS the logo/icons row (which takes vertical space outside the search bar's 42 height)
    // We'll use 80 for the height based on the original design
    const double appBarHeight = 80;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C1E),
      floatingActionButton: FutureBuilder<String?>(
        future: UserService().getUserRole(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          if (snapshot.data == 'developer') {
            return FloatingActionButton(
              backgroundColor: const Color(0xFF4CAF50),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddAppPage()),
              ),
              child: const Icon(Icons.add),
            );
          }
          return const SizedBox();
        },
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : RefreshIndicator(
          onRefresh: () async => _onRefresh(),
          // CustomScrollView is used to combine the sticky header and the scrollable list
          child: CustomScrollView(
            slivers: [
              // 1. Pinned Top Bar (SliverAppBar)
              SliverAppBar(
                pinned: true, // This keeps the top bar visible
                automaticallyImplyLeading: false, // Prevents a back arrow if not needed
                backgroundColor: const Color(0xFF121620), // Use the specified dark color
                expandedHeight: appBarHeight,
                collapsedHeight: appBarHeight, // Set both to the same height to prevent collapsing
                flexibleSpace: FlexibleSpaceBar(
                  // The actual content of your top bar
                  background: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1B2735), Color(0xFF090A0F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'BOCK STORE',
                          style: TextStyle(
                            color: Color(0xFF80D8FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search, color: Colors.white70),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    onChanged: (v) => setState(() => _searchQuery = v),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      hintText: 'Search apps...',
                                      hintStyle: TextStyle(color: Colors.white54),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _onRefresh,
                                  icon: const Icon(Icons.refresh, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.person_outline, color: Colors.white),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProfilePage()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: () async {
                            await supabase.auth.signOut();
                            Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginPage()),
                                    (route) => false);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Sticky Category Chips (SliverPersistentHeader)
              if (_categories.isNotEmpty)
                SliverPersistentHeader(
                  pinned: true, // This makes the chips stick below the app bar
                  delegate: _SliverAppBarDelegate(
                    minHeight: 64,
                    maxHeight: 64,
                    child: Container(
                      color: const Color(0xFF0B0C1E), // The scaffold background color
                      child: _buildTopFilters(),
                    ),
                  ),
                ),

              // 3. Main Content (SliverToBoxAdapter)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildBannersSection(),
                    _buildAppRow("Top Free", _filteredApps.take(10).toList()),
                    _buildAppRow(
                      "Music & Audio",
                      _filteredApps.where((a) => a['category_id'] == _categoryIdByName("Music & Audio")).toList(),
                    ),
                    _buildAppRow(
                      "Productivity",
                      _filteredApps.where((a) => a['category_id'] == _categoryIdByName("Productivity")).toList(),
                    ),
                    _buildAppRow(
                      "Games",
                      _filteredApps.where((a) => a['category_id'] == _categoryIdByName("Games")).toList(),
                    ),
                    _buildAppRow(
                      "Social",
                      _filteredApps.where((a) => a['category_id'] == _categoryIdByName("Social")).toList(),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),

              // 4. Footer Links (SliverToBoxAdapter)
              SliverToBoxAdapter(
                child: _buildFooterLinks(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}