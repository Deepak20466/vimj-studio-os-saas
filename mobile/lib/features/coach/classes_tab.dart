import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/models.dart';
import 'mark_attendance_screen.dart';

class ClassesTab extends StatefulWidget {
  const ClassesTab({super.key});

  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  DateTime _selectedDate = DateTime.now();
  List<ClassSession> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await ApiClient.instance.get('/activities/classes/my', query: {'class_date': dateStr}) as List;
      _classes = data.map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Classes'),
        actions: [IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate), style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _classes.isEmpty
                    ? const Center(child: Text('No classes on this date.'))
                    : ListView.builder(
                        itemCount: _classes.length,
                        itemBuilder: (context, i) {
                          final c = _classes[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: const Icon(Icons.fitness_center),
                              title: Text('${c.startTime} - ${c.endTime}'),
                              subtitle: Text('Class #${c.id} · Activity #${c.activityId}'),
                              trailing: ElevatedButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => MarkAttendanceScreen(classSession: c)),
                                ),
                                child: const Text('Mark'),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
