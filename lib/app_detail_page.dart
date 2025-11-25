// lib/app_detail_page.dart
import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chewie/chewie.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- ADD THIS IMPORT for Clipboard
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'add_app_page.dart';
import 'developer_profile_page.dart'; // <-- for "Offered by" navigation

class AppDetailPage extends StatefulWidget {
  final Map<String, dynamic> app;

  const AppDetailPage({super.key, required this.app});

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;

  final PageController _pageController = PageController(viewportFraction: 0.9);
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);

  final _commentController = TextEditingController();
  int _rating = 5;

  String? _selectedPlatform;
  int _downloadCount = 0;
  bool _downloading = false;

  // ---- Trailer (MP4 inline or YouTube external) ----
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isMuted = true;
  bool _hasInlineVideo = false; // mp4 plays inline
  String? _youtubeUrl; // open externally
  String? _youtubeThumb; // show as background

  // ---- Developer meta (for "Offered by") ----
  Future<Map<String, dynamic>?>? _devFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // changed: _setupTrailer is now async and resolves storage keys into signed URLs when possible
    _setupTrailer();
    _loadDownloadCount();
    _devFuture = _fetchDeveloperMeta();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep video stable across lifecycle
    if (_videoController == null) return;
    if (state == AppLifecycleState.paused) {
      _videoController!.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_hasInlineVideo) _videoController!.play();
    }
  }

  // ------------------------------
  // NEW: Share Function
  // ------------------------------
  void _shareApp() {
    final appId = widget.app['id'];
    final appName = widget.app['name'] ?? 'This App';
    // Use a placeholder for the host, as the actual host/port is dynamic (localhost)
    // In production, replace 'bockstore.dev' with your public domain.
    const publicHost = 'http://bockstore.dev';
    final shareUrl = '$publicHost/app?id=$appId';

    // Copy URL to clipboard
    Clipboard.setData(ClipboardData(text: shareUrl));

    // Show confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔗 Link to $appName copied to clipboard: $shareUrl'),
      ),
    );
  }

  // ------------------------------
  // Developer meta
  // ------------------------------
  Future<Map<String, dynamic>?> _fetchDeveloperMeta() async {
    final devId = widget.app['publisher_id'] as String?;
    if (devId == null) return null;

    try {
      // Prefer developer.org_name if it is NOT an email. Otherwise fallback to profiles display_name/username.
      final dev = await supabase
          .from('developers')
          .select('id, org_name')
          .eq('id', devId)
          .maybeSingle();

      String? nameFromDevelopers;
      if (dev != null) {
        final org = dev['org_name'] as String?;
        if (org != null && org.isNotEmpty && !org.contains('@')) {
          nameFromDevelopers = org;
        }
      }

      if (nameFromDevelopers != null) {
        return {'id': devId, 'display': nameFromDevelopers};
      }

      // Fallback to profiles
      final prof = await supabase
          .from('profiles')
          .select('display_name, username')
          .eq('id', devId)
          .maybeSingle();

      final display = (prof?['display_name'] ??
          prof?['username'] ??
          'Developer') as String;

      return {'id': devId, 'display': display};
    } catch (e) {
      debugPrint('❌ fetch developer meta: $e');
      return null;
    }
  }
// ------------------------------
// Helper: Create Signed URL if File Exists
// ------------------------------
  Future<String?> _createSignedUrlIfExists(String bucket, String storageKey) async {
    try {
      final signed = await supabase.storage
          .from(bucket)
          .createSignedUrl(storageKey, 60 * 60); // valid for 1 hour
      return signed;
    } catch (e) {
      debugPrint('❌ createSignedUrl failed for $bucket/$storageKey: $e');
      return null;
    }
  }

  // ------------------------------
  // Trailer setup (MODIFIED)
  // ------------------------------
