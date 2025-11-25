// lib/services/edit_developer_profile_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditDeveloperProfilePage extends StatefulWidget {
  const EditDeveloperProfilePage({super.key});

  @override
  State<EditDeveloperProfilePage> createState() => _EditDeveloperProfilePageState();
}

class _EditDeveloperProfilePageState extends State<EditDeveloperProfilePage> {
  final supabase = Supabase.instance.client;

  final _bioCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _profileUrl;
  String? _bannerUrl;

  bool _loading = true;
  bool _saving = false;

  static const int _maxBytes = 2 * 1024 * 1024; // 2MB
  static const _allowedImageExt = ['png', 'jpg', 'jpeg', 'webp'];

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    final me = supabase.auth.currentUser;
    if (me == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final existing = await supabase
          .from('developers')
          .select('id, org_name, bio, website, contact_email, profile_picture_url, banner_url')
          .eq('id', me.id)
          .maybeSingle();

      if (existing != null) {
        _bioCtrl.text = existing['bio'] ?? '';
        _websiteCtrl.text = existing['website'] ?? '';
        _emailCtrl.text = existing['contact_email'] ?? '';
        _profileUrl = existing['profile_picture_url'];
        _bannerUrl = existing['banner_url'];
      } else {
        // Create one if not exists
        // Fetch username instead of email
        final profile = await supabase
            .from('profiles')
            .select('username')
            .eq('id', me.id)
            .maybeSingle();

        await supabase.from('developers').insert({
          'id': me.id,
          'org_name': profile?['username'] ?? 'Developer',
          'verified': false,
        });

      }
    } catch (e) {
      debugPrint('❌ load dev row: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validImageName(String name) {
    final lower = name.toLowerCase();
    return _allowedImageExt.any((ext) => lower.endsWith('.$ext'));
  }

  Future<String?> _pickAndUpload({required String objectPath}) async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: kIsWeb);
      if (res == null) return null;

      final f = res.files.first;

      // ✅ Validate extension
      if (!_validImageName(f.name)) {
        _snack('Please choose a PNG/JPG/JPEG/WEBP image.');
        return null;
      }

      // ✅ Validate size
      final int size = kIsWeb ? (f.bytes?.length ?? 0) : f.size;
      if (size == 0 || size > _maxBytes) {
        _snack('Image must be under 2 MB.');
        return null;
      }

      final bucket = supabase.storage.from('developer-assets');

      try {
        await bucket.remove([objectPath]);
      } catch (_) {}

      // ✅ Upload properly (no duplicate logic)
      if (kIsWeb) {
        await bucket.uploadBinary(
          objectPath,
          f.bytes!,
          fileOptions: const FileOptions(
            contentType: 'image/*',
            upsert: true,
          ),
        );
      } else {
        if (f.path == null) {
          _snack('Could not read file path.');
          return null;
        }
        await bucket.upload(
          objectPath,
          File(f.path!),
          fileOptions: const FileOptions(
            contentType: 'image/*',
            upsert: true,
          ),
        );
      }

      final publicUrl = bucket.getPublicUrl(objectPath);
      return publicUrl;
    } catch (e) {
      _snack('Upload failed: $e');
      return null;
    }
  }

  Future<void> _uploadProfile() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;

    final url = await _pickAndUpload(objectPath: '${me.id}/profile.png');
    if (url == null) return;

    await supabase.from('developers').update({
      'profile_picture_url': url,
    }).eq('id', me.id);

    setState(() => _profileUrl = url);
    _snack('✅ Profile picture updated.');
  }

  Future<void> _uploadBanner() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;

    final url = await _pickAndUpload(objectPath: '${me.id}/banner.jpg');
    if (url == null) return;

    await supabase.from('developers').update({
      'banner_url': url,
    }).eq('id', me.id);

    setState(() => _bannerUrl = url);
    _snack('✅ Banner updated.');
  }

  Future<void> _saveMeta() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;

    setState(() => _saving = true);

    await supabase.from('developers').update({
      'bio': _bioCtrl.text.trim(),
      'website': _websiteCtrl.text.trim(),
      'contact_email': _emailCtrl.text.trim(),
    }).eq('id', me.id);

    _snack('✅ Saved!');
    if (mounted) Navigator.pop(context, true);

    setState(() => _saving = false);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Developer Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ✅ Banner Upload UI
          AspectRatio(
            aspectRatio: 16 / 6,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    image: _bannerUrl == null
                        ? null
                        : DecorationImage(image: NetworkImage(_bannerUrl!), fit: BoxFit.cover),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: ElevatedButton.icon(
                    onPressed: _uploadBanner,
                    icon: const Icon(Icons.upload),
                    label: const Text('Upload Banner'),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ✅ Avatar Upload UI
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: _profileUrl == null ? null : NetworkImage(_profileUrl!),
                child: _profileUrl == null
                    ? const Icon(Icons.person, size: 36, color: Colors.black45)
                    : null,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _uploadProfile,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Upload Profile Picture'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ✅ Meta Fields
          TextField(
            controller: _bioCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Bio',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _websiteCtrl,
            decoration: const InputDecoration(
              labelText: 'Website (https://...)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Contact Email',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _saveMeta,
            icon: const Icon(Icons.save),
            label: _saving ? const Text('Saving...') : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
