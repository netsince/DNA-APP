import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 设置页信息设计的结构约束(静态检查,不启动 UI)。
///
/// 保护 `SETTINGS_AUDIT.md` 定下的四条规矩,防止回潮:
/// 1. 禁止手写 `Card > Padding > Column` 样板,一律用 `SettingSection`;
/// 2. 提示文案不超过 20 字(长说明必须下沉到 helper / SettingHint);
/// 3. 每个 `SettingSection` 必须带图标;
/// 4. 数值类设置项用折叠组件,不再平铺输入框。
void main() {
  /// 设置页目录下的所有 .dart 文件。
  List<File> settingsFiles() => Directory('lib/pages/settings')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();

  /// **豁免名单:表单编辑页**。
  ///
  /// 这些页面是 `Form` + `validate()` + 保存回写的**录入表单**,
  /// 不是"设置项堆叠"。表单的 `TextFormField` 依赖 label / helperText /
  /// errorText 的语义,套 `SettingSection` 会破坏填写节奏,且折叠态
  /// 无法承载校验错误。故允许它们保留手写卡片。
  ///
  /// 新增豁免必须在此登记并写明理由 —— 不要为了让测试变绿而扩大名单。
  const Set<String> kFormPageExemptions = <String>{
    'provider_edit_page.dart',
    'about_page.dart', // 展示页(版本/链接/许可证),无设置项
  };

  bool isExempt(File f) =>
      kFormPageExemptions.any((String e) => f.path.endsWith(e));

  group('设置页信息设计', () {
    test('设置页不再出现手写卡片样板', () {
      final List<String> offenders = <String>[];
      for (final File f in settingsFiles()) {
        if (isExempt(f)) continue;
        final String c = f.readAsStringSync();
        final int n = RegExp(r'Card\(\s*\r?\n\s*child:\s*Padding\(')
            .allMatches(c)
            .length;
        if (n > 0) offenders.add('${f.path}: $n 处');
      }
      expect(offenders, isEmpty,
          reason: '应使用 SettingSection 组件:\n${offenders.join('\n')}');
    });

    test('豁免名单不得无序扩大', () {
      expect(kFormPageExemptions.length, lessThanOrEqualTo(3),
          reason: '豁免页面过多说明组件推广不彻底,应重新评估 SettingSection 是否够用');
    });

    test('提示文案不超过 20 个中文字符', () {
      final List<String> offenders = <String>[];
      final RegExp re =
          RegExp("(?:subtitle|description):\\s*(?:const\\s*)?(?:FitText\\(\\s*)?'([^']{21,})'");
      for (final File f in settingsFiles()) {
        for (final RegExpMatch m in re.allMatches(f.readAsStringSync())) {
          final String t = m.group(1)!;
          // 跳过插值字符串(长度由运行时值决定)与纯 ASCII 宏名说明。
          if (t.contains(r'${')) continue;
          final int cjk =
              RegExp(r'[\u4e00-\u9fa5]').allMatches(t).length;
          if (cjk > 20) offenders.add('${f.path}: [$cjk 字] $t');
        }
      }
      expect(offenders, isEmpty,
          reason: '长说明应下沉到 helper 或 SettingHint:\n${offenders.join('\n')}');
    });

    test('每个 SettingSection 都带图标', () {
      final List<String> offenders = <String>[];
      for (final File f in settingsFiles()) {
        final String c = f.readAsStringSync();
        // 匹配每个 SettingSection( ... ) 的参数块,检查是否含 icon:。
        for (final RegExpMatch m
            in RegExp(r'SettingSection\(\s*([\s\S]*?)\n\s*children:')
                .allMatches(c)) {
          if (!m.group(1)!.contains('icon:')) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '分组标题必须带图标以建立层级:\n${offenders.join('\n')}');
    });

    test('数值设置项使用折叠组件,不再平铺输入框', () {
      final String src =
          File('lib/widgets/setting_collapsible.dart').readAsStringSync();
      // 折叠组件族必须齐备(整型 / 文本 / 浮点)。
      expect(src.contains('class CollapsibleNumberSetting'), isTrue);
      expect(src.contains('class CollapsibleTextSetting'), isTrue);
      expect(src.contains('class CollapsibleDoubleSetting'), isTrue);

      // 折叠组件必须在业务里被真正用起来。
      int used = 0;
      for (final File f in settingsFiles()) {
        final String c = f.readAsStringSync();
        used += RegExp(r'Collapsible\w+Setting\(').allMatches(c).length;
      }
      expect(used, greaterThan(20),
          reason: '折叠组件仅被使用 $used 次,推广不彻底');
    });

    test('收起态必须显示当前值(而非留空)', () {
      final String src =
          File('lib/widgets/setting_collapsible.dart').readAsStringSync();
      // 三个组件都应有 displayValue 概念。
      final int n = RegExp(r'_displayValue').allMatches(src).length;
      expect(n, greaterThanOrEqualTo(6),
          reason: '收起态显示当前值是折叠组件的核心契约');
    });

    test('禁止合成加粗与手写行高(设置页内)', () {
      final List<String> offenders = <String>[];
      for (final File f in settingsFiles()) {
        final String c = f.readAsStringSync();
        for (final String bad in <String>[
          'FontWeight.bold',
          'FontWeight.w600',
          'FontWeight.w700',
        ]) {
          if (c.contains(bad)) offenders.add('${f.path}: $bad');
        }
        if (RegExp(r'height:\s*1\.\d+').hasMatch(c)) {
          offenders.add('${f.path}: 手写 height');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
