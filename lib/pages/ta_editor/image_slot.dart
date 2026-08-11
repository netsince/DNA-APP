import 'package:flutter/material.dart';
import 'package:dna/services/image_storage.dart';
import 'package:dna/widgets/fit_text.dart';

/// 角色编辑器中的单张图片上传槽（头像、背景图等）。
///
/// [ref] 为图片引用（IO 平台为绝对路径，Web 平台为逻辑文件名），
/// 通过 [ImageStorage] 统一解析为可显示的 ImageProvider，跨平台一致。
class ImageSlot extends StatelessWidget {
  const ImageSlot({super.key, required this.title, required this.ref, required this.onTap});

  final String title;
  final String? ref;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? provider = ImageStorage.instance.providerForRef(ref);
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
          child: provider == null
              ? Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image_outlined),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(image: provider, fit: BoxFit.cover),
                ),
        ),
      ],
    );
  }
}
