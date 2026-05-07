import 'package:flutter/material.dart';
// ============================================================
// @remind THEMATIC BREAK
// ============================================================

class ThematicBreakWidget extends StatelessWidget {
  const ThematicBreakWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(thickness: 1, color: Colors.grey),
    );
  }
}
