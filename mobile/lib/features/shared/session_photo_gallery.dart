import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/export_helper.dart';

/// Shared Admin/Coach gallery. The API scopes Coach results and delete access
/// to the signed-in coach, while Admins can manage every uploaded session photo.
class SessionPhotoGallery extends StatefulWidget {
  const SessionPhotoGallery({super.key});

  @override
  State<SessionPhotoGallery> createState() => _SessionPhotoGalleryState();
}

class _SessionPhotoGalleryState extends State<SessionPhotoGallery> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _dateFilter = 'all';
  DateTime _filterDate = DateTime.now();
  int? _busyPhotoId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await ApiClient.instance.get('/activities/session-photos') as List;
      _photos = data.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseFilter(String filter) async {
    if (filter == 'date') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _filterDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      setState(() {
        _dateFilter = filter;
        _filterDate = picked;
      });
      return;
    }
    setState(() {
      _dateFilter = filter;
      if (filter != 'all') _filterDate = DateTime.now();
    });
  }

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _filterDate = picked);
  }

  List<Map<String, dynamic>> get _visiblePhotos {
    final q = _query.trim().toLowerCase();
    return _photos.where((photo) {
      final date = DateTime.tryParse(photo['date'] as String? ?? '');
      final textMatch = q.isEmpty ||
          ['activity_name', 'coach_name', 'date', 'start_time', 'end_time']
              .any((key) => '${photo[key] ?? ''}'.toLowerCase().contains(q));
      var dateMatch = true;
      if (date != null) {
        if (_dateFilter == 'day' || _dateFilter == 'date') {
          dateMatch = date.year == _filterDate.year &&
              date.month == _filterDate.month &&
              date.day == _filterDate.day;
        } else if (_dateFilter == 'month') {
          dateMatch =
              date.year == _filterDate.year && date.month == _filterDate.month;
        } else if (_dateFilter == 'year') {
          dateMatch = date.year == _filterDate.year;
        }
      }
      return textMatch && dateMatch;
    }).toList();
  }

  Future<void> _downloadPhoto(Map<String, dynamic> photo) async {
    final id = photo['class_id'] as int;
    setState(() => _busyPhotoId = id);
    try {
      final bytes = await ApiClient.instance
          .getBytes('/activities/classes/$id/group-photo');
      await shareExportedFile(bytes, 'session_${id}_${photo['date']}.jpg');
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted)
        _showMessage('Could not download the session photo. Please try again.');
    } finally {
      if (mounted) setState(() => _busyPhotoId = null);
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final id = photo['class_id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete session photo?'),
        content: Text(
            'Delete the ${photo['activity_name']} photo from ${photo['date']}? The class and attendance will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyPhotoId = id);
    try {
      await ApiClient.instance.delete('/activities/classes/$id/group-photo');
      if (!mounted) return;
      setState(() {
        _photos.removeWhere((p) => p['class_id'] == id);
        _busyPhotoId = null;
      });
      _showMessage('Session photo deleted');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyPhotoId = null);
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyPhotoId = null);
      _showMessage('Could not delete the session photo. Please try again.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _viewPhoto(Map<String, dynamic> photo) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${photo['activity_name']} · ${photo['date']}'),
        content: SizedBox(
          width: 320,
          height: 320,
          child: FutureBuilder<List<int>>(
            future: ApiClient.instance.getBytes(
                '/activities/classes/${photo['class_id']}/group-photo'),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Center(child: Text('Photo could not be loaded.'));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              return Image.memory(Uint8List.fromList(snapshot.data!),
                  fit: BoxFit.contain);
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) => ChoiceChip(
        label: Text(label),
        selected: _dateFilter == value,
        onSelected: (_) => _chooseFilter(value),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Session Photos')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search activity, coach, or date',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _query = ''),
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  _filterChip('Any date', 'all'),
                  _filterChip('Day', 'day'),
                  _filterChip('Month', 'month'),
                  _filterChip('Year', 'year'),
                  _filterChip('Choose date', 'date'),
                ],
              ),
            ),
            if (_dateFilter != 'all')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextButton.icon(
                  onPressed: _pickFilterDate,
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(_dateFilter == 'year'
                      ? '${_filterDate.year}'
                      : _dateFilter == 'month'
                          ? '${_filterDate.month}/${_filterDate.year}'
                          : _filterDate.toIso8601String().substring(0, 10)),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!),
                              TextButton(
                                  onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: _photos.isEmpty
                              ? ListView(children: const [
                                  Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Center(
                                        child: Text(
                                            'No session photos have been uploaded yet.')),
                                  ),
                                ])
                              : _visiblePhotos.isEmpty
                                  ? ListView(children: const [
                                      Padding(
                                        padding: EdgeInsets.all(32),
                                        child: Center(
                                            child: Text(
                                                'No photos match the search or date filter.')),
                                      ),
                                    ])
                                  : ListView.builder(
                                      itemCount: _visiblePhotos.length,
                                      itemBuilder: (context, index) {
                                        final photo = _visiblePhotos[index];
                                        final id = photo['class_id'] as int;
                                        final busy = _busyPhotoId == id;
                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 5),
                                          child: ListTile(
                                            leading: const CircleAvatar(
                                                child: Icon(Icons.photo)),
                                            title: Text(
                                                '${photo['activity_name']} · ${photo['date']}'),
                                            subtitle: Text(
                                                '${photo['start_time']}–${photo['end_time']} · Coach: ${photo['coach_name']}'),
                                            onTap: () => _viewPhoto(photo),
                                            trailing: busy
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                          tooltip:
                                                              'Download photo',
                                                          icon: const Icon(Icons
                                                              .download_outlined),
                                                          onPressed: () =>
                                                              _downloadPhoto(
                                                                  photo)),
                                                      IconButton(
                                                          tooltip:
                                                              'Delete photo',
                                                          icon: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              color: AppColors
                                                                  .danger),
                                                          onPressed: () =>
                                                              _deletePhoto(
                                                                  photo)),
                                                    ],
                                                  ),
                                          ),
                                        );
                                      },
                                    ),
                        ),
            ),
          ],
        ),
      );
}
