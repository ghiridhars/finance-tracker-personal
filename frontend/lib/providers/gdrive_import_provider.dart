/// GDriveImportNotifier — manages Google Drive OAuth connection, folder browsing,
/// file discovery, review overrides, and import progress polling.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api/gdrive_api.dart';
import 'local_sync_provider.dart'; // Reuse the LocalSyncFile model

// ── Models ──────────────────────────────────────────────────────

/// Represents a folder in Google Drive.
class GDriveFolder {
  final String id;
  final String name;

  const GDriveFolder({required this.id, required this.name});

  factory GDriveFolder.fromJson(Map<String, dynamic> json) {
    return GDriveFolder(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled Folder',
    );
  }
}

/// Overall state for the Google Drive import feature.
class GDriveImportState {
  final bool isConnected;
  final String? email;
  final bool secretsConfigured;

  // Browsing & discovery
  final List<GDriveFolder> currentPath; // Breadcrumbs: e.g. [{id: "root", name: "My Drive"}, ...]
  final List<GDriveFolder> folders;
  final List<LocalSyncFile> files;

  // Loading flags
  final bool isLoadingFolders;
  final bool isLoadingFiles;
  final bool isImporting;
  final String? currentJobId;

  // Import Job Results
  final int importProcessed;
  final int importFailed;
  final int importSkipped;
  final int importTotal;
  final String? importStatus; // started | running | completed | failed
  final String? currentFile;
  final int currentIndex;

  final String? error;
  final Map<String, String> bankPasswords;

  const GDriveImportState({
    this.isConnected = false,
    this.email,
    this.secretsConfigured = false,
    this.currentPath = const [],
    this.folders = const [],
    this.files = const [],
    this.isLoadingFolders = false,
    this.isLoadingFiles = false,
    this.isImporting = false,
    this.currentJobId,
    this.importProcessed = 0,
    this.importFailed = 0,
    this.importSkipped = 0,
    this.importTotal = 0,
    this.importStatus,
    this.currentFile,
    this.currentIndex = 0,
    this.error,
    this.bankPasswords = const {},
  });

  int get selectedCount => files.where((f) => f.selected).length;
  int get newFileCount => files.where((f) => !f.alreadyProcessed).length;
  String get currentFolderId => currentPath.isEmpty ? 'root' : currentPath.last.id;
  String get currentFolderName => currentPath.isEmpty ? 'My Drive' : currentPath.last.name;

  GDriveImportState copyWith({
    bool? isConnected,
    String? email,
    bool? secretsConfigured,
    List<GDriveFolder>? currentPath,
    List<GDriveFolder>? folders,
    List<LocalSyncFile>? files,
    bool? isLoadingFolders,
    bool? isLoadingFiles,
    bool? isImporting,
    String? currentJobId,
    int? importProcessed,
    int? importFailed,
    int? importSkipped,
    int? importTotal,
    String? importStatus,
    String? currentFile,
    int? currentIndex,
    String? error,
    Map<String, String>? bankPasswords,
    bool clearError = false,
    bool clearJobId = false,
    bool clearImportStatus = false,
  }) {
    return GDriveImportState(
      isConnected: isConnected ?? this.isConnected,
      email: email ?? this.email,
      secretsConfigured: secretsConfigured ?? this.secretsConfigured,
      currentPath: currentPath ?? this.currentPath,
      folders: folders ?? this.folders,
      files: files ?? this.files,
      isLoadingFolders: isLoadingFolders ?? this.isLoadingFolders,
      isLoadingFiles: isLoadingFiles ?? this.isLoadingFiles,
      isImporting: isImporting ?? this.isImporting,
      currentJobId: clearJobId ? null : (currentJobId ?? this.currentJobId),
      importProcessed: importProcessed ?? this.importProcessed,
      importFailed: importFailed ?? this.importFailed,
      importSkipped: importSkipped ?? this.importSkipped,
      importTotal: importTotal ?? this.importTotal,
      importStatus: clearImportStatus ? null : (importStatus ?? this.importStatus),
      currentFile: currentFile ?? this.currentFile,
      currentIndex: currentIndex ?? this.currentIndex,
      error: clearError ? null : (error ?? this.error),
      bankPasswords: bankPasswords ?? this.bankPasswords,
    );
  }
}

// ── Notifier ────────────────────────────────────────────────────

class GDriveImportNotifier extends Notifier<GDriveImportState> {
  Timer? _pollTimer;

