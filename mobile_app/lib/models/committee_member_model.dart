// lib/models/committee_member_model.dart

enum CommitteeType { garc, ipdc, krrc }

extension CommitteeTypeExt on CommitteeType {
  String get label {
    switch (this) {
      case CommitteeType.garc: return 'GARC';
      case CommitteeType.ipdc: return 'IPDC';
      case CommitteeType.krrc: return 'KRRC';
    }
  }

  String get fullName {
    switch (this) {
      case CommitteeType.garc: return 'Grievance & Appeal Redressal Center';
      case CommitteeType.ipdc: return 'Infrastructure Planning & Development Centre';
      case CommitteeType.krrc: return 'Knowledge Resources & Relay Centre';
    }
  }

  List<String> get categories {
    switch (this) {
      case CommitteeType.garc: return ['academic', 'administrative', 'safety', 'other'];
      case CommitteeType.ipdc: return ['infrastructure'];
      case CommitteeType.krrc: return ['library'];
    }
  }
}

class CommitteeMember {
  final String email;
  final String name;
  final CommitteeType committee;
  final String designation;

  const CommitteeMember({
    required this.email,
    required this.name,
    required this.committee,
    required this.designation,
  });

  factory CommitteeMember.fromFirestore(Map<String, dynamic> data) {
    return CommitteeMember(
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      committee: CommitteeType.values.firstWhere(
        (c) => c.label == data['committee'],
        orElse: () => CommitteeType.garc,
      ),
      designation: data['designation'] ?? 'Member',
    );
  }

  Map<String, dynamic> toMap() => {
    'email': email,
    'name': name,
    'committee': committee.label,
    'designation': designation,
  };
}
