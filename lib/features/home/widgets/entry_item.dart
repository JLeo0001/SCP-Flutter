import 'package:flutter/material.dart';

/// 首页入口项 - 对应 EntryItem.kt
class EntryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const EntryItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
