/// Widget test for Local Sync Screen — verifies UI structure and interactions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:finance_tracker_frontend/providers/local_sync_provider.dart';
import 'package:finance_tracker_frontend/screens/local_sync_screen.dart';

/// A test notifier that exposes state without making API calls.
class MockLocalSyncNotifier extends Notifier<LocalSyncState>
    implements LocalSyncNotifier {
  LocalSyncState _initial;

  MockLocalSyncNotifier([this._initial = const LocalSyncState()]);

  @override
  LocalSyncState build() => _initial;

  @override
  Future<void> loadStatus() async {}

  @override
  Future<void> configurePath(String path) async {
    state = state.copyWith(configuredPath: path, pathExists: true);
  }

  @override
  Future<void> fetchFiles() async {}

  @override
  void updateFileBank(int index, String bank) {}

  @override
  void updateFileType(int index, String type) {}

  @override
  void toggleFile(int index) {
    final updated = List<LocalSyncFile>.from(state.files);
    updated[index] = updated[index].copyWith(selected: !updated[index].selected);
    state = state.copyWith(files: updated);
  }

  @override
  void selectAll() {
    state = state.copyWith(
      files: state.files.map((f) => f.copyWith(selected: true)).toList(),
    );
  }

  @override
  void deselectAll() {
    state = state.copyWith(
      files: state.files.map((f) => f.copyWith(selected: false)).toList(),
    );
  }

  @override
  Future<void> startScan({bool force = false}) async {}

  @override
  Future<void> resetFiles({List<String>? filepaths}) async {}
}

Widget _wrap(Widget child, {required List<dynamic> overrides}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: child,
        ),
      ),
    ),
  );
}

LocalSyncFile _makeFile({
  String filename = 'test.pdf',
  String bank = 'HDFC',
  String type = 'CREDIT_CARD',
  bool alreadyProcessed = false,
  bool selected = true,
}) {
  return LocalSyncFile(
    filepath: '/tmp/$filename',
    relativePath: filename,
    filename: filename,
    size: 1024,
    modifiedTime: '2025-01-01T00:00:00Z',
    inferredBank: bank,
    inferredType: type,
    alreadyProcessed: alreadyProcessed,
    fileKey: 'abc123',
    selectedBank: bank,
    selectedType: type,
    selected: selected,
    status: alreadyProcessed ? 'skipped' : 'pending',
  );
}

void _setWideView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
}

void main() {
  group('LocalSyncScreen', () {
    testWidgets('shows path configuration section', (tester) async {
      _setWideView(tester);

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => MockLocalSyncNotifier()),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Local Directory Import'), findsOneWidget);
      expect(find.text('Directory Path'), findsOneWidget);
    });

    testWidgets('shows Scan for Files button when path configured', (tester) async {
      _setWideView(tester);
      final notifier = MockLocalSyncNotifier(
        const LocalSyncState(configuredPath: '/tmp/statements', pathExists: true),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Scan for Files'), findsOneWidget);
      expect(find.text('Path configured'), findsOneWidget);
    });

    testWidgets('shows file list with select controls', (tester) async {
      _setWideView(tester);
      final files = [
        _makeFile(filename: 'hdfc_cc_jan.pdf', bank: 'HDFC', type: 'CREDIT_CARD'),
        _makeFile(filename: 'icici_savings.csv', bank: 'ICICI', type: 'SAVINGS'),
      ];

      final notifier = MockLocalSyncNotifier(
        LocalSyncState(
          configuredPath: '/tmp/statements',
          pathExists: true,
          files: files,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('2 files found'), findsOneWidget);
      expect(find.text('hdfc_cc_jan.pdf'), findsOneWidget);
      expect(find.text('icici_savings.csv'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);
    });

    testWidgets('shows import button with selected count', (tester) async {
      _setWideView(tester);
      final files = [
        _makeFile(filename: 'a.pdf', selected: true),
        _makeFile(filename: 'b.pdf', selected: false),
      ];

      final notifier = MockLocalSyncNotifier(
        LocalSyncState(
          configuredPath: '/tmp',
          pathExists: true,
          files: files,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Import Selected (1)'), findsOneWidget);
    });

    testWidgets('shows progress section during scan', (tester) async {
      _setWideView(tester);
      final notifier = MockLocalSyncNotifier(
        const LocalSyncState(
          configuredPath: '/tmp',
          pathExists: true,
          isScanning: true,
          scanStatus: 'running',
          scanTotal: 5,
          currentIndex: 2,
          currentFile: 'test.pdf',
          scanProcessed: 1,
          scanFailed: 0,
          scanSkipped: 0,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Importing...'), findsWidgets);
      expect(find.textContaining('Processing 2 of 5'), findsOneWidget);
    });

    testWidgets('shows completion summary', (tester) async {
      _setWideView(tester);
      final notifier = MockLocalSyncNotifier(
        const LocalSyncState(
          configuredPath: '/tmp',
          pathExists: true,
          scanStatus: 'completed',
          scanProcessed: 10,
          scanFailed: 1,
          scanSkipped: 2,
          scanTotal: 13,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Import Complete'), findsOneWidget);
      expect(find.text('10 processed'), findsOneWidget);
      expect(find.text('1 failed'), findsOneWidget);
      expect(find.text('2 skipped'), findsOneWidget);
    });

    testWidgets('shows error banner', (tester) async {
      _setWideView(tester);
      final notifier = MockLocalSyncNotifier(
        const LocalSyncState(error: 'Something went wrong'),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('already-processed files show done icon', (tester) async {
      _setWideView(tester);
      final files = [
        _makeFile(filename: 'old.pdf', alreadyProcessed: true, selected: false),
      ];

      final notifier = MockLocalSyncNotifier(
        LocalSyncState(
          configuredPath: '/tmp',
          pathExists: true,
          files: files,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const LocalSyncScreen(),
          overrides: [
            localSyncProvider.overrideWith(() => notifier),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('old.pdf'), findsOneWidget);
      expect(find.text('1 already processed'), findsOneWidget);
    });
  });
}
