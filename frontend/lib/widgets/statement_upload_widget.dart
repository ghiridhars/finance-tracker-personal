/// StatementUploadWidget — PDF upload form with drag-and-drop support.
/// Uses Riverpod state management. Supports both file picker and drag-and-drop.
///
/// Upload triggers auto-refresh of transaction lists via StatementsNotifier.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/statements_provider.dart';
import '../services/api_service.dart';

class StatementUploadWidget extends ConsumerStatefulWidget {
  const StatementUploadWidget({super.key});

  @override
  ConsumerState<StatementUploadWidget> createState() =>
      _StatementUploadWidgetState();
}

class _StatementUploadWidgetState extends ConsumerState<StatementUploadWidget> {
  PlatformFile? _selectedFile;
  String _bank = 'HDFC';
  String _statementType = 'SAVINGS';
  bool _saveAfterParse = true;
  bool _isDragHovering = false;

  /// Banks available in the dropdown.
  final List<Map<String, String>> _bankOptions = [
    {'value': 'HDFC', 'label': 'HDFC Bank'},
    {'value': 'ICICI', 'label': 'ICICI Bank'},
    {'value': 'SBI', 'label': 'State Bank of India'},
    {'value': 'AXIS', 'label': 'Axis Bank'},
    {'value': 'KOTAK', 'label': 'Kotak Mahindra Bank'},
    {'value': 'YES_BANK', 'label': 'Yes Bank'},
    {'value': 'BOB', 'label': 'Bank of Baroda'},
    {'value': 'FEDERAL_BANK', 'label': 'Federal Bank'},
    {'value': 'OTHER', 'label': 'Other Bank'},
  ];

  /// Statement types.
  final List<Map<String, String>> _statementTypeOptions = [
    {'value': 'SAVINGS', 'label': 'Savings Account'},
    {'value': 'CREDIT_CARD', 'label': 'Credit Card'},
  ];

  @override
  void initState() {
    super.initState();
    // Check backend connectivity on load
    Future.microtask(
        () => ref.read(statementsProvider.notifier).checkBackend());
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'csv', 'txt'],
      withData: true, // Required for web — reads bytes into memory
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
      });
      ref.read(statementsProvider.notifier).clearResult();
    }
  }

  Future<void> _upload() async {
    if (_selectedFile == null) {
      _showSnackBar('Please select a file first', isError: true);
      return;
    }

    if (_selectedFile!.bytes == null || _selectedFile!.bytes!.isEmpty) {
      _showSnackBar('File data not available — try re-selecting the file',
          isError: true);
      return;
    }

    // Client-side size check (10 MB)
    if (_selectedFile!.size > 10 * 1024 * 1024) {
      _showSnackBar('File exceeds 10 MB limit', isError: true);
      return;
    }

    // Determine if this is a CSV or PDF upload
    final fileName = _selectedFile!.name.toLowerCase();
    final isCsv = fileName.endsWith('.csv') || fileName.endsWith('.txt');

    await ref.read(statementsProvider.notifier).uploadV2(
          fileBytes: _selectedFile!.bytes!,
          fileName: _selectedFile!.name,
          bank: _bank,
          statementType: _statementType,
          save: _saveAfterParse,
          isCsv: isCsv,
        );

    final uploadState = ref.read(statementsProvider);
    if (uploadState.isError) {
      _showSnackBar('Upload failed', isError: true);
    } else {
      _showSnackBar('Statement processed successfully');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? colorScheme.error : colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(statementsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Text(
                    'Upload Bank Statement',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),

                  // Backend status indicator
                  if (!uploadState.backendReachable) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: colorScheme.error.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber,
                              color: colorScheme.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Backend not reachable at ${ApiService.baseUrl}',
                              style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                  fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref
                                .read(statementsProvider.notifier)
                                .checkBackend(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Bank dropdown
                  DropdownButtonFormField<String>(
                    value: _bank,
                    decoration: const InputDecoration(
                      labelText: 'Bank',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                    items: _bankOptions
                        .map((opt) => DropdownMenuItem(
                              value: opt['value'],
                              child: Text(opt['label']!),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _bank = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Statement type dropdown
                  DropdownButtonFormField<String>(
                    value: _statementType,
                    decoration: const InputDecoration(
                      labelText: 'Statement Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    items: _statementTypeOptions
                        .map((opt) => DropdownMenuItem(
                              value: opt['value'],
                              child: Text(opt['label']!),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _statementType = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Save toggle
                  SwitchListTile(
                    title: const Text('Save after parsing'),
                    subtitle: const Text(
                      'When off, statement is parsed but not stored',
                    ),
                    value: _saveAfterParse,
                    onChanged: (val) => setState(() => _saveAfterParse = val),
                  ),
                  const SizedBox(height: 16),

                  // File picker with drag-and-drop zone
                  _buildDropZone(uploadState, colorScheme),
                  const SizedBox(height: 24),

                  // Upload button
                  FilledButton.icon(
                    onPressed: uploadState.isUploading ? null : _upload,
                    icon: uploadState.isUploading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(uploadState.isUploading
                        ? 'Processing...'
                        : 'Upload & Parse'),
                  ),

                  // Result display
                  if (uploadState.resultMessage != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: uploadState.isError
                            ? colorScheme.errorContainer
                            : colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: uploadState.isError
                              ? colorScheme.error.withValues(alpha: 0.3)
                              : colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: SelectableText(
                        uploadState.resultMessage!,
                        style: TextStyle(
                          color: uploadState.isError
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropZone(UploadState uploadState, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: uploadState.isUploading ? null : _pickFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: _isDragHovering
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isDragHovering
                ? colorScheme.primary
                : _selectedFile != null
                    ? colorScheme.outline
                    : colorScheme.outlineVariant,
            width: _isDragHovering ? 2 : 1,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _isDragHovering
                    ? Icons.downloading
                    : _selectedFile != null
                        ? Icons.description
                        : Icons.cloud_upload_outlined,
                key: ValueKey(_isDragHovering ? 'hover' : _selectedFile?.name ?? 'empty'),
                size: 48,
                color: _isDragHovering
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedFile != null) ...[
              Text(
                _selectedFile!.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _formatFileSize(_selectedFile!.size),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: uploadState.isUploading ? null : _pickFile,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Change file'),
              ),
            ] else ...[
              Text(
                _isDragHovering ? 'Drop file here' : 'Click to select a file',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Supports PDF, CSV, and TXT files (max 10 MB)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
