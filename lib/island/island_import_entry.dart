import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_api.dart';
import 'island_card.dart';
import 'island_card_page.dart';

/// 「从岛导入」入口：粘贴卡片链接或 ID，取出卡片详情并打开卡片页。
///
/// 之所以先做这条"粘贴链接"的路而不是先做信息流：它足以把
/// **发现 → 试聊 → 导入** 这条链路跑通，而且不依赖登录（卡片详情是公开的）。
/// 信息流（探索/搜索/我的收藏）后续再接。
Future<void> openIslandCardImport(
  BuildContext context,
  AppController controller,
) async {
  final TextEditingController input = TextEditingController();
  final String? raw = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const FitText('从岛导入角色卡'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const FitText('粘贴卡片链接或卡片 ID。'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://…/cards/xxx 或 xxx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (String value) =>
                Navigator.of(dialogContext).pop(value),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const FitText('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(input.text),
          child: const FitText('打开'),
        ),
      ],
    ),
  );
  input.dispose();

  if (raw == null || raw.trim().isEmpty) {
    return;
  }
  final String? cardId = parseIslandCardId(raw);
  if (cardId == null) {
    if (context.mounted) {
      _toast(context, '看不出卡片 ID，请粘贴卡片链接或 ID');
    }
    return;
  }
  if (!context.mounted) {
    return;
  }

  final IslandApi api = IslandApi();
  try {
    final Map<String, dynamic> json = await api.cardDetail(cardId);
    final IslandCard card = IslandCard.fromJson(json);
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            IslandCardPage(controller: controller, card: card),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      _toast(context, '读取卡片失败：$e');
    }
  } finally {
    api.dispose();
  }
}

/// 从链接或纯 ID 里取出卡片 ID。
///
/// 认这几种：`.../cards/<id>`、`.../card/<id>`、以及裸 ID。
String? parseIslandCardId(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final Match? match = RegExp(
    r'/cards?/([A-Za-z0-9_-]+)',
  ).firstMatch(text);
  if (match != null) {
    return match.group(1);
  }
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text) ? text : null;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: FitText(message)));
}
