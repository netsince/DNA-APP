// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:dna/services/image_storage.dart';
import 'package:dna/widgets/fit_text.dart';

/// 角色编辑器中的单张图片上传槽（紧凑卡片形态，支持一行多列布局）。
///
/// [ref] 为图片引用（IO 平台为绝对路径，Web 平台为逻辑文件名），
/// 通过 [ImageStorage] 统一解析为可显示的 ImageProvider。
class ImageSlot extends StatelessWidget {
  const ImageSlot({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ref,
    required this.aspectRatio,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? ref;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ImageProvider? provider = ImageStorage.instance.providerForRef(ref);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: provider != null
                ? theme.colorScheme.primary.withOpacity(0.5)
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: provider == null
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        child: Center(
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: theme.colorScheme.outline,
                            size: 24,
                          ),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Image(image: provider, fit: BoxFit.cover),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            FitText(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            FitText(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
