/// Local Sync Screen — scan a local directory for bank statements.
///
/// Three-section UI:
///   1. Path configuration (folder picker or text input)
///   2. File review table with editable bank/type dropdowns
///   3. Import progress with per-file status
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/local_sync_provider.dart';

class LocalSyncScreen extends ConsumerStatefulWidget {
  const LocalSyncScreen({super.key});

  @override
  ConsumerState<LocalSyncScreen> createState() => _LocalSyncScreenState();
}

class _LocalSyncScreenState extends ConsumerState<LocalSyncScreen> {
  final _pathController = TextEditingController();

  /// Banks available in dropdowns.
  static const _bankOptions = [
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

  static const _typeOptions = [
    {'value': 'SAVINGS', 'label': 'Savings'},
    {'value': 'CREDIT_CARD', 'label': 'Credit Card'},
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(localSyncProvider.notifier).loadStatus();
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(localSyncProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Sync path controller when status loads
    if (syncState.configuredPath != null && _pathController.text.isEmpty) {
      _pathController.text = syncState.configuredPath!;
    }

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
                'Local Directory Import',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Scan a local folder for bank statements and import them in batch.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),

              // Section 1: Path Configuration
              _buildPathSection(syncState, colorScheme),
              const SizedBox(height: 24),

              // Error display
              if (syncState.error != null)
                _buildErrorBanner(syncState.error!, colorScheme),

              // Section 2: File review table
              if (syncState.files.isNotEmpty || syncState.isFetchingFiles)
                _buildFileSection(syncState, colorScheme),

              // Section 3: Import progress
              if (syncState.scanStatus != null)
                _buildProgressSection(syncState, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section 1: Path Configuration ─────────────────────────

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
                Text(
                  'Directory Path',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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

  Widget _infoChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  // ── Section 2: File Review Table ──────────────────────────

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
            // Header with summary
            Row(
              children: [
                Icon(Icons.list_alt, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${files.length} files found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (newCount > 0)
                  Text(
                    '$newCount new',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (processedCount > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    '$processedCount already processed',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
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
                child: ListView.separated(
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
            // Checkbox
            Checkbox(
              value: file.selected,
              onChanged: syncState.isScanning
                  ? null
                  : (_) => ref.read(localSyncProvider.notifier).toggleFile(index),
            ),

            // Status icon
            _statusIcon(file, colorScheme),
            const SizedBox(width: 8),

            // File info
            SizedBox(
              width: 350,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.filename,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (file.relativePath != file.filename)
                    Text(
                      file.relativePath,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  Row(
                    children: [
                      Text(
                        _formatFileSize(file.size),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (file.errorMessage != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            file.errorMessage!,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.error,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                items: _bankOptions
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
                items: _typeOptions
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
        return Icon(Icons.skip_next, color: colorScheme.onSurfaceVariant, size: 20);
      case 'processing':
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        if (file.alreadyProcessed) {
          return Icon(Icons.done, color: colorScheme.onSurfaceVariant, size: 20);
        }
        return Icon(Icons.insert_drive_file_outlined,
            color: colorScheme.primary, size: 20);
    }
  }

  // ── Section 3: Import Progress ────────────────────────────

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
                  Icon(
                    isDone ? Icons.check_circle : Icons.sync,
                    color: isDone ? Colors.green.shade600 : colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isDone ? 'Import Complete' : 'Importing...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Progress bar
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

              // Summary chips
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
                      avatar:
                          Icon(Icons.error, size: 16, color: colorScheme.error),
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

  // ── Error Banner ──────────────────────────────────────────

  Widget _buildErrorBanner(String error, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber,
                color: colorScheme.onErrorContainer, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: TextStyle(
                    color: colorScheme.onErrorContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────

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
