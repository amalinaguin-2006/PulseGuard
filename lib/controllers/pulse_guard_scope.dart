// lib/controllers/pulse_guard_scope.dart
//
// PulseGuard — Application-wide state scope using pure Flutter InheritedWidget.
// No external state libraries (no Provider / Riverpod / Bloc).

import 'package:flutter/widgets.dart';

import 'history_controller.dart';
import 'measurement_controller.dart';
import 'session_controller.dart';

/// Top-level [InheritedWidget] providing access to all core application controllers.
class PulseGuardScope extends InheritedWidget {
  final SessionController sessionController;
  final HistoryController historyController;
  final MeasurementController measurementController;

  const PulseGuardScope({
    super.key,
    required this.sessionController,
    required this.historyController,
    required this.measurementController,
    required super.child,
  });

  /// Retrieves the closest [PulseGuardScope] ancestor in the widget tree.
  static PulseGuardScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PulseGuardScope>();
    assert(scope != null, 'No PulseGuardScope found in BuildContext');
    return scope!;
  }

  @override
  bool updateShouldNotify(PulseGuardScope oldWidget) {
    return sessionController != oldWidget.sessionController ||
        historyController != oldWidget.historyController ||
        measurementController != oldWidget.measurementController;
  }
}
