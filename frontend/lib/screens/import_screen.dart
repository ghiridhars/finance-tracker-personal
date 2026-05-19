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
import '../providers/gdrive_import_provider.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ImportMode { upload, directory, gdrive }

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

  /// Per-bank password cache for the session (not persisted).
  final Map<String, String> _bankPasswords = {};
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

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
      ref.read(gdriveImportProvider.notifier).loadStatus();
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    _passwordController.dispose();
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
                    ButtonSegment(
                      value: _ImportMode.gdrive,
                      label: Text('Google Drive'),
                      icon: Icon(Icons.cloud_queue),
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
                    : (_mode == _ImportMode.directory
                        ? _buildDirectoryMode(colorScheme)
                        : _buildGDriveMode(colorScheme)),
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
                if (val != null) {
                  setState(() {
                    _bank = val;
                    // Pre-fill cached password for this bank
                    _passwordController.text = _bankPasswords[val] ?? '';
                  });
                }
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

            // Password field — only shown for PDF files
            if (_selectedFile != null &&
                _selectedFile!.name.toLowerCase().endsWith('.pdf')) ...[
              TextField(
                controller: _passwordController,
                obscureText: !_passwordVisible,
                onChanged: (val) => _bankPasswords[_bank] = val,
                decoration: InputDecoration(
                  labelText: 'PDF Password (optional)',
                  hintText: 'Leave blank if not password-protected',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                    tooltip:
                        _passwordVisible ? 'Hide password' : 'Show password',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

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
      final picked = result.files.first;
      final isPdf = picked.name.toLowerCase().endsWith('.pdf');
      setState(() {
        _selectedFile = picked;
        // Pre-fill cached password for this bank when switching to a PDF
        if (isPdf) {
          _passwordController.text = _bankPasswords[_bank] ?? '';
        } else {
          _passwordController.clear();
        }
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
    if (_selectedFile!.size > 10 * 1024 * 1024) {
      _showSnackBar('File exceeds 10 MB limit', isError: true);
      return;
    }

    final fileName = _selectedFile!.name.toLowerCase();
    final isCsv = fileName.endsWith('.csv') || fileName.endsWith('.txt');
    final password = _passwordController.text.trim();

    await ref.read(statementsProvider.notifier).uploadV2(
          fileBytes: _selectedFile!.bytes!,
          fileName: _selectedFile!.name,
          bank: _bank,
          statementType: _statementType,
          save: _saveAfterParse,
          isCsv: isCsv,
          password: password.isNotEmpty ? password : null,
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

            // Bank Passwords — shown when any selected PDF needs a password
            _buildBankPasswordsSection(syncState, colorScheme),

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

  /// Shows one password field per unique bank that has ≥1 selected PDF file.
  /// Shares the session-level [_bankPasswords] cache with the upload mode.
  Widget _buildBankPasswordsSection(
      LocalSyncState syncState, ColorScheme colorScheme) {
    // Collect banks that have at least one selected PDF file
    final banksWithPdf = syncState.files
        .where((f) =>
            f.selected && f.filename.toLowerCase().endsWith('.pdf'))
        .map((f) => f.selectedBank)
        .toSet()
        .toList()
      ..sort();

    if (banksWithPdf.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Bank Passwords (optional)',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Enter passwords for any password-protected PDF statements.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            ...banksWithPdf.map((bank) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BankPasswordField(
                    bank: bank,
                    initialValue: _bankPasswords[bank] ?? '',
                    enabled: !syncState.isScanning,
                    onChanged: (val) {
                      // Keep both caches in sync
                      _bankPasswords[bank] = val;
                      ref
                          .read(localSyncProvider.notifier)
                          .updateBankPassword(bank, val);
                    },
                  ),
                )),
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

  // ══════════════════════════════════════════════════════════════
  // MODE 3: GOOGLE DRIVE IMPORT
  // ══════════════════════════════════════════════════════════════

  Widget _buildGDriveMode(ColorScheme colorScheme) {
    final gdriveState = ref.watch(gdriveImportProvider);

    return Column(
      key: const ValueKey('gdrive'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Connection section
        _buildGDriveConnectionSection(gdriveState, colorScheme),
        const SizedBox(height: 16),

        if (gdriveState.isConnected) ...[
          // Folder Explorer section
          _buildGDriveExplorerSection(gdriveState, colorScheme),
          const SizedBox(height: 16),

          // File Discovery & Selection list
          if (gdriveState.files.isNotEmpty || gdriveState.isLoadingFiles) ...[
            _buildGDriveFileSection(gdriveState, colorScheme),
            const SizedBox(height: 16),
          ],

          // Import job progress polling card
          if (gdriveState.importStatus != null)
            _buildGDriveProgressSection(gdriveState, colorScheme),
        ],

        // Error display
        if (gdriveState.error != null) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(gdriveState.error!, colorScheme),
          Center(
            child: TextButton(
              onPressed: () => ref.read(gdriveImportProvider.notifier).clearError(),
              child: const Text('Dismiss Error'),
            ),
          ),
        ],
      ],
    );
  }

  // ── Connection Card ───────────────────────────────────────

  Widget _buildGDriveConnectionSection(GDriveImportState gdriveState, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  gdriveState.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: gdriveState.isConnected ? Colors.blue.shade600 : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Google Drive Connection',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (gdriveState.isConnected) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Connected to account: ${gdriveState.email ?? "Authorized User"}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                    ),
                    onPressed: () => ref.read(gdriveImportProvider.notifier).disconnect(),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Disconnect'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Connect your personal Google account to browse, select, and import statement PDFs or CSVs directly from your Google Drive.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final url = await ref.read(gdriveImportProvider.notifier).getAuthUrl();
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        _showSnackBar('Could not launch authorization page', isError: true);
                      }
                    } catch (e) {
                      _showSnackBar('Authorization error: $e', isError: true);
                    }
                  },
                  icon: Image.network(
                    'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                    height: 18,
                    width: 18,
                    errorBuilder: (_, __, ___) => const Icon(Icons.login, color: Colors.blue, size: 18),
                  ),
                  label: const Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Subfolder Explorer Card ──────────────────────────────

  Widget _buildGDriveExplorerSection(GDriveImportState gdriveState, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_shared_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Folder Navigator', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),

            // Breadcrumbs Navigation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => ref.read(gdriveImportProvider.notifier).navigateBack(-1),
                      child: Text(
                        'My Drive',
                        style: TextStyle(
                          color: gdriveState.currentPath.isEmpty ? colorScheme.onSurface : colorScheme.primary,
                          fontWeight: gdriveState.currentPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    for (int i = 0; i < gdriveState.currentPath.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant),
                      ),
                      InkWell(
                        onTap: () => ref.read(gdriveImportProvider.notifier).navigateBack(i),
                        child: Text(
                          gdriveState.currentPath[i].name,
                          style: TextStyle(
                            color: i == gdriveState.currentPath.length - 1 ? colorScheme.onSurface : colorScheme.primary,
                            fontWeight: i == gdriveState.currentPath.length - 1 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Folder grid list
            if (gdriveState.isLoadingFolders) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (gdriveState.folders.isEmpty) ...[
              Text(
                'No subfolders found in this directory.',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ] else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: Scrollbar(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.8,
                    ),
                    itemCount: gdriveState.folders.length,
                    itemBuilder: (context, index) {
                      final folder = gdriveState.folders[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        color: colorScheme.surfaceContainerLow,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          onTap: () => ref.read(gdriveImportProvider.notifier).navigateInto(folder),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.folder, color: Colors.amber, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    folder.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Folder scan button
            Row(
              children: [
                FilledButton.icon(
                  onPressed: gdriveState.isLoadingFiles || gdriveState.isImporting
                      ? null
                      : () => ref.read(gdriveImportProvider.notifier).scanCurrentFolder(),
                  icon: gdriveState.isLoadingFiles
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.find_in_page_outlined),
                  label: Text(gdriveState.isLoadingFiles
                      ? 'Scanning Folder...'
                      : 'Scan ${gdriveState.currentFolderName} for Statements'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Scanned Statement Review Section ──────────────────────

  Widget _buildGDriveFileSection(GDriveImportState gdriveState, ColorScheme colorScheme) {
    if (gdriveState.isLoadingFiles) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final files = gdriveState.files;
    if (files.isEmpty) return const SizedBox.shrink();

    final newCount = gdriveState.newFileCount;
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
                Text('${files.length} statement files discovered',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (newCount > 0)
                  Text('$newCount new',
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                if (processedCount > 0) ...[
                  const SizedBox(width: 12),
                  Text('$processedCount already imported',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                TextButton.icon(
                  onPressed: () => ref.read(gdriveImportProvider.notifier).selectAll(),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('Select All'),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(gdriveImportProvider.notifier).deselectAll(),
                  icon: const Icon(Icons.deselect, size: 18),
                  label: const Text('Deselect All'),
                ),
                const Spacer(),
                if (processedCount > 0)
                  TextButton.icon(
                    onPressed: () => ref.read(gdriveImportProvider.notifier).resetFiles(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset Sync Cache'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Files view
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
                      _buildGDriveFileRow(files[index], index, gdriveState, colorScheme),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Passwords section
            _buildGDriveBankPasswordsSection(gdriveState, colorScheme),

            // Import Trigger Button
            FilledButton.icon(
              onPressed: gdriveState.isImporting || gdriveState.selectedCount == 0
                  ? null
                  : () => ref.read(gdriveImportProvider.notifier).startImport(),
              icon: gdriveState.isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download),
              label: Text(gdriveState.isImporting
                  ? 'Importing from Google Drive...'
                  : 'Import Selected (${gdriveState.selectedCount})'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGDriveFileRow(
    LocalSyncFile file,
    int index,
    GDriveImportState gdriveState,
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
              onChanged: gdriveState.isImporting
                  ? null
                  : (_) => ref.read(gdriveImportProvider.notifier).toggleFile(index),
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
            // Bank selector
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
                onChanged: gdriveState.isImporting
                    ? null
                    : (val) {
                        if (val != null) {
                          ref
                              .read(gdriveImportProvider.notifier)
                              .updateFileBank(index, val);
                        }
                      },
              ),
            ),
            const SizedBox(width: 8),
            // Statement type selector
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
                onChanged: gdriveState.isImporting
                    ? null
                    : (val) {
                        if (val != null) {
                          ref
                              .read(gdriveImportProvider.notifier)
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

  // ── Passwords Grid ────────────────────────────────────────

  Widget _buildGDriveBankPasswordsSection(
      GDriveImportState gdriveState, ColorScheme colorScheme) {
    final banksWithPdf = gdriveState.files
        .where((f) =>
            f.selected && f.filename.toLowerCase().endsWith('.pdf'))
        .map((f) => f.selectedBank)
        .toSet()
        .toList()
      ..sort();

    if (banksWithPdf.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Bank Passwords (optional)',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Enter passwords for any password-protected PDF statements.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            ...banksWithPdf.map((bank) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BankPasswordField(
                    bank: bank,
                    initialValue: _bankPasswords[bank] ?? '',
                    enabled: !gdriveState.isImporting,
                    onChanged: (val) {
                      _bankPasswords[bank] = val;
                      ref
                          .read(gdriveImportProvider.notifier)
                          .updateBankPassword(bank, val);
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── Import Progress card ──────────────────────────────────

  Widget _buildGDriveProgressSection(
      GDriveImportState gdriveState, ColorScheme colorScheme) {
    final isRunning = gdriveState.importStatus == 'running' ||
        gdriveState.importStatus == 'started';
    final isDone = gdriveState.importStatus == 'completed';

    return Card(
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
                Text(isDone ? 'Google Drive Import Complete' : 'Downloading & Importing...',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            if (isRunning && gdriveState.importTotal > 0)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: gdriveState.currentIndex / gdriveState.importTotal,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Processing ${gdriveState.currentIndex} of ${gdriveState.importTotal}'
                    '${gdriveState.currentFile != null ? ': ${gdriveState.currentFile}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (gdriveState.importProcessed > 0)
                  Chip(
                    avatar: Icon(Icons.check_circle,
                        size: 16, color: Colors.green.shade600),
                    label: Text('${gdriveState.importProcessed} imported'),
                    backgroundColor: Colors.green.shade50,
                  ),
                if (gdriveState.importFailed > 0)
                  Chip(
                    avatar: Icon(Icons.error,
                        size: 16, color: colorScheme.error),
                    label: Text('${gdriveState.importFailed} failed'),
                    backgroundColor: colorScheme.errorContainer,
                  ),
                if (gdriveState.importSkipped > 0)
                  Chip(
                    avatar: Icon(Icons.skip_next,
                        size: 16, color: colorScheme.onSurfaceVariant),
                    label: Text('${gdriveState.importSkipped} skipped'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

/// A stateful password field for a single bank, with visibility toggle.
class _BankPasswordField extends StatefulWidget {
  final String bank;
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _BankPasswordField({
    required this.bank,
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_BankPasswordField> createState() => _BankPasswordFieldState();
}

class _BankPasswordFieldState extends State<_BankPasswordField> {
  late final TextEditingController _ctrl;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      obscureText: !_visible,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: '${widget.bank} — Password',
        hintText: 'Leave blank if not password-protected',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
          tooltip: _visible ? 'Hide password' : 'Show password',
        ),
      ),
    );
  }
}
