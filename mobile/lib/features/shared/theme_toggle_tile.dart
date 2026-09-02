import 'package:flutter/material.dart';
import '../../core/theme_controller.dart';

class ThemeToggleTile extends StatelessWidget {
  const ThemeToggleTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('Theme'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 18)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => ThemeController.setMode(selection.first),
            showSelectedIcon: false,
          ),
        );
      },
    );
  }
}
