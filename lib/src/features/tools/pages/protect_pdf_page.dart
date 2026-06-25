import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../tools_service.dart';
import '../utils/tools_directory_util.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../../../shared/widgets/glass_app_bar.dart';

class ProtectPdfPage extends ConsumerStatefulWidget {
  final List<String>? initialFiles;

  const ProtectPdfPage({super.key, this.initialFiles});

  @override
  ConsumerState<ProtectPdfPage> createState() => _ProtectPdfPageState();
}

class _ProtectPdfPageState extends ConsumerState<ProtectPdfPage> {
  final List<String> _selectedFiles = [];
  final _passwordController = TextEditingController();
  bool _isObscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _selectedFiles.addAll(widget.initialFiles!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickFiles();
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: true);
    if (paths != null && paths.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(paths.where((p) => !_selectedFiles.contains(p)));
      });
    } else if (_selectedFiles.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _processFiles() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a password')),
      );
      return;
    }

    if (_selectedFiles.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ToolActionDialog(
        title: _selectedFiles.length == 1 ? 'Protecting PDF' : 'Batch Protecting PDFs',
        message: 'Encrypting with AES-256...',
        isLoading: true,
      ),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    int successCount = 0;
    String? lastSuccessPath;

    for (final path in _selectedFiles) {
      final originalName = p.basenameWithoutExtension(path);
      final outputPath = p.join(dir, '${originalName}_protected.pdf');

      final result = await ToolsService.protectPdf(path, outputPath, password);
      if (result != null) {
        successCount++;
        lastSuccessPath = result;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successCount == _selectedFiles.length && _selectedFiles.length == 1) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(
          title: 'Success',
          message: 'PDF protected successfully!',
          isLoading: false,
          outputPath: lastSuccessPath,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(
          title: 'Batch Complete',
          message: 'Successfully protected $successCount out of ${_selectedFiles.length} files.\nSaved to: $dir',
          isLoading: false,
          outputPath: dir,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: _selectedFiles.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _processFiles,
              icon: const Icon(HugeIcons.strokeRoundedLockPassword),
              label: const Text('Protect'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          const GlassSliverAppBar(
            title: Text('Protect PDF'),
          ),
          if (_selectedFiles.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: FilledButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Select PDFs'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'Set Password',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: _isObscure,
                    decoration: InputDecoration(
                      hintText: 'Enter password',
                      prefixIcon: const Icon(HugeIcons.strokeRoundedKey01),
                      suffixIcon: IconButton(
                        icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _isObscure = !_isObscure;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHigh,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Selected Files (${_selectedFiles.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._selectedFiles.map((path) {
                    final filename = p.basename(path);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        leading: const Icon(HugeIcons.strokeRoundedFile01),
                        title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _selectedFiles.remove(path);
                            });
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 80),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
