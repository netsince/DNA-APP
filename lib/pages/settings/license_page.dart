import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:dna/widgets/fit_text.dart';

/// 本项目许可证：源码许可证与美术资源许可证。
class _LicenseDoc {
  const _LicenseDoc({required this.title, required this.file});

  final String title;
  final String file;
}

const List<_LicenseDoc> _kLicenseDocs = <_LicenseDoc>[
  _LicenseDoc(title: '源代码许可证 (nSPPL)', file: 'LICENSE-nSPPL'),
  _LicenseDoc(title: '美术资源许可证 (CC BY-NC-ND 4.0)', file: 'LICENSE-CC'),
];

/// 许可证全文页：编译时将 LICENSE 文件随应用打包，运行时读取并展示全文。
class LicensePage extends StatefulWidget {
  const LicensePage({super.key});

  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  /// 各许可证的全文；加载完成前为 null。
  Map<String, String> _texts = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Map<String, String> map = <String, String>{};
    for (final doc in _kLicenseDocs) {
      try {
        map[doc.file] = await rootBundle.loadString(doc.file);
      } catch (_) {
        map[doc.file] = '（无法读取 $doc.file）';
      }
    }
    if (!mounted) return;
    setState(() => _texts = map);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _kLicenseDocs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const FitText('许可证'),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              for (final doc in _kLicenseDocs)
                Tab(child: FitText(doc.title)),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final doc in _kLicenseDocs) _buildDoc(doc),
          ],
        ),
      ),
    );
  }

  Widget _buildDoc(_LicenseDoc doc) {
    final String? text = _texts[doc.file];
    if (text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
    );
  }
}
