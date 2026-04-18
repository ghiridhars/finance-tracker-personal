/// Unified Import Screen — combines single-file upload and batch directory import.
///
/// Uses a SegmentedButton to toggle between:
///   1. Upload File — single PDF/CSV with bank/type selection
///   2. Directory Import — scan a local folder and batch-import statements
///
/// Each mode delegates to its own existing provider
/// (statementsProvider / localSyncProvider).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/statements_provider.dart';
import '../providers/local_sync_provider.dart';
import '../services/api_service.dart';

enum _ImportMode { upload, directory }

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _ImportMode _mode = _ImportMode.upload;

  // ── Upload mode state ──
  PlatformFile? _selectedFile;
  String _bank = 'HDFC';
  String _statementType = 'SAVINGS';
  bool _saveAfterParse = true;
  bool _isDragHovering = false;

  // ── Directory mode state ──
  final _pathController = TextEditingController();
  final _fileListScrollController = ScrollController();

  /// Shared bank options.
  static const _bankOptions = [
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

  static const _typeOptions = [
    {'value': 'SAVINGS', 'label': 'Savings Account'},
    {'value': 'CREDIT_CARD', 'label': 'Credit Card'},
  ];

  /// Short labels for the per-file dropdowns in directory mode.
  static const _bankOptionsShort = [
    {'value': 'HDFC', 'label': 'HDFC'},
    {'value': 'ICICI', 'label': 'ICICI'},
    {'value': 'SBI', 'label': 'SBI'},
    {'value': 'AXIS', 'label': 'AXIS'},
    {'value': 'KOTAK', 'label': 'KOTAK'},
    {'value': 'YES_BANK', 'label': 'Yes Bank'},
    {'value': 'BOB', 'label': 'BOB'},
    {'value': 'FEDERAL_BANK', 'label': 'Federal Bank'},
    {'value': 'OTHER', 'label': 'Other'},
  ];

  static const _typeOptionsShort = [
    {'value': 'SAVINGS', 'label': 'Savings'},
    {'value': 'CREDIT_CARD', 'label': 'Credit Card'},
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(statementsProvider.notifier).checkBackend();
      ref.read(localSyncProvider.notifier).loadStatus();
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    _fileListScrollController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                'Import Data',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Upload a statement file or batch-import from a local directory.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),

              // Mode toggle
              Center(
                child: SegmentedButton<_ImportMode>(
                  segments: const [
                    ButtonSegment(
                      value: _ImportMode.upload,
                      label: Text('Upload File'),
                      icon: Icon(Icons.upload_file),
                    ),
                    ButtonSegment(
                      value: _ImportMode.directory,
                      label: Text('Directory Import'),
                      icon: Icon(Icons.folder_open),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (sel) =>
                      setState(() => _mode = sel.first),
                ),
              ),
              const SizedBox(height: 24),

              // Conditional content
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _mode == _ImportMode.upload
                    ? _buildUploadMode(colorScheme)
                    : _buildDirectoryMode(colorScheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MODE 1: UPLOAD FILE
  // ══════════════════════════════════════════════════════════════

  Widget _buildUploadMode(ColorScheme colorScheme) {
    final uploadState = ref.watch(statementsProvider);

    return Card(
      key: const ValueKey('upload'),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend status
            if (!uploadState.backendReachable) ...[
              _buildBackendBanner(colorScheme),
              const SizedBox(height: 16),
            ],

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
              items: _typeOptions
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
              subtitle:
                  const Text('When off, statement is parsed but not stored'),
              value: _saveAfterParse,
              onChanged: (val) => setState(() => _saveAfterParse = val),
            ),
            const SizedBox(height: 16),

            // Drop zone
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
              label: Text(
                  uploadState.isUploading ? 'Processing...' : 'Upload & Parse'),
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
    );
  }

  Widget _buildBackendBanner(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
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
                  color: colorScheme.onErrorContainer, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(statementsProvider.notifier).checkBackend(),
            child: const Text('Retry'),
          ),
        ],
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
                key: ValueKey(
                    _isDragHovering ? 'hover' : _selectedFile?.name ?? 'empty'),
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
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(_formatFileSize(_selectedFile!.size),
                  style: Theme.of(context).textTheme.bodySmall),
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'csv', 'txt'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
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
    if (_selectedFile!.size > 10 * 1024 * 1024) {
      _showSnackBar('File exceeds 10 MB limit', isError: true);
      return;
    }

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

  // ══════════════════════════════════════════════════════════════
  // MODE 2: DIRECTORY IMPORT
  // ══════════════════════════════════════════════════════════════

  Widget _buildDirectoryMode(ColorScheme colorScheme) {
    final syncState = ref.watch(localSyncProvider);

    // Sync path controller when status loads
    if (syncState.configuredPath != null && _pathController.text.isEmpty) {
      _pathController.text = syncState.configuredPath!;
    }

    return Column(
      key: const ValueKey('directory'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Path configuration card
        _buildPathSection(syncState, colorScheme),
        const SizedBox(height: 16),

        // Error display
        if (syncState.error != null)
          _buildErrorBanner(syncState.error!, colorScheme),

        // File review table
        if (syncState.files.isNotEmpty || syncState.isFetchingFiles)
          _buildFileSection(syncState, colorScheme),

        // Import progress
        if (syncState.scanStatus != null)
          _buildProgressSection(syncState, colorScheme),
      ],
    );
  }

  // ── Path Configuration ────────────────────────────────────

  Widget _buildPathSection(LocalSyncState syncState, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Directory Path',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: kIsWeb
                          ? 'Server-side directory path'
                          : 'Folder path',
                      hintText: kIsWeb
                          ? '/home/user/statements'
                          : 'Click Browse to select a folder',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.folder),
                    ),
                    onSubmitted: (_) => _configurePath(),
                  ),
                ),
                const SizedBox(width: 12),
                if (!kIsWeb)
                  FilledButton.tonalIcon(
                    onPressed: _pickDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse'),
                  ),
                if (kIsWeb)
                  FilledButton.tonalIcon(
                    onPressed: _configurePath,
                    icon: const Icon(Icons.check),
                    label: const Text('Set Path'),
                  ),
              ],
            ),
            if (syncState.configuredPath != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _infoChip(
                    Icons.check_circle_outline,
                    'Path configured',
                    syncState.pathExists ? Colors.green : Colors.red,
                  ),
                  if (syncState.lastScan != null)
                    _infoChip(
                      Icons.schedule,
                      'Last scan: ${_formatDate(syncState.lastScan!)}',
                      colorScheme.primary,
                    ),
                  if (syncState.processedFileCount > 0)
                    _infoChip(
                      Icons.done_all,
                      '${syncState.processedFileCount} files processed',
                      colorScheme.tertiary,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: syncState.isFetchingFiles || syncState.isScanning
                    ? null
                    : () => ref.read(localSyncProvider.notifier).fetchFiles(),
                icon: syncState.isFetchingFiles
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(syncState.isFetchingFiles
                    ? 'Scanning...'
                    : 'Scan for Files'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Statements Folder',
    );
    if (result != null) {
      _pathController.text = result;
      await ref.read(localSyncProvider.notifier).configurePath(result);
    }
  }

  Future<void> _configurePath() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    await ref.read(localSyncProvider.notifier).configurePath(path);
  }

  // ── File Review Table ─────────────────────────────────────

  Widget _buildFileSection(LocalSyncState syncState, ColorScheme colorScheme) {
    if (syncState.isFetchingFiles) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final files = syncState.files;
    if (files.isEmpty) return const SizedBox.shrink();

    final newCount = syncState.newFileCount;
    final processedCount = files.length - newCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('${files.length} files found',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (newCount > 0)
                  Text('$newCount new',
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                if (processedCount > 0) ...[
                  const SizedBox(width: 12),
                  Text('$processedCount already processed',
                      style:
                          TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Select all / deselect controls
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      ref.read(localSyncProvider.notifier).selectAll(),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('Select All'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(localSyncProvider.notifier).deselectAll(),
                  icon: const Icon(Icons.deselect, size: 18),
                  label: const Text('Deselect All'),
                ),
                const Spacer(),
                if (syncState.processedFileCount > 0)
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(localSyncProvider.notifier).resetFiles(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset All'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // File list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500),
              child: Scrollbar(
                controller: _fileListScrollController,
                child: ListView.separated(
                  controller: _fileListScrollController,
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _buildFileRow(files[index], index, syncState, colorScheme),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Import button
            FilledButton.icon(
              onPressed: syncState.isScanning || syncState.selectedCount == 0
                  ? null
                  : () => ref.read(localSyncProvider.notifier).startScan(),
              icon: syncState.isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(syncState.isScanning
                  ? 'Importing...'
                  : 'Import Selected (${syncState.selectedCount})'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(
    LocalSyncFile file,
    int index,
    LocalSyncState syncState,
    ColorScheme colorScheme,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 100,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: file.selected,
              onChanged: syncState.isScanning
                  ? null
                  : (_) =>
                      ref.read(localSyncProvider.notifier).toggleFile(index),
            ),
            _statusIcon(file, colorScheme),
            const SizedBox(width: 8),
            SizedBox(
              width: 350,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.filename,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                  if (file.relativePath != file.filename)
                    Text(file.relativePath,
                        style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Text(_formatFileSize(file.size),
                          style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant)),
                      if (file.errorMessage != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(file.errorMessage!,
                              style: TextStyle(
                                  fontSize: 11, color: colorScheme.error),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Bank dropdown
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                value: file.selectedBank,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: _bankOptionsShort
                    .map((opt) => DropdownMenuItem(
                          value: opt['value'],
                          child: Text(opt['label']!,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: syncState.isScanning
                    ? null
                    : (val) {
                        if (val != null) {
                          ref
                              .read(localSyncProvider.notifier)
                              .updateFileBank(index, val);
                        }
                      },
              ),
            ),
            const SizedBox(width: 8),
            // Type dropdown
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                value: file.selectedType,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: _typeOptionsShort
                    .map((opt) => DropdownMenuItem(
                          value: opt['value'],
                          child: Text(opt['label']!,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: syncState.isScanning
                    ? null
                    : (val) {
                        if (val != null) {
                          ref
                              .read(localSyncProvider.notifier)
                              .updateFileType(index, val);
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(LocalSyncFile file, ColorScheme colorScheme) {
    switch (file.status) {
      case 'success':
        return Icon(Icons.check_circle, color: Colors.green.shade600, size: 20);
      case 'failed':
        return Icon(Icons.error, color: colorScheme.error, size: 20);
      case 'skipped':
        return Icon(Icons.skip_next,
            color: colorScheme.onSurfaceVariant, size: 20);
      case 'processing':
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        if (file.alreadyProcessed) {
          return Icon(Icons.done,
              color: colorScheme.onSurfaceVariant, size: 20);
        }
        return Icon(Icons.insert_drive_file_outlined,
            color: colorScheme.primary, size: 20);
    }
  }

  // ── Import Progress ───────────────────────────────────────

  Widget _buildProgressSection(
      LocalSyncState syncState, ColorScheme colorScheme) {
    final isRunning = syncState.scanStatus == 'running' ||
        syncState.scanStatus == 'started';
    final isDone = syncState.scanStatus == 'completed';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isDone ? Icons.check_circle : Icons.sync,
                      color:
                          isDone ? Colors.green.shade600 : colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(isDone ? 'Import Complete' : 'Importing...',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              if (isRunning && syncState.scanTotal > 0)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: syncState.currentIndex / syncState.scanTotal,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Processing ${syncState.currentIndex} of ${syncState.scanTotal}'
                      '${syncState.currentFile != null ? ': ${syncState.currentFile}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (syncState.scanProcessed > 0)
                    Chip(
                      avatar: Icon(Icons.check_circle,
                          size: 16, color: Colors.green.shade600),
                      label: Text('${syncState.scanProcessed} processed'),
                      backgroundColor: Colors.green.shade50,
                    ),
                  if (syncState.scanFailed > 0)
                    Chip(
                      avatar: Icon(Icons.error,
                          size: 16, color: colorScheme.error),
                      label: Text('${syncState.scanFailed} failed'),
                      backgroundColor: colorScheme.errorContainer,
                    ),
                  if (syncState.scanSkipped > 0)
                    Chip(
                      avatar: Icon(Icons.skip_next,
                          size: 16, color: colorScheme.onSurfaceVariant),
                      label: Text('${syncState.scanSkipped} skipped'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────

  Widget _buildErrorBanner(String error, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber,
                color: colorScheme.onErrorContainer, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(error,
                  style: TextStyle(
                      color: colorScheme.onErrorContainer, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
