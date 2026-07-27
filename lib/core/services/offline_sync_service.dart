import 'dart:async';
import 'package:flutter/foundation.dart';

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.action,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String action;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService() {
    // Simulate periodic connectivity check
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => checkConnectivity());
  }

  bool _isOnline = true;
  bool _isSyncing = false;
  final List<SyncQueueItem> _queue = [];
  Timer? _timer;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _queue.length;
  List<SyncQueueItem> get queue => List.unmodifiable(_queue);

  void setOnlineStatus(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    notifyListeners();
    if (_isOnline && _queue.isNotEmpty) {
      triggerSync();
    }
  }

  void enqueueAction({
    required String entityType,
    required String action,
    required Map<String, dynamic> payload,
  }) {
    final item = SyncQueueItem(
      id: 'sync-${DateTime.now().millisecondsSinceEpoch}',
      entityType: entityType,
      action: action,
      payload: payload,
      createdAt: DateTime.now(),
    );
    _queue.add(item);
    notifyListeners();

    if (_isOnline) {
      triggerSync();
    }
  }

  Future<void> triggerSync() async {
    if (_isSyncing || _queue.isEmpty) return;
    _isSyncing = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800)); // Simulate network sync

    _queue.clear();
    _isSyncing = false;
    notifyListeners();
  }

  void checkConnectivity() {
    // Keep online state synchronized
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
