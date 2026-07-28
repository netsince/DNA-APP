import 'package:flutter/material.dart';

import '../../models/ta.dart';
import '../../services/conversation_export_import_service.dart';

/// 导入对话时，处理缺失/重名的角色卡。返回角色决议列表（取消时为 null）。
Future<List<CharacterImportDecision>?> showCharacterResolutionDialog({
  required BuildContext context,
  required List<NeededCharacter> needed,
  required List<TA> existingTas,
}) async {
  final modeById = <String, String>{};
  final assignById = <String, String>{};
  for (final n in needed) {
    modeById[n.originalTaId] = n.hasCard ? 'create' : 'link';
    assignById[n.originalTaId] = '';
  }
  return showDialog<List<CharacterImportDecision>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('匹配角色'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: StatefulBuilder(
            builder: (bc, setSB) => ListView(
              children: needed.map((n) {
                final name = n.cardName ?? n.originalTaId;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    RadioGroup<String>(
                      groupValue: modeById[n.originalTaId]!,
                      onChanged: (v) => setSB(() => modeById[n.originalTaId] = v!),
                      child: Column(
                        children: <Widget>[
                          RadioListTile<String>(
                            title: const Text('新建角色卡'),
                            value: 'create',
                          ),
                          RadioListTile<String>(
                            title: const Text('关联到已有角色'),
                            value: 'link',
                          ),
                        ],
                      ),
                    ),
                    if (modeById[n.originalTaId] == 'link')
                      InputDecorator(
                        decoration: const InputDecoration(labelText: '选择角色'),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: assignById[n.originalTaId]!.isEmpty && existingTas.isNotEmpty
                              ? existingTas.first.id
                              : assignById[n.originalTaId],
                          items: existingTas
                              .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                              .toList(),
                          onChanged: (v) => setSB(() => assignById[n.originalTaId] = v!),
                        ),
                      ),
                    const Divider(),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final out = <CharacterImportDecision>[];
              for (final n in needed) {
                final bool importAsNew = modeById[n.originalTaId] == 'create';
                out.add(
                  CharacterImportDecision(
                    originalTaId: n.originalTaId,
                    importAsNew: importAsNew,
                    existingTaId: importAsNew
                        ? null
                        : (assignById[n.originalTaId]!.isEmpty && existingTas.isNotEmpty
                            ? existingTas.first.id
                            : assignById[n.originalTaId]),
                  ),
                );
              }
              Navigator.pop(ctx, out);
            },
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
}
