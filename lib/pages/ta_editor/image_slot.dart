import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dna/widgets/fit_text.dart';

/// 角色编辑器中的单张图片上传槽（头像、背景图等）。
class ImageSlot extends StatelessWidget {
  const ImageSlot({super.key, required this.title, required this.path, required this.onTap});

  final String title;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: FitText(title)),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.upload_outlined),
          label: const FitText('上传'),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          height: 72,
          child: path == null || path!.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image_outlined),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(path!), fit: BoxFit.cover),
                ),
        ),
      ],
    );
  }
}
