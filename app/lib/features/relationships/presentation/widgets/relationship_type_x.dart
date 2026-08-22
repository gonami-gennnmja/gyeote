import 'package:flutter/material.dart';

/// `relationship_groups.type`('couple' | 'family' | 'friend') 문자열에 대한
/// 표시용 아이콘/라벨 매핑. 그룹 목록/생성/상세 화면에서 공통으로 사용한다.
extension RelationshipTypeX on String {
  IconData get relationshipTypeIcon {
    switch (this) {
      case 'couple':
        return Icons.favorite;
      case 'family':
        return Icons.home;
      case 'friend':
        return Icons.groups;
      default:
        return Icons.group;
    }
  }

  String get relationshipTypeLabel {
    switch (this) {
      case 'couple':
        return '커플';
      case 'family':
        return '가족';
      case 'friend':
        return '친구';
      default:
        return this;
    }
  }
}
