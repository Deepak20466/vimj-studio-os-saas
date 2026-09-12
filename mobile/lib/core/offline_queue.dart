import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// A single queued "mark student attendance" request, persisted locally so a
/// coach can mark attendance with no signal and have it sync automatically
/// once connectivity returns.
class QueuedAttendance {
  final int? id;
  final int studentId;
  final int classId;
  final String status;
  final double lat;
  final double lng;
  final String? selfieBase64;
  final DateTime createdAt;

  QueuedAttendance({
    this.id,
    required this.studentId,
    required this.classId,
    required this.status,
    required this.lat,
    required this.lng,
    this.selfieBase64,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'student_id': studentId,
        'class_id': classId,
        'status': status,
        'lat': lat,
        'lng': lng,
        'selfie_base64': selfieBase64,
        'created_at': createdAt.toIso8601String(),
      };

  factory QueuedAttendance.fromMap(Map<String, dynamic> map) => QueuedAttendance(
        id: map['id'] as int?,
        studentId: map['student_id'] as int,
        classId: map['class_id'] as int,
        status: map['status'] as String,
        lat: map['lat'] as double,
        lng: map['lng'] as double,
        selfieBase64: map['selfie_base64'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// Marking is manual entry now (no GPS/selfie) — [lat]/[lng]/[selfieBase64]
  /// are unused legacy fields kept only so the persisted queue table's schema
  /// doesn't need a migration; the API body sends just the three fields the
  /// backend actually accepts.
  Map<String, dynamic> toApiBody() => {
        'student_id': studentId,
        'class_id': classId,
        'status': status,
      };
}

class OfflineQueue {
  static Database? _db;

  // sqflite has no web implementation, and this queue only exists to bridge
  // real connectivity gaps on a physical device — on web there's no offline
  // mode to bridge, so fall back to an in-memory list instead of crashing.
  static final List<QueuedAttendance> _webQueue = [];
  static int _webNextId = 1;

  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'vimj_offline_queue.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE queued_attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            class_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            selfie_base64 TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<int> enqueue(QueuedAttendance item) async {
    if (kIsWeb) {
      final id = _webNextId++;
      _webQueue.add(QueuedAttendance(
        id: id,
        studentId: item.studentId,
        classId: item.classId,
        status: item.status,
        lat: item.lat,
        lng: item.lng,
        selfieBase64: item.selfieBase64,
        createdAt: item.createdAt,
      ));
      return id;
    }
    final db = await _database();
    return db.insert('queued_attendance', item.toMap()..remove('id'));
  }

  static Future<List<QueuedAttendance>> pending() async {
    if (kIsWeb) {
      final sorted = [..._webQueue]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return sorted;
    }
    final db = await _database();
    final rows = await db.query('queued_attendance', orderBy: 'created_at ASC');
    return rows.map(QueuedAttendance.fromMap).toList();
  }

  static Future<void> remove(int id) async {
    if (kIsWeb) {
      _webQueue.removeWhere((e) => e.id == id);
      return;
    }
    final db = await _database();
    await db.delete('queued_attendance', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> pendingCount() async {
    if (kIsWeb) return _webQueue.length;
    final db = await _database();
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM queued_attendance');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

String encodeSelfie(List<int> bytes) => base64Encode(bytes);
