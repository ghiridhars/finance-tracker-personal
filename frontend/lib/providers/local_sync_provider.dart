/// LocalSyncNotifier — manages local directory scan & import state.
///
/// Handles path configuration, file discovery, bank/type overrides,
/// file selection, scan initiation, and progress polling.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api/local_sync_api.dart';

// ── Models ──────────────────────────────────────────────────────

/// Represents a single file discovered during a directory scan.
class LocalSyncFile {
  final String filepath;
  final String relativePath;
  final String filename;
  final int size;
  final String modifiedTime;
  final String inferredBank;
  final String inferredType;
  final bool alreadyProcessed;
  final String fileKey;

  // User-modifiable fields
  final String selectedBank;
  final String selectedType;
  final bool selected;
  final String status; // pending | processing | success | failed | skipped
  final String? errorMessage;

  // Suggestion metadata from backend (immutable, not user-editable)
  final String suggestionSource;   // 'filename' | 'history'
  final bool suggestionConflict;   // true = ambiguous history
  final String suggestedBank;
  final String suggestedType;

  const LocalSyncFile({
    required this.filepath,
    required this.relativePath,
    required this.filename,
    required this.size,
    required this.modifiedTime,
    required this.inferredBank,
    required this.inferredType,
    required this.alreadyProcessed,
    required this.fileKey,
    required this.selectedBank,
    required this.selectedType,
    this.selected = true,
    this.status = 'pending',
    this.errorMessage,
    this.suggestionSource = 'filename',
    this.suggestionConflict = false,
    String? suggestedBank,
    String? suggestedType,
  })  : suggestedBank = suggestedBank ?? selectedBank,
        suggestedType = suggestedType ?? selectedType;

  LocalSyncFile copyWith({
    String? selectedBank,
    String? selectedType,
    bool? selected,
    String? status,
    String? errorMessage,
  }) {
    return LocalSyncFile(
      filepath: filepath,
      relativePath: relativePath,
      filename: filename,
      size: size,
      modifiedTime: modifiedTime,
      inferredBank: inferredBank,
      inferredType: inferredType,
      alreadyProcessed: alreadyProcessed,
      fileKey: fileKey,
      selectedBank: selectedBank ?? this.selectedBank,
      selectedType: selectedType ?? this.selectedType,
      selected: selected ?? this.selected,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      // Preserve immutable suggestion metadata
      suggestionSource: suggestionSource,
      suggestionConflict: suggestionConflict,
      suggestedBank: suggestedBank,
      suggestedType: suggestedType,
    );
  }

  factory LocalSyncFile.fromJson(Map<String, dynamic> json) {
    final bank = json['inferred_bank'] as String? ?? 'OTHER';
    final type = json['inferred_type'] as String? ?? 'SAVINGS';
    final alreadyProcessed = json['already_processed'] as bool? ?? false;
    final suggestionSource = json['suggestion_source'] as String? ?? 'filename';
    final suggestionConflict = json['suggestion_conflict'] as bool? ?? false;
    final suggestedBank = json['suggested_bank'] as String? ?? bank;
    final suggestedType = json['suggested_type'] as String? ?? type;

    return LocalSyncFile(
      filepath: json['filepath'] as String,
      relativePath: json['relative_path'] as String? ?? '',
      filename: json['filename'] as String,
      size: json['size'] as int? ?? 0,
      modifiedTime: json['modified_time'] as String? ?? '',
      inferredBank: bank,
      inferredType: type,
      alreadyProcessed: alreadyProcessed,
      fileKey: json['file_key'] as String? ?? '',
      selectedBank: suggestedBank,
      selectedType: suggestedType,
      // Auto-deselect already processed files
      selected: !alreadyProcessed,
      status: alreadyProcessed ? 'skipped' : 'pending',
      suggestionSource: suggestionSource,
      suggestionConflict: suggestionConflict,
      suggestedBank: suggestedBank,
      suggestedType: suggestedType,
    );
  }
}

/// Overall state for the local sync feature.
class LocalSyncState {
  final String? configuredPath;
  final bool pathExists;
  final String? lastScan;
  final int processedFileCount;

  final List<LocalSyncFile> files;
  final bool isFetchingFiles;
  final bool isScanning;
  final String? currentJobId;

