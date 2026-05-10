import 'dart:io';

import 'package:flutter/material.dart';

import '../models/ta.dart';

class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.tas,
    this.size = 40,
    this.radius = 8,
  });

  final List<TA> tas;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // 在 build 开始时缓存 theme 数据
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color surfaceContainerHigh = colorScheme.surfaceContainerHigh;
    final Color surfaceContainerHighest = colorScheme.surfaceContainerHighest;
    final TextStyle? labelMedium = textTheme.labelMedium;

    final List<TA> picked = tas.take(4).toList();
    
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          color: surfaceContainerHighest,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double half = constraints.maxWidth / 2;
              
              Widget buildCell(TA ta) {
                final String? path = ta.images['square'];
                if (path != null && path.isNotEmpty) {
                  final File file = File(path);
                  if (file.existsSync()) {
                    return Image.file(
                      file,
                      fit: BoxFit.cover,
                      width: half,
                      height: half,
                      // 使用 cacheWidth 和 cacheHeight 限制图片解码大小
                      cacheWidth: half.toInt() * 2,
                      cacheHeight: half.toInt() * 2,
                    );
                  }
                }
                final String label = ta.name.isNotEmpty ? ta.name[0] : '?';
                return Container(
                  width: half,
                  height: half,
                  color: surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Text(label, style: labelMedium),
                );
              }

              if (picked.isEmpty) {
                return Container(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  color: surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Text('?', style: labelMedium),
                );
              }
              if (picked.length == 1) {
                return buildCell(picked.first);
              }

              // 预构建所有 cells
              final List<Widget> cells = <Widget>[
                for (int i = 0; i < picked.length; i++) buildCell(picked[i]),
              ];
              
              // 填充剩余空间
              while (cells.length < 4) {
                cells.add(Container(
                  width: half,
                  height: half,
                  color: surfaceContainerHigh,
                ));
              }
              
              return Wrap(
                spacing: 0,
                runSpacing: 0,
                children: <Widget>[
                  SizedBox(width: half, height: half, child: cells[0]),
                  SizedBox(width: half, height: half, child: cells[1]),
                  SizedBox(width: half, height: half, child: cells[2]),
                  SizedBox(width: half, height: half, child: cells[3]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
