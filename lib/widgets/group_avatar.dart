import 'dart:io';

import 'package:flutter/material.dart';

import '../models/role.dart';

class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.roles,
    this.size = 40,
    this.radius = 8,
  });

  final List<Role> roles;
  final double size;
  final double radius;

  ImageProvider? _avatarForRole(Role role) {
    final String? path = role.images['square'];
    if (path == null || path.isEmpty) {
      return null;
    }
    final File file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return FileImage(file);
  }

  @override
  Widget build(BuildContext context) {
    final List<Role> picked = roles.take(4).toList();
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double half = constraints.maxWidth / 2;
              Widget buildCell(Role role) {
                final ImageProvider? avatar = _avatarForRole(role);
                if (avatar != null) {
                  return Image(
                    image: avatar,
                    fit: BoxFit.cover,
                    width: half,
                    height: half,
                  );
                }
                final String label = role.name.isNotEmpty ? role.name[0] : '?';
                return Container(
                  width: half,
                  height: half,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Text(label, style: Theme.of(context).textTheme.labelMedium),
                );
              }

              if (picked.isEmpty) {
                return Container(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: Text('?', style: Theme.of(context).textTheme.labelMedium),
                );
              }
              if (picked.length == 1) {
                return buildCell(picked.first);
              }

              final List<Widget> cells = <Widget>[];
              for (int i = 0; i < picked.length; i++) {
                cells.add(buildCell(picked[i]));
              }
              while (cells.length < 4) {
                cells.add(Container(
                  width: half,
                  height: half,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