  @override
  GDriveImportState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const GDriveImportState();
  }

  /// Load current connection and authorization status.
  Future<void> loadStatus() async {
    try {
      final data = await GDriveApi.getStatus();
      final connected = data['connected'] as bool? ?? false;
      state = state.copyWith(
        isConnected: connected,
        email: data['email'] as String?,
        secretsConfigured: data['secrets_configured'] as bool? ?? false,
        clearError: true,
      );

      // If connected, fetch the root directories automatically
      if (connected && state.folders.isEmpty && !state.isLoadingFolders) {
        await fetchFolders();
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Trigger account disconnection.
  Future<void> disconnect() async {
    try {
      await GDriveApi.disconnect();
      state = const GDriveImportState();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Retrieve the authentication consent URL.
  Future<String> getAuthUrl() async {
    try {
      return await GDriveApi.getAuthUrl();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  /// Fetch directories in the current folder.
  Future<void> fetchFolders() async {
    state = state.copyWith(
      isLoadingFolders: true,
      clearError: true,
    );

    try {
      final parentId = state.currentFolderId;
      final data = await GDriveApi.listFolders(parentId: parentId);
      final rawFolders = data['folders'] as List<dynamic>? ?? [];
      
      final folderList = rawFolders
          .map((f) => GDriveFolder.fromJson(f as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        folders: folderList,
        isLoadingFolders: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingFolders: false,
        error: e.toString(),
      );
    }
  }

  /// Scan for statements in the current selected folder.
  Future<void> scanCurrentFolder() async {
    if (state.currentFolderId == 'root' && state.currentPath.isEmpty) {
      state = state.copyWith(error: "Cannot scan files directly from the My Drive root. Navigate into a subfolder.");
      return;
    }

    state = state.copyWith(
      isLoadingFiles: true,
      clearError: true,
      clearImportStatus: true,
      files: const [], // Clear previous
    );

    try {
      final data = await GDriveApi.listFiles(folderId: state.currentFolderId);
      final rawFiles = data['files'] as List<dynamic>? ?? [];
      
      final fileList = rawFiles
          .map((f) => LocalSyncFile.fromJson(f as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        files: fileList,
        isLoadingFiles: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingFiles: false,
        error: e.toString(),
      );
    }
  }

  /// Navigate inside a subdirectory.
  Future<void> navigateInto(GDriveFolder folder) async {
    final updatedPath = List<GDriveFolder>.from(state.currentPath)..add(folder);
    state = state.copyWith(
      currentPath: updatedPath,
      files: const [], // Reset files scanning state
    );
    await fetchFolders();
  }

  /// Navigate back to a higher folder using breadcrumbs.
  Future<void> navigateBack(int index) async {
    // index is from breadcrumbs loop. If index is -1, it means 'My Drive' root.
    List<GDriveFolder> updatedPath = [];
    if (index >= 0) {
      updatedPath = state.currentPath.sublist(0, index + 1);
    }
    
    state = state.copyWith(
      currentPath: updatedPath,
      files: const [],
    );
    await fetchFolders();
  }

  /// Toggle selection of a statement file.
  void toggleFile(int index) {
    if (index < 0 || index >= state.files.length) return;
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selected: !updated[index].selected);
    state = state.copyWith(files: updated);
  }

  /// Select all statement files.
  void selectAll() {
    state = state.copyWith(
      files: state.files.map((f) => f.copyWith(selected: true)).toList(),
    );
  }

  /// Deselect all statement files.
  void deselectAll() {
    state = state.copyWith(
      files: state.files.map((f) => f.copyWith(selected: false)).toList(),
    );
  }

  /// Update the bank dropdown choice for a scanned file.
  void updateFileBank(int index, String bank) {
    if (index < 0 || index >= state.files.length) return;
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selectedBank: bank);
    state = state.copyWith(files: updated);
  }

  /// Update the type dropdown choice (savings/cc) for a scanned file.
  void updateFileType(int index, String type) {
    if (index < 0 || index >= state.files.length) return;
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selectedType: type);
    state = state.copyWith(files: updated);
  }

  /// Update session-only password cache for a bank.
  void updateBankPassword(String bank, String password) {
    final updated = Map<String, String>.from(state.bankPasswords);
    if (password.isEmpty) {
      updated.remove(bank);
    } else {
      updated[bank] = password;
    }
    state = state.copyWith(bankPasswords: updated);
  }

  /// Clear the active error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Start the background import for selected statement files.
  Future<void> startImport({bool force = false}) async {
    final selectedFiles = state.files.where((f) => f.selected).toList();
    if (selectedFiles.isEmpty) {
      state = state.copyWith(error: 'No files selected');
      return;
    }

    state = state.copyWith(
      isImporting: true,
      clearError: true,
      importProcessed: 0,
      importFailed: 0,
      importSkipped: 0,
      importTotal: selectedFiles.length,
      importStatus: 'started',
      currentIndex: 0,
    );

    try {
      final filesPayload = selectedFiles
          .map((f) => {
                'filepath': f.filepath, // Drive file ID
                'filename': f.filename,
                'bank': f.selectedBank,
                'type': f.selectedType,
              })
          .toList();

      final data = await GDriveApi.startImport(
        files: filesPayload,
        force: force,
        bankPasswords: state.bankPasswords.isNotEmpty
            ? state.bankPasswords
            : null,
      );

      final jobId = data['job_id'] as String;
      state = state.copyWith(
        currentJobId: jobId,
        importStatus: 'running',
      );

      _startPolling(jobId);
    } catch (e) {
      state = state.copyWith(
        isImporting: false,
        error: e.toString(),
        importStatus: 'failed',
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
      final data = await GDriveApi.getImportStatus(jobId);
      final status = data['status'] as String? ?? 'running';

      state = state.copyWith(
        importProcessed: data['processed'] as int? ?? 0,
        importFailed: data['failed'] as int? ?? 0,
        importSkipped: data['skipped'] as int? ?? 0,
        importTotal: data['total'] as int? ?? state.importTotal,
        currentFile: data['current_file'] as String?,
        currentIndex: data['current_index'] as int? ?? 0,
        importStatus: status,
      );

      final details = data['details'] as List<dynamic>?;
      if (details != null && details.isNotEmpty) {
        _updateFileStatuses(details);
      }

      if (status == 'completed') {
        _pollTimer?.cancel();
        state = state.copyWith(isImporting: false);
      }
    } catch (e) {
      // Don't stop polling on transient networking errors
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

  /// Reset processed states for specific file IDs or all files in current session.
  Future<void> resetFiles({List<String>? fileIds}) async {
    try {
      await GDriveApi.resetState(fileIds: fileIds);
      // Re-scan current folder to refresh connection indicators
      await scanCurrentFolder();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

// ── Provider ────────────────────────────────────────────────────

final gdriveImportProvider =
    NotifierProvider<GDriveImportNotifier, GDriveImportState>(GDriveImportNotifier.new);
