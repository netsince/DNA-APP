import 'package:dna/models/prompt_strategy.dart';
import 'package:dna/pages/chat/chat_system_prompt.dart';

void main() {
  final PromptStrategy base = PromptStrategy.defaults();
  print('=== defaults ===');
  print(ChatSystemPrompt.previewStrategy(base));
  print('');
  print('=== 电影感预设 ===');
  print(ChatSystemPrompt.previewStrategy(base.applyPreset(StrategyPreset.cinematic)));
  print('');
  print('=== 悬疑本预设 ===');
  print(ChatSystemPrompt.previewStrategy(base.applyPreset(StrategyPreset.mystery)));
}