  // Scan results
  final int scanProcessed;
  final int scanFailed;
  final int scanSkipped;
  final int scanTotal;
  final String? scanStatus; // null | started | running | completed
  final String? currentFile;
  final int currentIndex;

  final String? error;
  final Map<String, String> bankPasswords;

  const LocalSyncState({
    this.configuredPath,
    this.pathExists = false,
    this.lastScan,
    this.processedFileCount = 0,
    this.files = const [],
    this.isFetchingFiles = false,
    this.isScanning = false,
    this.currentJobId,
    this.scanProcessed = 0,
    this.scanFailed = 0,
    this.scanSkipped = 0,
    this.scanTotal = 0,
    this.scanStatus,
    this.currentFile,
    this.currentIndex = 0,
    this.error,
    this.bankPasswords = const {},
  });

  int get selectedCount => files.where((f) => f.selected).length;
  int get newFileCount => files.where((f) => !f.alreadyProcessed).length;

  LocalSyncState copyWith({
    String? configuredPath,
    bool? pathExists,
    String? lastScan,
    int? processedFileCount,
    List<LocalSyncFile>? files,
    bool? isFetchingFiles,
    bool? isScanning,
    String? currentJobId,
    int? scanProcessed,
    int? scanFailed,
    int? scanSkipped,
    int? scanTotal,
    String? scanStatus,
    String? currentFile,
    int? currentIndex,
    String? error,
    Map<String, String>? bankPasswords,
    bool clearError = false,
    bool clearJobId = false,
    bool clearScanStatus = false,
  }) {
    return LocalSyncState(
      configuredPath: configuredPath ?? this.configuredPath,
      pathExists: pathExists ?? this.pathExists,
      lastScan: lastScan ?? this.lastScan,
      processedFileCount: processedFileCount ?? this.processedFileCount,
      files: files ?? this.files,
      isFetchingFiles: isFetchingFiles ?? this.isFetchingFiles,
      isScanning: isScanning ?? this.isScanning,
      currentJobId: clearJobId ? null : (currentJobId ?? this.currentJobId),
      scanProcessed: scanProcessed ?? this.scanProcessed,
      scanFailed: scanFailed ?? this.scanFailed,
      scanSkipped: scanSkipped ?? this.scanSkipped,
      scanTotal: scanTotal ?? this.scanTotal,
      scanStatus: clearScanStatus ? null : (scanStatus ?? this.scanStatus),
      currentFile: currentFile ?? this.currentFile,
      currentIndex: currentIndex ?? this.currentIndex,
      error: clearError ? null : (error ?? this.error),
      bankPasswords: bankPasswords ?? this.bankPasswords,
    );
  }
}

// ── Notifier ────────────────────────────────────────────────────

class LocalSyncNotifier extends Notifier<LocalSyncState> {
  Timer? _pollTimer;

