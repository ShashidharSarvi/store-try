// lib/app_detail_page_full.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'services/bockstore_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDetailPage extends StatefulWidget {
  final Map<String, dynamic> app;

  const AppDetailPage({super.key, required this.app});

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  final PageController _screenshotController = PageController(viewportFraction: 0.9);
  final TextEditingController _commentController = TextEditingController();
  
  List<dynamic> _screenshots = [];
  List<dynamic> _reviews = [];
  List<dynamic> _versions = [];
  int _downloadCount = 0;
  int _rating = 5;
  bool _loading = true;
  bool _isOwner = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _screenshotController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      // Get current user
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token != null) {
        // Decode JWT to get user ID (simple base64 decode)
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          // Add padding if needed
          var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
          while (normalized.length % 4 != 0) {
            normalized += '=';
          }
          // In production, use a proper JWT library
          // For now, we'll just check if user is owner via API
        }
      }
      
      // Check if current user is owner
      _isOwner = false; // Will implement proper check later
      
      // Load all data in parallel
      final results = await Future.wait([
        BockStoreApi.getScreenshots(widget.app['id']),
        BockStoreApi.getReviews(widget.app['id']),
        BockStoreApi.getVersions(widget.app['id']),
        BockStoreApi.getDownloadCount(widget.app['id']),
      ]);
      
      setState(() {
        _screenshots = results[0] as List<dynamic>;
        _reviews = results[1] as List<dynamic>;
        _versions = results[2] as List<dynamic>;
        _downloadCount = results[3] as int;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _submitReview() async {
    if (_commentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a comment')),
      );
      return;
    }

    try {
      await BockStoreApi.submitReview(
        widget.app['id'],
        rating: _rating,
        comment: _commentController.text,
      );
      
      _commentController.clear();
      setState(() => _rating = 5);
      
      // Reload reviews
      final reviews = await BockStoreApi.getReviews(widget.app['id']);
      setState(() => _reviews = reviews);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Review submitted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    }
  }

  Future<void> _downloadApp(Map<String, dynamic> version) async {
    try {
      // Record download
      await BockStoreApi.recordDownload(
        widget.app['id'],
        versionId: version['id'],
        platform: version['platform'],
      );
      
      // Get download URL
      final downloadUrl = version['external_url'] ?? version['storage_key'];
      
      if (downloadUrl != null) {
        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      
      // Reload download count
      final count = await BockStoreApi.getDownloadCount(widget.app['id']);
      setState(() => _downloadCount = count);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📥 Download started!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    }
  }

  String _detectPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    final appName = (widget.app['name'] ?? 'App') as String;
    final appDesc = (widget.app['description'] ?? 'No description') as String;
    final appIcon = widget.app['icon_url'] as String?;
    final avgRating = widget.app['avg_rating']?.toStringAsFixed(1) ?? '—';
    final ratingsCount = widget.app['ratings_count'] ?? 0;

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0C1E),
        appBar: AppBar(
          title: Text(appName, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1B2735),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C1E),
      appBar: AppBar(
        title: Text(
          appName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF1B2735),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Header
            _buildAppHeader(appName, appIcon, avgRating, ratingsCount),
            
            // Stats Row
            _buildStatsRow(),
            
            // Install Button
            _buildInstallButton(),
            
            // Screenshots
            if (_screenshots.isNotEmpty) _buildScreenshots(),
            
            // Description
            _buildDescription(appDesc),
            
            // Reviews Section
            _buildReviewsSection(),
            
            // Versions (for developers)
            if (_isOwner && _versions.isNotEmpty) _buildVersionsSection(),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAppHeader(String name, String? icon, String rating, int count) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // App Icon
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: icon != null && icon.isNotEmpty
                ? Image.network(
                    icon,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildIconPlaceholder(),
                  )
                : _buildIconPlaceholder(),
          ),
          const SizedBox(width: 20),
          // App Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      rating,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($count)',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconPlaceholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.apps, color: Colors.white54, size: 48),
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            '${_downloadCount}+',
            'Downloads',
            Icons.download,
          ),
          _buildStatItem(
            '${_reviews.length}',
            'Reviews',
            Icons.rate_review,
          ),
          _buildStatItem(
            '${_versions.length}',
            'Versions',
            Icons.update,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildInstallButton() {
    final currentPlatform = _detectPlatform();
    final platformVersion = _versions.firstWhere(
      (v) => v['platform'] == currentPlatform,
      orElse: () => null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: platformVersion != null
              ? () => _downloadApp(platformVersion)
              : null,
          icon: const Icon(Icons.download),
          label: Text(
            platformVersion != null
                ? 'Install for ${currentPlatform.toUpperCase()}'
                : 'Not available for $currentPlatform',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: platformVersion != null
                ? const Color(0xFF4CAF50)
                : Colors.grey,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenshots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(
            'Screenshots',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _screenshotController,
            itemCount: _screenshots.length,
            itemBuilder: (context, index) {
              final screenshot = _screenshots[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    screenshot['image_url'],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.image, color: Colors.white54),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(String description) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this app',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reviews',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Submit Review Form
          _buildReviewForm(),
          
          const SizedBox(height: 24),
          
          // Reviews List
          if (_reviews.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No reviews yet. Be the first!',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ..._reviews.map((review) => _buildReviewCard(review)).toList(),
        ],
      ),
    );
  }

  Widget _buildReviewForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Write a review',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (index) {
              return IconButton(
                onPressed: () => setState(() => _rating = index + 1),
                icon: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Share your experience...',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _submitReview,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit Review'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue,
                child: Text(
                  (review['username'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['username'] ?? 'Anonymous',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < (review['rating'] ?? 0)
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 16,
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review['comment'] != null) ...[
            const SizedBox(height: 12),
            Text(
              review['comment'],
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionsSection() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Versions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._versions.map((version) => _buildVersionCard(version)).toList(),
        ],
      ),
    );
  }

  Widget _buildVersionCard(Map<String, dynamic> version) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _getPlatformIcon(version['platform']),
            color: Colors.white70,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${version['platform']} v${version['version']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Released: ${version['created_at']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _downloadApp(version),
            icon: const Icon(Icons.download, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.apple;
      case 'windows':
        return Icons.window;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      case 'web':
        return Icons.web;
      default:
        return Icons.devices;
    }
  }
}
