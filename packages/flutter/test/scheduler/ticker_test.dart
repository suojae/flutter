// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

void main() {
  Future<void> setAppLifeCycleState(AppLifecycleState state) async {
    final ByteData? message = const StringCodec().encodeMessage(state.toString());
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      message,
      (_) {},
    );
  }

  testWidgets('Ticker mute control test', (WidgetTester tester) async {
    var tickCount = 0;
    void handleTick(Duration duration) {
      tickCount += 1;
    }

    final ticker = Ticker(handleTick);
    addTearDown(ticker.dispose);

    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isFalse);

    ticker.start();

    expect(ticker.isTicking, isTrue);
    expect(ticker.isActive, isTrue);
    expect(tickCount, equals(0));

    FlutterError? error;
    try {
      ticker.start();
    } on FlutterError catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(error!.diagnostics.length, 3);
    expect(error.diagnostics.last, isA<DiagnosticsBlock>());
    expect(error.diagnostics.last.value, ticker);
    expect(
      error.toStringDeep(),
      startsWith(
        'FlutterError\n'
        '   A ticker was started twice.\n'
        '   A ticker that is already active cannot be started again without\n'
        '   first stopping it.\n'
        '   The affected ticker was: Ticker():\n'
        '     The stack trace when the Ticker was actually created was:\n',
      ),
    );

    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(1));

    ticker.muted = true;
    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(1));
    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isTrue);

    ticker.muted = false;
    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(2));
    expect(ticker.isTicking, isTrue);
    expect(ticker.isActive, isTrue);

    ticker.muted = true;
    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(2));
    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isTrue);

    ticker.stop();

    expect(tickCount, equals(2));
    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isFalse);

    ticker.muted = false;

    expect(tickCount, equals(2));
    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isFalse);

    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(2));
    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isFalse);
  });

  testWidgets('Ticker control test', (WidgetTester tester) async {
    late Ticker ticker;
    addTearDown(() => ticker.dispose());

    void testFunction() {
      ticker = Ticker((Duration _) {});
    }

    testFunction();

    expect(ticker, hasOneLineDescription);
    expect(ticker.toString(debugIncludeStack: true), contains('testFunction'));
  });

  testWidgets('Ticker.describeForError includes the creation stack trace', (
    WidgetTester tester,
  ) async {
    late Ticker ticker;
    addTearDown(() => ticker.dispose());

    void testFunction() {
      ticker = Ticker((Duration _) {});
    }

    testFunction();

    final DiagnosticsNode node = ticker.describeForError('The ticker was');
    expect(node.value, ticker);
    expect(node.toDescription(), 'Ticker()');
    final DiagnosticsNode stackTrace = node.getProperties().single;
    expect(stackTrace, isA<DiagnosticsStackTrace>());
    expect(stackTrace.name, 'The stack trace when the Ticker was actually created was');
    final List<String> frames = stackTrace
        .getProperties()
        .map((DiagnosticsNode frame) => frame.toDescription())
        .toList();
    expect(frames, contains(contains('testFunction')));

    // Stack frames are not wrapped when the error is rendered.
    final String rendered = FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('A ticker error.'),
      node,
    ]).toStringDeep();
    for (final frame in frames) {
      expect(rendered, contains(frame));
    }
  });

  testWidgets('Ticker can be sped up with time dilation', (WidgetTester tester) async {
    timeDilation = 0.5; // Move twice as fast.
    late Duration lastDuration;
    void handleTick(Duration duration) {
      lastDuration = duration;
    }

    final ticker = Ticker(handleTick);
    ticker.start();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    expect(lastDuration, const Duration(milliseconds: 20));

    ticker.dispose();

    timeDilation = 1.0; // restore time dilation, or it will affect other tests
  });

  testWidgets('Ticker can be slowed down with time dilation', (WidgetTester tester) async {
    timeDilation = 2.0; // Move half as fast.
    late Duration lastDuration;
    void handleTick(Duration duration) {
      lastDuration = duration;
    }

    final ticker = Ticker(handleTick);
    ticker.start();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    expect(lastDuration, const Duration(milliseconds: 5));

    ticker.dispose();

    timeDilation = 1.0; // restore time dilation, or it will affect other tests
  });

  testWidgets('Ticker stops ticking when application is paused', (WidgetTester tester) async {
    var tickCount = 0;
    void handleTick(Duration duration) {
      tickCount += 1;
    }

    final ticker = Ticker(handleTick);
    addTearDown(ticker.dispose);
    ticker.start();

    expect(ticker.isTicking, isTrue);
    expect(ticker.isActive, isTrue);
    expect(tickCount, equals(0));

    await setAppLifeCycleState(AppLifecycleState.paused);

    expect(ticker.isTicking, isFalse);
    expect(ticker.isActive, isTrue);

    ticker.stop();

    await setAppLifeCycleState(AppLifecycleState.resumed);
  });

  testWidgets('Ticker can be created before application unpauses', (WidgetTester tester) async {
    await setAppLifeCycleState(AppLifecycleState.paused);

    var tickCount = 0;
    void handleTick(Duration duration) {
      tickCount += 1;
    }

    final ticker = Ticker(handleTick);
    addTearDown(ticker.dispose);
    ticker.start();

    expect(tickCount, equals(0));
    expect(ticker.isTicking, isFalse);

    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(0));
    expect(ticker.isTicking, isFalse);

    await setAppLifeCycleState(AppLifecycleState.resumed);

    await tester.pump(const Duration(milliseconds: 10));

    expect(tickCount, equals(1));
    expect(ticker.isTicking, isTrue);

    ticker.stop();
  });

  test('Ticker dispatches memory events', () async {
    await expectLater(
      await memoryEvents(() => Ticker((_) {}).dispose(), Ticker),
      areCreateAndDispose,
    );
  });
}
