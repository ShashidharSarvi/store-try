import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/user_service.dart';

class AddAppPage extends StatefulWidget {
  final Map<String, dynamic>? app; // null => Add, not null => Update

  const AddAppPage({super.key, this.app});

  @override
  State<AddAppPage> createState() => _AddAppPageState();
}

class _AddAppPageState extends State<AddAppPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // 🆕 New: Banner-related fields
  File? _bannerImageFile;
  Uint8List? _bannerImageBytes;
  String? _bannerImageUrl;
  String? _bannerImageName;

  File? _bannerVideoFile;
  Uint8List? _bannerVideoBytes;
  String? _bannerVideoUrl;
  String? _bannerVideoName;

  final _youtubeLinkController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

  final List<String> _platforms = ["android", "ios", "windows", "macos", "linux", "web"];
  Map<String, PlatformFile?> _platformBinaries = {}; // {platform: file}

  File? _iconFile;
  Uint8List? _iconBytes;
  String? _iconUrl;

  List<File> _screenshotFiles = [];
  List<Uint8List> _screenshotBytes = [];
  List<String> _screenshotNames = [];

  bool _loading = false;
  String? _errorMessage;

  bool get isUpdateMode => widget.app != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();

    if (isUpdateMode) {
      _nameController.text = widget.app!['name'] ?? "";
      _descriptionController.text = widget.app!['description'] ?? "";
      _selectedCategoryId = widget.app!['category_id'];
      _iconUrl = widget.app!['icon_url'];
      _bannerImageUrl = widget.app!['banner_url'];
      _bannerVideoUrl = widget.app!['banner_video_url'];
    }
  }

  Future<void> _loadCategories() async {
    try {
      final response = await http.get(
        Uri.parse('http://52.66.201.185:3000/api/categories'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _categories = (data['categories'] as List).map((cat) => {
            'id': int.parse(cat['id'].toString()),
            'name': cat['name'].toString(),
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("❌ Failed to load categories: $e");
      setState(() => _categories = []);
    }
  }

  Future<void> _pickIcon() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _iconBytes = bytes;
          _iconFile = null;
        });
      } else {
        setState(() {
          _iconFile = File(picked.path);
          _iconBytes = null;
        });
      }
    }
  }

  Future<void> _pickBannerImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _bannerImageBytes = bytes;
        _bannerImageFile = null;
        _bannerImageName = picked.name;
      });
    } else {
      setState(() {
        _bannerImageFile = File(picked.path);
        _bannerImageBytes = null;
        _bannerImageName = picked.name;
      });
    }
  }

  Future<void> _pickBannerVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null) return;
    final file = result.files.single;

    if (kIsWeb) {
      setState(() {
        _bannerVideoBytes = file.bytes;
        _bannerVideoFile = null;
        _bannerVideoName = file.name;
      });
    } else {
      setState(() {
        _bannerVideoFile = File(file.path!);
        _bannerVideoBytes = null;
        _bannerVideoName = file.name;
      });
    }
  }

  Future<void> _pickBinary(String platform) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    setState(() => _platformBinaries[platform] = result.files.single);
  }

  // ✅ FIXED: Upload to 'app-binaries' bucket consistently
  Future<String?> _uploadBinary(String appId, String platform, PlatformFile file) async {
    final supabase = Supabase.instance.client;
    try {
      final fileName = "${platform}_${DateTime.now().millisecondsSinceEpoch}_${file.name}";
      final storagePath = "binaries/$appId/$fileName";

      if (kIsWeb) {
        await supabase.storage.from('app-binaries').uploadBinary(
          storagePath,
          file.bytes!,
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );
      } else {
        await supabase.storage.from('app-binaries').upload(
          storagePath,
          File(file.path!),
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );
      }

      return storagePath;
    } catch (e) {
      debugPrint("❌ Upload failed for $platform: $e");
      return null;
    }
  }

  Future<void> _pickScreenshots() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image);
    if (result != null) {
      if (kIsWeb) {
        setState(() {
          _screenshotBytes = result.files.map((f) => f.bytes!).toList();
          _screenshotNames = result.files.map((f) => f.name).toList();
          _screenshotFiles = [];
        });
      } else {
        setState(() {
          _screenshotFiles = result.paths.map((p) => File(p!)).toList();
          _screenshotNames = result.files.map((f) => f.name).toList();
        });
      }
    }
  }

  Future<void> _submitApp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      setState(() => _errorMessage = "⚠️ Please select a category");
      return;
    }

    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => _errorMessage = "Not logged in");
      return;
    }

    try {
      final slug =
          "${_nameController.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(' ', '-')}-${DateTime.now().millisecondsSinceEpoch}";

      // 1️⃣ Upload icon
      String? iconUrl = _iconUrl;
      if (_iconFile != null || _iconBytes != null) {
        final path = "icons/${DateTime.now().millisecondsSinceEpoch}_${_nameController.text}.png";
        if (kIsWeb) {
          await supabase.storage.from('app-media').uploadBinary(
            path,
            _iconBytes!,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
        } else {
          await supabase.storage.from('app-media').upload(
            path,
            _iconFile!,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
        }
        iconUrl = supabase.storage.from('app-media').getPublicUrl(path);
      }

      // 2️⃣ Upload banner image
      String? bannerImageUrl;
      if (_bannerImageFile != null || _bannerImageBytes != null) {
        final path = "banners/${DateTime.now().millisecondsSinceEpoch}_${_bannerImageName}";
        if (kIsWeb) {
          await supabase.storage.from('app-media').uploadBinary(
            path,
            _bannerImageBytes!,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
        } else {
          await supabase.storage.from('app-media').upload(
            path,
            _bannerImageFile!,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
        }
        bannerImageUrl = supabase.storage.from('app-media').getPublicUrl(path);
      }

      // 3️⃣ Upload banner video or YouTube link
      String? bannerVideoUrl;
      if (_bannerVideoFile != null || _bannerVideoBytes != null) {
        final path = "videos/${DateTime.now().millisecondsSinceEpoch}_${_bannerVideoName}";
        if (kIsWeb) {
          await supabase.storage.from('app-media').uploadBinary(
            path,
            _bannerVideoBytes!,
            fileOptions: const FileOptions(contentType: 'video/mp4'),
          );
        } else {
          await supabase.storage.from('app-media').upload(
            path,
            _bannerVideoFile!,
            fileOptions: const FileOptions(contentType: 'video/mp4'),
          );
        }
        bannerVideoUrl = supabase.storage.from('app-media').getPublicUrl(path);
      }

      // fallback to YouTube link
      if ((bannerVideoUrl == null || bannerVideoUrl.isEmpty) &&
          _youtubeLinkController.text.isNotEmpty) {
        bannerVideoUrl = _youtubeLinkController.text.trim();
      }

      // 4️⃣ Insert app base record
      final insertedApp = await supabase.from('apps').insert({
        'slug': slug,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'publisher_id': user.id,
        'icon_url': iconUrl,
        'category_id': _selectedCategoryId,
        'banner_url': bannerImageUrl,
        'banner_video_url': bannerVideoUrl,
        'is_listed': true,
      }).select().single();

      final appId = insertedApp['id'].toString();

      // 5️⃣ Upload binaries (multi-platform)
      for (final entry in _platformBinaries.entries) {
        final file = entry.value;
        if (file != null) {
          final path = await _uploadBinary(appId, entry.key, file);
          if (path != null) {
            await supabase.from('app_versions').insert({
              'app_id': appId,
              'version': '1.0.0',
              'platform': entry.key,
              'storage_key': path,
            });
          }
        }
      }

      // 6️⃣ Upload screenshots
      await _uploadScreenshots(appId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ App added successfully")),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _uploadScreenshots(String appId) async {
    final supabase = Supabase.instance.client;
    for (var i = 0; i < _screenshotNames.length; i++) {
      final path = "screenshots/${DateTime.now().millisecondsSinceEpoch}_${_screenshotNames[i]}";
      if (kIsWeb) {
        await supabase.storage.from('app-media').uploadBinary(
          path,
          _screenshotBytes[i],
          fileOptions: const FileOptions(contentType: 'image/png'),
        );
      } else {
        await supabase.storage.from('app-media').upload(
          path,
          _screenshotFiles[i],
          fileOptions: const FileOptions(contentType: 'image/png'),
        );
      }
      final publicUrl = supabase.storage.from('app-media').getPublicUrl(path);

      await supabase.from('screenshots').insert({
        'app_id': appId,
        'storage_key': path,
        'url': publicUrl,
        'sort_order': i,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget iconPreview = _iconBytes != null
        ? Image.memory(_iconBytes!, width: 50, height: 50)
        : _iconFile != null
        ? Image.file(_iconFile!, width: 50, height: 50)
        : _iconUrl != null
        ? Image.network(_iconUrl!, width: 50, height: 50)
        : const Icon(Icons.image, size: 50);

    return Scaffold(
      appBar: AppBar(title: const Text("Add New App"), backgroundColor: const Color(0xFF1B2735)),
      backgroundColor: const Color(0xFF0B0C1E),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "App Name"),
                validator: (v) => v == null || v.isEmpty ? "Enter app name" : null,
              ),
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Description"),
                validator: (v) => v == null || v.isEmpty ? "Enter description" : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                value: _selectedCategoryId,
                dropdownColor: const Color(0xFF1B2735),
                items: _categories
                    .map<DropdownMenuItem<int>>(
                        (cat) => DropdownMenuItem<int>(
                      value: cat['id'] as int,
                      child: Text(cat['name'],
                          style:
                          const TextStyle(color: Colors.white)),
                    ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategoryId = val),
                decoration: const InputDecoration(labelText: "Category"),
              ),
              const SizedBox(height: 20),
              Row(children: [
                iconPreview,
                const SizedBox(width: 10),
                ElevatedButton(onPressed: _pickIcon, child: const Text("Pick Icon")),
              ]),
              const Divider(color: Colors.white30, height: 40),

              // 🖼 Banner Image Upload
              const Text("🖼 Banner Image",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _pickBannerImage,
                child:
                Text(_bannerImageName ?? "Upload Banner Image"),
              ),
              const SizedBox(height: 20),

              // 🎬 Banner Video Upload or YouTube
              const Text("🎬 Banner Video",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _pickBannerVideo,
                child:
                Text(_bannerVideoName ?? "Upload .mp4 Video"),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _youtubeLinkController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "YouTube Video Link (optional)",
                  hintText: "https://youtube.com/watch?v=...",
                ),
              ),
              const Divider(color: Colors.white30, height: 40),

              const Text("📦 Platform Binaries",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              for (final p in _platforms)
                ListTile(
                  title: Text(p.toUpperCase(),
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                      _platformBinaries[p]?.name ?? "No file selected",
                      style: const TextStyle(color: Colors.white70)),
                  trailing: ElevatedButton(
                    onPressed: () => _pickBinary(p),
                    child: Text(_platformBinaries[p] != null
                        ? "Replace"
                        : "Upload"),
                  ),
                ),
              const Divider(color: Colors.white30, height: 40),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _screenshotNames.isNotEmpty
                          ? "${_screenshotNames.length} screenshots selected"
                          : "No screenshots selected",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton(
                      onPressed: _pickScreenshots,
                      child: const Text("Pick Screenshots")),
                ],
              ),
              const SizedBox(height: 30),
              if (_errorMessage != null)
                Text(_errorMessage!,
                    style:
                    const TextStyle(color: Colors.redAccent)),
              ElevatedButton(
                onPressed: _submitApp,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green),
                child: const Text("Submit App"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
}
