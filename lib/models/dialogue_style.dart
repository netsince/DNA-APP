class DialogueTurn {
  const DialogueTurn({required this.user, required this.assistant});

  final String user;
  final String assistant;

  DialogueTurn copyWith({String? user, String? assistant}) {
    return DialogueTurn(
      user: user ?? this.user,
      assistant: assistant ?? this.assistant,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'user': user,
      'assistant': assistant,
    };
  }

  static DialogueTurn fromJson(Map<String, dynamic> json) {
    return DialogueTurn(
      user: (json['user'] as String?) ?? '',
      assistant: (json['assistant'] as String?) ?? '',
    );
  }
}
