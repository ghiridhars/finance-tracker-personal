/// Settings Screen — user preferences and app configuration.
///
/// Features:
///   - Backend URL configuration
///   - Currency symbol selection
///   - Theme mode selector (system/light/dark)
///   - Clear all data action
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_settings_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/upi_management_widget.dart';
import 'database_manager_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  bool? _backendReachable;

  // Google Drive sync state
  Map<String, dynamic>? _driveStatus;
  List<dynamic>? _driveFiles;
  bool _isSyncing = false;
  bool _isLoadingDrive = false;
  String? _syncResult;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    Future.microtask(() {
      final settings = ref.read(appSettingsProvider);
      _urlController.text = settings.baseUrl;
      _loadDriveStatus();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _backendReachable = null;
    });
    try {
      await ApiService.healthCheck();
      setState(() => _backendReachable = true);
    } catch (_) {
      setState(() => _backendReachable = false);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber, size: 48, color: Colors.red),
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete ALL transactions, statements, accounts, '
          'budgets, goals, and reminders. This action cannot be undone.\n\n'
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Double confirm
    final reallyConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: const Text('Type DELETE to confirm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );

    if (reallyConfirmed != true || !mounted) return;

    try {
      await ApiService.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear data: $e')),
        );
      }
    }
  }

  Future<void> _loadDriveStatus() async {
    try {
      final status = await ApiService.getGDriveStatus();
      if (mounted) setState(() => _driveStatus = status);
    } catch (_) {
      // Drive not configured — that's fine
    }
  }

  Future<void> _loadDriveFiles() async {
    setState(() => _isLoadingDrive = true);
    try {
      final result = await ApiService.getGDriveFiles();
      if (mounted) {
        setState(() {
          _driveFiles = result['files'] as List<dynamic>?;
          _isLoadingDrive = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDrive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to list Drive files: $e')),
        );
      }
    }
  }

  Future<void> _triggerSync({bool force = false}) async {
    setState(() {
      _isSyncing = true;
      _syncResult = null;
    });
    try {
      final result = await ApiService.syncFromGDrive(force: force);
      if (mounted) {
        final processed = result['processed'] ?? 0;
        final skipped = result['skipped'] ?? 0;
        final failed = result['failed'] ?? 0;
        setState(() {
          _isSyncing = false;
          _syncResult = '$processed processed, $skipped skipped, $failed failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync complete: $_syncResult')),
        );
        _loadDriveStatus();
        _loadDriveFiles();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncResult = 'Error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Appearance Section ─────────────────────────
              _SectionHeader(title: 'Appearance', icon: Icons.palette),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme Mode',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (modes) {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setThemeMode(modes.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Currency',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '₹', label: Text('₹ INR')),
                          ButtonSegment(value: '\$', label: Text('\$ USD')),
                          ButtonSegment(value: '€', label: Text('€ EUR')),
                          ButtonSegment(value: '£', label: Text('£ GBP')),
                        ],
                        selected: {settings.currency},
                        onSelectionChanged: (currencies) {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setCurrency(currencies.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Backend Connection Section ─────────────────
              _SectionHeader(title: 'Backend Connection', icon: Icons.dns),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          labelText: 'Backend URL',
                          hintText: 'http://127.0.0.1:8080',
                          prefixIcon: const Icon(Icons.link),
                          suffixIcon: _backendReachable != null
                              ? Icon(
                                  _backendReachable!
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _backendReachable!
                                      ? Colors.green
                                      : colorScheme.error,
                                )
                              : null,
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            ref
                                .read(appSettingsProvider.notifier)
                                .setBaseUrl(value.trim());
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_tethering),
                            label: const Text('Test Connection'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () {
                              final url = _urlController.text.trim();
                              if (url.isNotEmpty) {
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .setBaseUrl(url);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Backend URL saved')),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                      if (_backendReachable != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _backendReachable!
                                ? Colors.green.withValues(alpha: 0.1)
                                : colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _backendReachable!
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                size: 18,
                                color: _backendReachable!
                                    ? Colors.green
                                    : colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _backendReachable!
                                    ? 'Backend is reachable'
                                    : 'Cannot connect to backend',
                                style: TextStyle(
                                  color: _backendReachable!
                                      ? Colors.green.shade800
                                      : colorScheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Google Drive Sync Section ──────────────────
              _SectionHeader(
                  title: 'Google Drive Sync', icon: Icons.cloud_sync),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_driveStatus == null)
                        const Text(
                          'Loading sync status...',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        )
                      else if (_driveStatus!['enabled'] != true)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Google Drive sync is not configured.',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'To enable, set these in your backend .env file:\n'
                                    '• GDRIVE_ENABLED=true\n'
                                    '• GDRIVE_CREDENTIALS_FILE=path/to/service-account.json\n'
                                    '• GDRIVE_FOLDER_ID=your-folder-id',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        // Status row
                        Row(
                          children: [
                            Icon(
                              _driveStatus!['credentials_configured'] == true
                                  ? Icons.check_circle
                                  : Icons.error,
                              color:
                                  _driveStatus!['credentials_configured'] == true
                                      ? Colors.green
                                      : colorScheme.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _driveStatus!['credentials_configured'] == true
                                  ? 'Connected to Google Drive'
                                  : 'Credentials not configured',
                            ),
                          ],
                        ),
                        if (_driveStatus!['last_sync'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Last sync: ${_driveStatus!['last_sync']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (_driveStatus!['processed_file_count'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Files processed: ${_driveStatus!['processed_file_count']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Action buttons
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _isSyncing ? null : () => _triggerSync(),
                              icon: _isSyncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync),
                              label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isSyncing
                                  ? null
                                  : () => _triggerSync(force: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Force Re-sync'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _isLoadingDrive ? null : _loadDriveFiles,
                              icon: _isLoadingDrive
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.folder_open),
                              label: const Text('View Files'),
                            ),
                          ],
                        ),

                        // Sync result
                        if (_syncResult != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _syncResult!.startsWith('Error')
                                  ? colorScheme.errorContainer
                                  : Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _syncResult!,
                              style: TextStyle(
                                color: _syncResult!.startsWith('Error')
                                    ? colorScheme.onErrorContainer
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],

                        // File list
                        if (_driveFiles != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Files in Drive folder (${_driveFiles!.length}):',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          if (_driveFiles!.isEmpty)
                            const Text('No statement files found.')
                          else
                            ...(_driveFiles!.map((f) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        f['already_processed'] == true
                                            ? Icons.check_circle_outline
                                            : Icons.insert_drive_file,
                                        size: 16,
                                        color: f['already_processed'] == true
                                            ? Colors.green
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          f['name'] ?? 'Unknown',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                      if (f['already_processed'] == true)
                                        Text(
                                          'Processed',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.green,
                                              ),
                                        ),
                                    ],
                                  ),
                                ))),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Data Management Section ────────────────────
              _SectionHeader(
                  title: 'Data Management', icon: Icons.storage),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: Icon(Icons.delete_forever,
                            color: colorScheme.error),
                        title: const Text('Clear All Data'),
                        subtitle: const Text(
                          'Delete all transactions, statements, accounts, budgets, and goals',
                        ),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.error),
                          onPressed: _clearAllData,
                          child: const Text('Clear'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // ── Account Section ─────────────────────────────────
              _SectionHeader(title: 'Account', icon: Icons.person),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign Out'),
                    subtitle: Text(
                      'Signed in as ${ref.watch(authProvider).username ?? "unknown"}',
                    ),
                    trailing: OutlinedButton(
                      onPressed: () {
                        ref.read(authProvider.notifier).logout();
                      },
                      child: const Text('Sign Out'),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // ── UPI ID Management ───────────────────────────
              _SectionHeader(title: 'UPI IDs', icon: Icons.qr_code_2),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: const UpiManagementPanel(),
                ),
              ),

              const SizedBox(height: 24),
              // ── Advanced Section ───────────────────────────
              _SectionHeader(title: 'Advanced', icon: Icons.build_outlined),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Database Manager'),
                  subtitle: const Text(
                    'Browse and edit database tables directly',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DatabaseManagerScreen(),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),
              // ── About Section ──────────────────────────────
              _SectionHeader(title: 'About', icon: Icons.info_outline),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AboutRow(label: 'App', value: 'Finance Tracker v2'),
                      _AboutRow(label: 'Stack', value: 'Flutter + FastAPI'),
                      _AboutRow(
                          label: 'Backend',
                          value: settings.baseUrl),
                      _AboutRow(
                          label: 'Currency',
                          value: settings.currency),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
