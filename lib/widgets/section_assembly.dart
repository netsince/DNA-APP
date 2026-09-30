import 'package:dna/pages/group_home_page.dart';
import 'package:dna/pages/home_page.dart';
import 'package:dna/pages/identity_page.dart';
import 'package:dna/island/island_section.dart';
import 'package:dna/pages/my_home_page.dart';
import 'package:dna/pages/settings_page.dart';
import 'package:dna/pages/world_page.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/app_section.dart';

/// 七个栏目的装配表:按抽屉顺序排列。
///
/// 每个栏目页文件提供一个 `xxSection(controller)` 工厂,
/// 返回该栏目的标题栏/内容区/悬浮按钮与共享状态(归档开关)。
/// 壳([AppSectionShell])在 initState 里调用一次,
/// 之后工厂闭包里的状态(归档开关、滚动位置)随壳常驻。
List<SectionPageData> sectionAssembly(AppController controller) =>
    <SectionPageData>[
      homeSection(controller),
      groupHomeSection(controller),
      myHomeSection(controller),
      islandSection(controller),
      identitySection(controller),
      worldSection(controller),
      settingsSection(controller),
    ];