  @override
  LocalSyncState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const LocalSyncState();
  }

  /// Load current status from backend.
  Future<void> loadStatus() async {
    try {
      final data = await LocalSyncApi.getStatus();
      state = state.copyWith(
        configuredPath: data['configured_path'] as String?,
        pathExists: data['path_exists'] as bool? ?? false,
        lastScan: data['last_scan'] as String?,
        processedFileCount: data['processed_file_count'] as int? ?? 0,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Configure the local sync path.
  Future<void> configurePath(String path) async {
    try {
      final data = await LocalSyncApi.configurePath(path);
      state = state.copyWith(
        configuredPath: data['path'] as String?,
        pathExists: true,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Fetch files from the configured directory.
  Future<void> fetchFiles() async {
    state = state.copyWith(
      isFetchingFiles: true,
      clearError: true,
      clearScanStatus: true,
    );

    try {
      final data = await LocalSyncApi.listFiles();
      final fileList = (data['files'] as List<dynamic>)
          .map((f) => LocalSyncFile.fromJson(f as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        files: fileList,
        isFetchingFiles: false,
      );
    } catch (e) {
      state = state.copyWith(
        isFetchingFiles: false,
        error: e.toString(),
      );
    }
  }

  /// Update bank selection for a file at the given index.
  void updateFileBank(int index, String bank) {
    if (index < 0 || index >= state.files.length) return;
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selectedBank: bank);
    state = state.copyWith(files: updated);
  }

  /// Update the PDF password for a bank (session-only, not persisted).
  void updateBankPassword(String bank, String password) {
    final updated = Map<String, String>.from(state.bankPasswords);
    if (password.isEmpty) {
      updated.remove(bank);
    } else {
      updated[bank] = password;
    }
    state = state.copyWith(bankPasswords: updated);
  }

  /// Update statement type for a file at the given index.
  void updateFileType(int index, String type) {
    if (index < 0 || index >= state.files.length) return;
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selectedType: type);
    state = state.copyWith(files: updated);
  }

  /// Toggle selection of a file.
  void toggleFile(int index) {
    if (index < 0 || index >= state.files.length) return;
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selected: !updated[index].selected);
    state = state.copyWith(files: updated);
  }

  /// Select all files.
  void selectAll() {
    state = state.copyWith(
      files: state.files.map((f) => f.copyWith(selected: true)).toList(),
    );
  }

  /// Deselect all files.
  void deselectAll() {
    state = state.copyWith(
      files: state.files.map((f) => f.copyWith(selected: false)).toList(),
    );
  }

  /// Start the scan/import for selected files.
  Future<void> startScan({bool force = false}) async {
    final selectedFiles = state.files.where((f) => f.selected).toList();
    if (selectedFiles.isEmpty) {
      state = state.copyWith(error: 'No files selected');
      return;
    }

    state = state.copyWith(
      isScanning: true,
      clearError: true,
      scanProcessed: 0,
      scanFailed: 0,
      scanSkipped: 0,
      scanTotal: selectedFiles.length,
      scanStatus: 'started',
      currentIndex: 0,
    );

    try {
      final filesPayload = selectedFiles
          .map((f) => {
                'filepath': f.filepath,
                'bank': f.selectedBank,
                'type': f.selectedType,
              })
          .toList();

      final data = await LocalSyncApi.startScan(
        files: filesPayload,
        force: force,
        bankPasswords: state.bankPasswords.isNotEmpty
            ? state.bankPasswords
            : null,
      );

      final jobId = data['job_id'] as String;
      state = state.copyWith(
        currentJobId: jobId,
        scanStatus: 'running',
      );

      // Start polling for progress
      _startPolling(jobId);
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        error: e.toString(),
        scanStatus: 'failed',
      );
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollStatus(jobId);
    });
  }

  Future<void> _pollStatus(String jobId) async {
    try {
      final data = await LocalSyncApi.getScanStatus(jobId);
      final status = data['status'] as String? ?? 'running';

      state = state.copyWith(
        scanProcessed: data['processed'] as int? ?? 0,
        scanFailed: data['failed'] as int? ?? 0,
        scanSkipped: data['skipped'] as int? ?? 0,
        scanTotal: data['total'] as int? ?? state.scanTotal,
        currentFile: data['current_file'] as String?,
        currentIndex: data['current_index'] as int? ?? 0,
        scanStatus: status,
      );

      // Update per-file status from details
      final details = data['details'] as List<dynamic>?;
      if (details != null && details.isNotEmpty) {
        _updateFileStatuses(details);
      }

      if (status == 'completed') {
        _pollTimer?.cancel();
        state = state.copyWith(isScanning: false);
        // Refresh status to get updated processed count
        loadStatus();
      }
    } catch (e) {
      // Don't stop polling on transient errors
    }
  }

  void _updateFileStatuses(List<dynamic> details) {
    final statusMap = <String, Map<String, dynamic>>{};
    for (final d in details) {
      final detail = d as Map<String, dynamic>;
      final filepath = detail['filepath'] as String? ?? '';
      statusMap[filepath] = detail;
    }

    final updated = state.files.map((f) {
      final detail = statusMap[f.filepath];
      if (detail == null) return f;

      return f.copyWith(
        status: detail['status'] as String? ?? f.status,
        errorMessage: detail['error'] as String?,
      );
    }).toList();

    state = state.copyWith(files: updated);
  }

  /// Reset processed state for specific or all files.
  Future<void> resetFiles({List<String>? filepaths}) async {
    try {
      await LocalSyncApi.resetState(filepaths: filepaths);
      // Refresh file list and status
      await Future.wait([loadStatus(), fetchFiles()]);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

// ── Provider ────────────────────────────────────────────────────

final localSyncProvider =
    NotifierProvider<LocalSyncNotifier, LocalSyncState>(LocalSyncNotifier.new);
