/// `relationship_groups` 테이블 한 행을 표현하는 모델.
///
/// `type`은 DB의 `relationship_type` enum('couple' | 'family' | 'friend')을
/// 그대로 문자열로 다룬다. 실제 표시용 아이콘/라벨은
/// `presentation/widgets/relationship_type_x.dart`에서 매핑한다.
class RelationshipGroup {
  const RelationshipGroup({
    required this.id,
    required this.type,
    required this.name,
    required this.createdBy,
    required this.createdAt,
  });

  factory RelationshipGroup.fromJson(Map<String, dynamic> json) {
    return RelationshipGroup(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String type;
  final String? name;
  final String? createdBy;
  final DateTime createdAt;

  /// 이름이 없을 때 목록/상세 화면에 보여줄 기본 표시명.
  String displayName(String typeLabel) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '이름 없는 $typeLabel 그룹';
    }
    return trimmed;
  }
}