// Detect and initialize the correct trailer (YouTube or MP4)
  Future<void> _setupTrailer() async {
    final raw = (widget.app['banner_video_url'] as String?)?.trim();
    debugPrint("🎥 banner_video_url: $raw");

    _hasInlineVideo = false;
    _youtubeUrl = null;
    _youtubeThumb = null;

    if (raw == null || raw.isEmpty) {
      debugPrint("❌ No banner_video_url provided");
      if (mounted) setState(() {});
      return;
    }

    // ✅ Case 1: Direct URL (Supabase or YouTube)
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      if (_looksLikeMp4(raw)) {
        debugPrint("🎬 Detected direct MP4 link — initializing inline video");
        await _initInlineMp4(raw);
        return;
      }

      final ytId = _extractYouTubeId(raw);
      if (ytId != null && ytId.isNotEmpty) {
        debugPrint("📺 Detected YouTube video ($ytId)");
        _youtubeUrl = raw;
        _youtubeThumb = "https://img.youtube.com/vi/$ytId/hqdefault.jpg";
        _hasInlineVideo = false;
        if (mounted) setState(() {});
        return;
      }

      debugPrint("⚠️ Unknown link type: $raw");
      if (mounted) setState(() {});
      return;
    }

    // ✅ Case 2: Storage key — attempt to get signed URL
    String? signed;
    try {
      signed = await _createSignedUrlIfExists('app-media', raw);
    } catch (e) {
      debugPrint("⚠️ Error getting signed URL from app-media: $e");
    }

    if (signed == null) {
      try {
        signed = await _createSignedUrlIfExists('app-binaries', raw);
      } catch (e) {
        debugPrint("⚠️ Error getting signed URL from app-binaries: $e");
      }
    }

    if (signed != null) {
      if (_looksLikeMp4(signed)) {
        debugPrint("🎬 Signed MP4 detected — initializing inline video");
        await _initInlineMp4(signed);
        return;
      }

      final ytId = _extractYouTubeId(signed);
      if (ytId != null && ytId.isNotEmpty) {
        _youtubeUrl = signed;
        _youtubeThumb = "https://img.youtube.com/vi/$ytId/hqdefault.jpg";
        _hasInlineVideo = false;
        if (mounted) setState(() {});
        return;
      }
    }

    debugPrint("❌ No valid trailer found.");
    if (mounted) setState(() {});
  }

