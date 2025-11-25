import 'dart:typed_data';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateAppPage extends StatefulWidget {
  final String appId;

  const UpdateAppPage({super.key, required this.appId});

  @override
  State<UpdateAppPage> createState() => _UpdateAppPageState();
}

class _UpdateAppPageState extends State<UpdateAppPage> {
  final _formKey = GlobalKey<FormState>();
  final _versionController = TextEditingController();
  String? _selectedPlatform;

  final List<String> _platforms = ["android", "ios", "windows", "macos", "linux", "web"];
  File? _binaryFile;
  Uint8List? _binaryBytes;
  String? _binaryName;
  bool _loading = false;
  String? _errorMessage;

  Future<void> _pickBinary() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        if (kIsWeb) {
          _binaryBytes = result.files.first.bytes;
        } else {
          _binaryFile = File(result.files.single.path!);
        }
        _binaryName = result.files.first.name;
      });
    }
  }

  Future<void> _submitUpdate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_binaryName == null) return setState(() => _errorMessage = "⚠️ Please select a binary file");
    if (_selectedPlatform == null) return setState(() => _errorMessage = "⚠️ Please select a platform");

    setState(() => _loading = true);
    final supabase = Supabase.instance.client;

    try {
      final path = "binaries/${_selectedPlatform}_${DateTime.now().millisecondsSinceEpoch}_$_binaryName";

      if (kIsWeb) {
        await supabase.storage.from('app-media').uploadBinary(
          path,
          _binaryBytes!,
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );
      } else {
        await supabase.storage.from('app-media').upload(
          path,
          _binaryFile!,
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );
      }

      await supabase.from('app_versions').insert({
        'app_id': widget.appId,
        'version': _versionController.text.trim(),
        'platform': _selectedPlatform,
        'storage_key': path,
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Version added successfully")));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Update App")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _versionController,
                decoration: const InputDecoration(labelText: "Version"),
                validator: (v) => v == null || v.isEmpty ? "Enter version" : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedPlatform,
                decoration: const InputDecoration(labelText: "Platform"),
                items: _platforms.map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase()))).toList(),
                onChanged: (val) => setState(() => _selectedPlatform = val),
                validator: (v) => v == null ? "Select platform" : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(_binaryName ?? "No binary selected", overflow: TextOverflow.ellipsis),
                  ),
                  ElevatedButton(onPressed: _pickBinary, child: const Text("Pick Binary")),
                ],
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(onPressed: _submitUpdate, child: const Text("Upload New Version")),
            ],
          ),
        ),
      ),
    );
  }
}
