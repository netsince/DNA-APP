import 'dart:io';

import 'package:dna/models/app_settings.dart';
import 'package:dna/widgets/model_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「模型列表不限高」设置项 + [ModelPicker] 高度策略的契约。
///
/// 默认行为是**限高 240 内部滚动**（模型插件在页面里只占一小块）；
/// 打开设置后不再封顶，列表高度由模型数量决定、整页滚动。
ModelPicker _picker({
  required List<String> models,
  bool unbounded = false,
  bool fill = false,
}) =>
    ModelPicker(
      models: models,
      selectedModel: models.isEmpty ? null : models.first,
      loading: false,
      onReload: () {},
      onSelect: (_) {},
      onCustom: () {},
      fill: fill,
      unbounded: unbounded,
    );

List<String> _models(int n) =>
    List<String>.generate(n, (int i) => 'model-$i');

void main() {
  group('设置项 unboundedModelList', () {
    test('默认关闭（列表限高，不把下面内容顶出屏幕）', () {
      expect(AppSettings.empty().unboundedModelList, isFalse);
    });

    test('copyWith 可开启', () {
      expect(
        AppSettings.empty().copyWith(unboundedModelList: true).unboundedModelList,
        isTrue,
      );
    });

    test('toJson / fromJson 往返一致', () {
      final AppSettings s =
          AppSettings.empty().copyWith(unboundedModelList: true);
      expect(AppSettings.fromJson(s.toJson()).unboundedModelList, isTrue);
    });

    test('缺失字段回退默认 false（旧备份恢复不报错）', () {
      final Map<String, dynamic> json = AppSettings.empty().toJson();
      json.remove('unboundedModelList');
      expect(AppSettings.fromJson(json).unboundedModelList, isFalse);
    });
  });

  group('ModelPicker 高度策略', () {
    /// 把组件放进"本身可滚动"的页面里 —— 与设置页的真实用法一致。
    Future<void> pumpPicker(WidgetTester tester, ModelPicker picker) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: picker),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认：模型很多也限高在 240', (WidgetTester tester) async {
      await pumpPicker(tester, _picker(models: _models(30)));
      final double height = tester.getSize(find.byType(ListView)).height;
      expect(height, kModelListInlineMaxHeight);
    });

    testWidgets('不限高：列表高度随模型数量变长（超过 240）', (WidgetTester tester) async {
      await pumpPicker(tester, _picker(models: _models(30), unbounded: true));
      final double height = tester.getSize(find.byType(ListView)).height;
      expect(height, greaterThan(kModelListInlineMaxHeight));
    });

    testWidgets('不限高：模型少时不吃到 240（高度由内容决定）', (WidgetTester tester) async {
      await pumpPicker(tester, _picker(models: _models(2), unbounded: true));
      final double height = tester.getSize(find.byType(ListView)).height;
      expect(height, lessThan(kModelListInlineMaxHeight));
    });

    testWidgets('fill: true 时 unbounded 不参与（仍撑满父级）', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Expanded(
                  child: _picker(models: _models(30), unbounded: true, fill: true),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('结构约束', () {
    test('精简模式把开关值真的传给了 ModelPicker', () {
      final String src =
          File('lib/pages/settings/ai_service/simple_view.dart')
              .readAsStringSync();
      expect(src.contains('unbounded:'), isTrue);
    });

    test('开关住在「界面模式」分区，不在模型列表旁边', () {
      final String more =
          File('lib/pages/settings/ai_service_more_page.dart')
              .readAsStringSync();
      expect(more.contains('模型列表不限高'), isTrue);
      expect(more.contains('saveUnboundedModelList'), isTrue);

      // 反证：模型选择区里不该再出现这个开关的文案与写入调用。
      final String simple =
          File('lib/pages/settings/ai_service/simple_view.dart')
              .readAsStringSync();
      expect(simple.contains('模型列表不限高'), isFalse,
          reason: '开关已挪到「界面模式」，不要在模型列表里再出现一份');
    });
  });
}