// Stronger MP4 detection — now supports Supabase public file URLs
  bool _looksLikeMp4(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.contains('/videos/') ||
        u.contains('/trailers/') ||
        u.contains('/app-media/') && u.contains('.mp4') ||
        u.contains('video/mp4') ||
        u.contains('content_type=video');
  }

  // Basic YouTube ID extraction for common formats
  String? _extractYouTubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.host.contains('youtube.com')) {
      // https://www.youtube.com/watch?v=VIDEO_ID
      if (uri.path.toLowerCase() == '/watch') {
        return uri.queryParameters['v'];
      }
      // /shorts/VIDEO_ID or /embed/VIDEO_ID or /live/VIDEO_ID
      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    }

    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return null;
  }

  Future<void> _initInlineMp4(String url) async {
    try {
      // Dispose old first (if hot reloading within same widget instance)
      _disposeInlineVideo();

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await _videoController!.initialize();

      // Loop, mute (for autoplay reliability), and play
      await _videoController!.setLooping(true);
      await _videoController!.setVolume(0.0);
      await _videoController!.play();

      // If the player unexpectedly pauses (e.g., buffering), try to resume.
      _videoController!.addListener(() {
        final ctrl = _videoController!;
        if (ctrl.value.hasError) return;
        if (!ctrl.value.isPlaying && ctrl.value.isInitialized && mounted) {
          // Don't force play when user paused; we only auto-resume if muted.
          if (_isMuted && _hasInlineVideo) {
            ctrl.play();
          }
        }
      });

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: true,
        showControls: false, // clean hero
        allowMuting: true,
        allowPlaybackSpeedChanging: false,
        allowFullScreen: true,
      );

      if (mounted) {
        setState(() {
          _hasInlineVideo = true;
          _isMuted = true;
        });
      }
    } catch (e) {
      debugPrint('❌ inline video init failed: $e');
      _disposeInlineVideo();
      if (mounted) {
        setState(() {
          _hasInlineVideo = false;
        });
      }
    }
  }

  void _toggleMute() async {
    if (_videoController == null) return;
    final nowMuted = !_isMuted;
    setState(() => _isMuted = nowMuted);
    await _videoController!.setVolume(nowMuted ? 0.0 : 1.0);
  }

  void _disposeInlineVideo() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _currentPage.dispose();
    _commentController.dispose();
    _disposeInlineVideo();
    super.dispose();
  }

  // ------------------------------
  // Downloads: count + record + URL
  // ------------------------------
  Future<void> _loadDownloadCount() async {
    try {
      final rows = await supabase
          .from('installs')
          .select('id')
          .eq('app_id', widget.app['id']);
      if (mounted) setState(() => _downloadCount = rows.length);
    } catch (e) {
      debugPrint("❌ Error loading download count: $e");
    }
  }

  Future<void> _recordDownload(String versionId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ You must be signed in to download")),
      );
      return;
    }
    final platform = _detectPlatform();

    try {
      await supabase.from('installs').insert({
        'app_id': widget.app['id'],
        'version_id': versionId,
        'user_id': user.id,
        'platform': platform,
      });
      await _loadDownloadCount();
    } catch (e) {
      debugPrint("❌ Failed to record download: $e");
    }
  }

  Future<String?> _getSignedUrl(String storageKey) async {
    try {
      final signedUrl = await supabase.storage
          .from('app-binaries')
          .createSignedUrl(storageKey, 60 * 60);
      return signedUrl;
    } catch (e) {
      debugPrint("❌ Error generating signed URL: $e");
      return null;
    }
  }

  // ------------------------------
  // Upload: per-platform (strict)
  // ------------------------------
  static const _platforms = <String>[
    'android',
    'windows',
    'macos',
    'linux',
    'ios',
    'web',
  ];

  static const _platformLabels = <String, String>{
    'android': 'Upload Android',
    'windows': 'Upload Windows',
    'macos': 'Upload macOS',
    'linux': 'Upload Linux',
    'ios': 'Upload iOS',
    'web': 'Upload Web',
  };

  static const _allowedExt = <String, List<String>>{
    'android': ['apk', 'aab'],
    'windows': ['exe'],
    'macos': ['dmg', 'zip'],
    'linux': ['deb', 'appimage', 'tar.gz'],
    'ios': ['ipa'],
    'web': ['zip'],
  };

  bool _isValidExtension(String platform, String filename) {
    final name = filename.toLowerCase();
    final allow = _allowedExt[platform] ?? [];
    for (final ext in allow) {
      if (ext == 'tar.gz') {
        if (name.endsWith('.tar.gz')) return true;
      } else if (name.endsWith('.$ext')) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _promptVersion() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Version'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Version (e.g. 1.1.0)",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _uploadBinaryForPlatform(String platform) async {
    final version = await _promptVersion();
    if (version == null || version.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Version is required")),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    String fileName;
    Uint8List? binaryBytes;
    File? binaryFile;

    if (kIsWeb) {
      binaryBytes = result.files.first.bytes;
      fileName = result.files.first.name;
    } else {
      final path = result.files.single.path!;
      binaryFile = File(path);
      fileName = result.files.single.name;
    }

    if (!_isValidExtension(platform, fileName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Invalid file type for $platform")),
      );
      return;
    }

    try {
      final storagePath =
          "binaries/${widget.app['id']}/${platform}_${DateTime.now().millisecondsSinceEpoch}_$fileName";

      if (kIsWeb) {
        await supabase.storage.from('app-binaries').uploadBinary(
          storagePath,
          binaryBytes!,
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );
      } else {
        await supabase.storage.from('app-binaries').upload(
          storagePath,
          binaryFile!,
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );
      }

      await supabase.from('app_versions').insert({
        'app_id': widget.app['id'],
        'version': version,
        'platform': platform,
        'storage_key': storagePath,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Uploaded $platform $version")),
        );
        setState(() {}); // refresh list
      }
    } catch (e) {
      debugPrint("❌ Upload failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Upload failed: $e")),
      );
    }
  }

  Future<void> _uploadWindowsFlow() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text("Windows Upload"),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'file'),
            child: const Text("Upload .exe file"),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'url'),
            child: const Text("Paste external download URL"),
          ),
        ],
      ),
    );

    if (choice == 'file') {
      await _uploadBinaryForPlatform('windows');
      return;
    }
    if (choice == 'url') {
      final version = await _promptVersion();
      if (version == null || version.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ Version is required")),
        );
        return;
      }

      final urlController = TextEditingController();
      final url = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Windows External URL'),
          content: TextField(
            controller: urlController,
            decoration: const InputDecoration(
              hintText: "https://example.com/yourfile.exe",
              labelText: "Download URL (https)",
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, urlController.text.trim()), child: const Text('Save')),
          ],
        ),
      );

      if (url == null || url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Please enter a valid URL")),
        );
        return;
      }
      final parsed = Uri.tryParse(url);
      if (parsed == null || !(parsed.isScheme('http') || parsed.isScheme('https'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ URL must start with http or https")),
        );
        return;
      }

      try {
        await supabase.from('app_versions').insert({
          'app_id': widget.app['id'],
          'version': version,
          'platform': 'windows',
          'storage_key': null,
          'external_url': url,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Windows URL saved")),
          );
          setState(() {});
        }
      } catch (e) {
        debugPrint("❌ Failed to save windows URL: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Failed to save URL: $e")),
        );
      }
    }
  }

  String _detectPlatform() {
    if (kIsWeb) return "web";
    if (Platform.isAndroid) return "android";
    if (Platform.isIOS) return "ios";
    if (Platform.isWindows) return "windows";
    if (Platform.isMacOS) return "macos";
    if (Platform.isLinux) return "linux";
    return "unknown";
  }

  Future<void> _submitReview() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ You must be logged in to review")),
      );
      return;
    }
    if (user.id == widget.app['publisher_id']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🚫 Developers cannot review their own apps")),
      );
      return;
    }

    try {
      await supabase.from("reviews").upsert({
        'app_id': widget.app['id'],
        'user_id': user.id,
        'rating': _rating,
        'comment': _commentController.text,
      }, onConflict: 'app_id,user_id');

      _commentController.clear();
      if (mounted) setState(() {}); // refresh
    } catch (e) {
      debugPrint("❌ Failed to submit review: $e");
    }
  }

  Future<List<Map<String, dynamic>>> _fetchVersions() {
    return supabase
        .from('app_versions')
        .select('id, app_id, version, platform, storage_key, external_url, created_at')
        .eq('app_id', widget.app['id'])
        .order('created_at', ascending: false);
  }

  void _goUpdateApp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAppPage(app: widget.app)),
    ).then((changed) {
      if (changed == true) setState(() {});
    });
  }

  // ------------------------------
  // NEW: Play Store Style Stats Row
  // ------------------------------
  Widget _buildStatsRow(BuildContext context) {
    final avgRating = widget.app['avg_rating']?.toStringAsFixed(1) ?? '—';
    final ratingsCount = widget.app['ratings_count'] ?? 0;
    final downloads = _downloadCount;
    // NOTE: 'age_rating' key is assumed; use a safe default if not found in your app map
    final ageRating = widget.app['age_rating'] ?? '3+';

    String formatDownloads(int count) {
      if (count >= 1000000) {
        return '${(count / 1000000).toStringAsFixed(1)}M+';
      } else if (count >= 10000) {
        return '${(count / 1000).floor()}K+';
      }
      return '${count}+';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: IntrinsicHeight( // Ensures all dividers match the height of the tallest item
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1. Rating
            Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        avgRating,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Icon(Icons.star, color: Colors.white70, size: 20),
                    ],
                  ),
                  Text(
                    '${ratingsCount} reviews',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const VerticalDivider(width: 20, thickness: 1, color: Colors.white12),

            // 2. Downloads
            Expanded(
              child: Column(
                children: [
                  Text(
                    formatDownloads(downloads),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Downloads',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const VerticalDivider(width: 20, thickness: 1, color: Colors.white12),

            // 3. Content Rating (Age Restriction)
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ageRating,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Text(
                    'Rated for',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------
  // UI
  // ------------------------------
  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser;
    final isOwner = currentUser != null && currentUser.id == widget.app['publisher_id'];

    final appName = (widget.app['name'] ?? '') as String? ?? '';
    final appDesc = (widget.app['description'] ?? '') as String? ?? '';
    final appIcon = widget.app['icon_url'] as String?;
    final bannerUrl = widget.app['banner_url'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C1E),
      appBar: AppBar(
        title: Text(appName.isEmpty ? "App" : appName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1B2735),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // ⭐ NEW: Share Button (always visible)
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: "Share App Link",
            onPressed: _shareApp, // Calls the new share function
          ),

          if (isOwner)
            IconButton(
              icon: const Icon(Icons.edit, color: Color(0xFF80D8FF)),
              tooltip: "Update App",
              onPressed: _goUpdateApp,
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              tooltip: "Delete App",
              onPressed: () async {
                try {
                  await supabase.from("apps").delete().eq("id", widget.app['id']);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ App deleted successfully")),
                    );
                    Navigator.pop(context, true);
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("❌ Error deleting app: $e")),
                  );
                }
              },
            ),
        ],
      ),

      // 🖤 Unified theme layout
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchVersions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          final versions = snapshot.data ?? [];
          final availablePlatforms =
          versions.map((v) => v['platform'] as String).toSet().toList();

          // Retain detection logic from original, but use the state variable
          _selectedPlatform ??= () {
            final detected = _detectPlatform();
            if (availablePlatforms.contains(detected)) return detected;
            return availablePlatforms.isNotEmpty ? availablePlatforms.first : null;
          }();


          final selectedVersion = (versions.isNotEmpty && _selectedPlatform != null)
              ? versions.firstWhere(
                (v) => v['platform'] == _selectedPlatform,
            orElse: () => versions.first,
          )
              : null;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B0C1E), Color(0xFF1B2735)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: ListView(
              children: [
                // 🎬 Hero section with video/banner
                _HeroSection(
                  hasInlineVideo: _hasInlineVideo,
                  chewie: _chewieController,
                  isMuted: _isMuted,
                  onToggleMute: _toggleMute,
                  bannerUrl: bannerUrl,
                  iconUrl: appIcon,
                  appName: appName,
                  youtubeThumb: _youtubeThumb,
                  youtubeUrl: _youtubeUrl,
                ),

                // 🔤 App name + desc
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appDesc,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      // NOTE: Removed old "Downloads: $_downloadCount" line here
                    ],
                  ),
                ),

                // ⭐ NEW: Play Store Stats Row
                _buildStatsRow(context),

                // 🧑‍💻 Developer info
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2735),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: FutureBuilder<Map<String, dynamic>?>(
                    future: _devFuture,
                    builder: (context, snap) {
                      final devName = (snap.data?['display'] as String?) ?? 'Developer';
                      return Row(
                        children: [
                          const Icon(Icons.verified_user, color: Colors.white54),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Offered by $devName",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // Retain navigation from original
                          InkWell(
                            onTap: () {
                              final devId = widget.app['publisher_id'] as String?;
                              if (devId == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DeveloperProfilePage(developerId: devId),
                                ),
                              );
                            },
                            child: const Icon(Icons.chevron_right, color: Colors.white54),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // 🧩 Manage builds section (for developer)
                if (isOwner)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: Colors.white30),
                        const Text(
                          "Manage Builds",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _platforms.map((p) {
                            return ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E3A59),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                if (p == 'windows') {
                                  await _uploadWindowsFlow();
                                } else {
                                  await _uploadBinaryForPlatform(p);
                                }
                                if (mounted) setState(() {});
                              },
                              icon: Icon(_platformIcon(p)),
                              label: Text(_platformLabels[p] ?? p.toUpperCase()),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // 📥 Download section
                if (availablePlatforms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text("No builds available yet.", style: TextStyle(color: Colors.white70)),
                  )
                else if (selectedVersion != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2735),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Available Platforms",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButton<String>(
                            value: _selectedPlatform,
                            dropdownColor: const Color(0xFF1B2735),
                            iconEnabledColor: Colors.white,
                            items: availablePlatforms
                                .map((p) => DropdownMenuItem<String>(
                              value: p,
                              child: Text(
                                p.toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ))
                                .toList(),
                            onChanged: (val) => setState(() => _selectedPlatform = val),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            onPressed: _downloading
                                ? null
                                : () async {
                              setState(() => _downloading = true);
                              final vId = selectedVersion['id'] as String;
                              final extUrl =
                              selectedVersion['external_url'] as String?;
                              final storageKey =
                              selectedVersion['storage_key'] as String?;
                              String? launchUrlStr;
                              if (extUrl != null && extUrl.isNotEmpty) {
                                launchUrlStr = extUrl;
                              } else if (storageKey != null &&
                                  storageKey.isNotEmpty) {
                                launchUrlStr =
                                await _getSignedUrl(storageKey);
                              }
                              if (launchUrlStr != null) {
                                await _recordDownload(vId);
                                launchUrl(Uri.parse(launchUrlStr),
                                    mode:
                                    LaunchMode.externalApplication);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("⚠️ No download available for this platform"),
                                  ),
                                );
                              }
                              if (mounted) setState(() => _downloading = false);
                            },
                            icon: const Icon(Icons.download),
                            label: Text(
                              "Download for ${_selectedPlatform?.toUpperCase()}",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // 🖼️ Screenshots (re-styled for dark mode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: supabase
                        .from('screenshots')
                        .select()
                        .eq('app_id', widget.app['id'])
                        .order('sort_order', ascending: true),
                    builder: (context, ssSnapshot) {
                      if (ssSnapshot.hasError) {
                        return Text("⚠️ Failed to load screenshots: ${ssSnapshot.error}",
                            style: const TextStyle(color: Colors.redAccent));
                      }
                      if (ssSnapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      final screenshots = ssSnapshot.data ?? [];
                      if (screenshots.isEmpty) {
                        return const Text("No screenshots uploaded.", style: TextStyle(color: Colors.white70));
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Screenshots",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 300,
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: screenshots.length,
                              onPageChanged: (i) => _currentPage.value = i,
                              itemBuilder: (_, index) {
                                final shot = screenshots[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      shot['url'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                      const Center(child: Text("⚠️ Failed to load image", style: TextStyle(color: Colors.white))),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<int>(
                            valueListenable: _currentPage,
                            builder: (_, currentPage, __) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(screenshots.length, (i) {
                                  final active = currentPage == i;
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: active ? 10 : 8,
                                    height: active ? 10 : 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: active ? const Color(0xFF80D8FF) : Colors.white38,
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // ⭐ Reviews (re-styled for dark mode)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "User Reviews",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: supabase
                        .from("reviews")
                        .select(
                      "id, rating, comment, created_at, profiles!reviews_user_id_fkey(username)",
                    )
                        .eq("app_id", widget.app['id'])
                        .order("created_at", ascending: false),
                    builder: (context, rsSnapshot) {
                      if (rsSnapshot.hasError) {
                        return Text("⚠️ Error: ${rsSnapshot.error}", style: const TextStyle(color: Colors.redAccent));
                      }
                      if (rsSnapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }

                      final reviews = rsSnapshot.data ?? [];
                      if (reviews.isEmpty) {
                        return const Text("No reviews yet. Be the first!", style: TextStyle(color: Colors.white70));
                      }

                      final avg = reviews
                          .map((r) => r['rating'] as int)
                          .fold<int>(0, (a, b) => a + b) /
                          reviews.length;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "⭐ ${avg.toStringAsFixed(1)} (${reviews.length} reviews)",
                            style: const TextStyle(
                              color: Color(0xFFF9A825), // Gold-ish color for stars
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...reviews.map((r) {
                            final createdAt =
                            DateTime.tryParse(r['created_at'] ?? "");
                            final timeAgo = createdAt != null
                                ? timeago.format(createdAt, locale: 'en_short')
                                : "";
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B2735),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "${r['profiles']?['username'] ?? "Anonymous"} - ⭐ ${r['rating']}",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (timeAgo.isNotEmpty)
                                        Text(
                                          timeAgo,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white54,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    r['comment'] ?? "No comment provided.",
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  ),
                ),

                const Divider(color: Colors.white30),

                // ➕ Add Review (re-styled for dark mode)
                if (supabase.auth.currentUser != null &&
                    supabase.auth.currentUser!.id != widget.app['publisher_id'])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Add Your Review",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            DropdownButton<int>(
                              value: _rating,
                              dropdownColor: const Color(0xFF1B2735),
                              iconEnabledColor: Colors.white,
                              items: List.generate(5, (i) => i + 1)
                                  .map(
                                    (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text("⭐ $v",
                                      style:
                                      const TextStyle(color: Colors.white)),
                                ),
                              )
                                  .toList(),
                              onChanged: (val) => setState(() => _rating = val ?? 5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: "Write a comment...",
                                  hintStyle: TextStyle(color: Colors.white54),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send, color: Color(0xFF80D8FF)),
                              onPressed: _submitReview,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _platformIcon(String p) {
    switch (p) {
      case 'android':
        return Icons.android;
      case 'windows':
        return Icons.window;
      case 'macos':
        return Icons.apple;
      case 'linux':
        return Icons.laptop;
      case 'ios':
        return Icons.phone_iphone;
      case 'web':
        return Icons.public;
      default:
        return Icons.devices;
    }
  }
}

// ======== HERO WIDGET (No change) ========
class _HeroSection extends StatelessWidget {
  final bool hasInlineVideo; // mp4
  final ChewieController? chewie;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final String? bannerUrl;
  final String? iconUrl;
  final String appName;
  final String? youtubeThumb;
  final String? youtubeUrl;

  const _HeroSection({
    required this.hasInlineVideo,
    required this.chewie,
    required this.isMuted,
    required this.onToggleMute,
    required this.bannerUrl,
    required this.iconUrl,
    required this.appName,
    required this.youtubeThumb,
    required this.youtubeUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasYouTube = youtubeUrl != null && youtubeUrl!.isNotEmpty;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🎬 Background priority: inline video → YouTube thumbnail → banner image → blurred icon
          if (hasInlineVideo && chewie != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: chewie!.videoPlayerController.value.size.width,
                height: chewie!.videoPlayerController.value.size.height,
                child: Chewie(controller: chewie!),
              ),
            )
          else if (hasYouTube && youtubeThumb != null)
            Image.network(youtubeThumb!, fit: BoxFit.cover)
          else if (bannerUrl != null && bannerUrl!.isNotEmpty)
              Image.network(bannerUrl!, fit: BoxFit.cover)
            else
              _BlurredIconFallback(iconUrl: iconUrl),

          // 🎨 Dark gradient for overlay readability
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black54, Colors.black87],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // 🔇 Mute toggle button for inline video
          if (hasInlineVideo && chewie != null)
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                backgroundColor: Colors.black54,
                onPressed: onToggleMute,
                child: Icon(
                  isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
            ),

          // ▶️ YouTube "Play trailer" button
          if (hasYouTube && youtubeUrl != null)
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.7),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => launchUrl(
                  Uri.parse(youtubeUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.play_circle_fill, size: 32),
                label: const Text("Watch trailer"),
              ),
            ),

          // 🧩 App icon and title at bottom (like Play Store)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HeroIcon(iconUrl: iconUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurredIconFallback extends StatelessWidget {
  final String? iconUrl;

  const _BlurredIconFallback({required this.iconUrl});

  @override
  Widget build(BuildContext context) {
    if (iconUrl == null || iconUrl!.isEmpty) {
      return Container(color: Colors.grey.shade300);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(iconUrl!, fit: BoxFit.cover),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(color: Colors.black.withOpacity(0.15)),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroIcon extends StatelessWidget {
  final String? iconUrl;

  const _HeroIcon({required this.iconUrl});

  @override
  Widget build(BuildContext context) {
    const double size = 64;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: size,
        height: size,
        color: Colors.white10,
        child: (iconUrl != null && iconUrl!.isNotEmpty)
            ? Image.network(iconUrl!, fit: BoxFit.cover)
            : const Icon(Icons.apps, size: 40, color: Colors.white70),
      ),
    );
  }
}