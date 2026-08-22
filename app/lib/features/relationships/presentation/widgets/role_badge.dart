import 'package:flutter/material.dart';

/// 멤버 목록에서 owner/member 역할을 나타내는 작은 배지.
class RoleBadge extends StatelessWidget {
  const RoleBadge({required this.isOwner, super.key});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isOwner
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isOwner ? '방장' : '멤버',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isOwner
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
