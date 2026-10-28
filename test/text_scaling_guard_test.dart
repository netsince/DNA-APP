import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

///文字缩放的结构性约束（不启动 UI）。
///
/// ##规则
///
///应用层**只允许**用 `Text` / `Text.rich` / `FitText`渲染文字。它们会自动接
/// `MediaQuery.textScaler`；而 `RichText` / `TextPainter`这两个低层原语默认
/// `TextScaler.noScaling`，**必须由调用方自己传 scaler**。
///
///聊天正文曾经就是一条 `RichText`：字号设置改了首页、改不了对话正文。
///靠"每个调用点都记得传参数"是拦不住的（新人、复制粘贴、第三方都会漏），
///所以这里把它变成**写不出来**。
///
///唯一豁免：`fit_text.dart`用 `TextPainter` **测量**长宽（决定要不要缩字），
///不参与绘制；绘制依旧走 `Text`。新增豁免必须在这里写明理由。
void main() {
 const Set<String> kTextPainterAllowed = <String>{
 'lib/widgets/fit_text.dart',
 };

 List<File> libFiles() => Directory('lib')
 .listSync(recursive: true)
 .whereType<File>()
 .where((File f) => f.path.endsWith('.dart'))
 .toList();

 String norm(String p) => p.replaceAll('\\', '/');

 test('lib下不允许出现 RichText（一律用 Text.rich / FitText）', () {
 final List<String> offenders = <String>[];
 for (final File f in libFiles()) {
 for (final String line in f.readAsLinesSync()) {
 final String code = line.split('//').first;
 if (code.contains('RichText(')) {
 offenders.add('${norm(f.path)}: ${line.trim()}');
 }
 }
 }
 expect(
 offenders,
 isEmpty,
 reason: 'RichText不读 MediaQuery.textScaler，字号设置到不了它：\n${offenders.join('\n')}',
 );
 });

 test('TextPainter只允许在 fit_text.dart里做测量', () {
 final List<String> offenders = <String>[];
 for (final File f in libFiles()) {
 final String path = norm(f.path);
 if (kTextPainterAllowed.contains(path)) continue;
 for (final String line in f.readAsLinesSync()) {
 if (line.split('//').first.contains('TextPainter(')) {
 offenders.add('$path: ${line.trim()}');
 }
 }
 }
 expect(offenders, isEmpty, reason: '自绘文字必须走包装（否则不跟随字号）：\n${offenders.join('\n')}');
 });

 test('两处曾经的漏点已改成 Text.rich', () {
 final String chat =
 File('lib/pages/chat/ui/widgets/chat_message_list.dart').readAsStringSync();
 expect(chat.contains('Text.rich('), isTrue,
 reason: '聊天气泡正文必须用 Text.rich，否则字号设置到不了正文');

 final String sticker =
 File('lib/island_app/widgets/sticker_text.dart').readAsStringSync();
 expect(sticker.contains('Text.rich('), isTrue,
 reason: '社区贴纸文字同理');
 });
}
