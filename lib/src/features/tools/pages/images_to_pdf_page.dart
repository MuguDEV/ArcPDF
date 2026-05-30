import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../utils/tools_directory_util.dart';

class ImagesToPdfPage extends StatefulWidget {
  const ImagesToPdfPage({super.key});

  @override
  State<ImagesToPdfPage> createState() => _ImagesToPdfPageState();
}

class _ImagesToPdfPageState extends State<ImagesToPdfPage> {
  List<String> _selectedFiles = [];

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.paths.whereType<String>());
      });
    }
  }

  Future<void> _convert() async {
    if (_selectedFiles.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Converting', message: 'Please wait...', isLoading: true),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final outputPath = p.join(dir, 'ImagesToPDF_${DateTime.now().millisecondsSinceEpoch}.pdf');

    final successPath = await ToolsService.imagesToPdf(_selectedFiles, outputPath);

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successPath != null) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n$successPath', isLoading: false, outputPath: successPath),
      ).then((_) => Navigator.of(context).pop());
    } else {
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to convert.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Images to PDF')),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _selectedFiles.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _selectedFiles.removeAt(oldIndex);
                  _selectedFiles.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final path = _selectedFiles[index];
                return ListTile(
                  key: ValueKey(path),
                  leading: Image.file(File(path), width: 40, height: 40, fit: BoxFit.cover),
                  title: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickFiles,
                    child: const Text('Add Images'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedFiles.isNotEmpty ? _convert : null,
                    child: const Text('Convert to PDF'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
