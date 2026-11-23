/// 设置 → 自由剪图（配置驱动版）。
///
/// ## 为什么开关的 subtitle 是静态的
///
/// 改动前这条副标题按当前值在两句话之间切换（开：都放开；关：列槽位比例）。
/// 声明层的 subtitle 是常量，表达不了「按值换文案」；硬要保留就得把开关降级成
/// SettingAction，那样 `freeImageCrop` 就没有 key 了，写通道也就管不到它。
/// 取舍是：subtitle 固定写「放开」的结果，把「关着的时候锁定哪些比例」下沉到
/// hint —— 两句话都还在页面上，只是从互斥变为同时可见。
///
/// ## 为什么说明文字是动作项
///
/// 渲染器只把 hint 挂在某个字段下面，没有「分组级提示行」这种东西；
/// 与安全页的「不可用提示」同一个做法：一个不可搜索的动作项，builder 直接返回
/// SettingHint。
library;

import 'package:flutter/material.dart';

import '../../widgets/setting_section.dart';
import 'spec/settings_spec.dart';

const String _switchTitle = '自由剪图';
const String _switchSubtitle = '所有图片编辑器都不再限制比例';
const String _switchHint = '关闭时角色卡 1:1 / 16:9 / 9:16、TA 形象、社区头像按固定比例锁定。';

const String _ratioNoticeTitle = '服务端比例校验';
const String _ratioNoticeBody =
    '角色卡的形象槽位仍受服务端比例校验：剪成别的比例后，'
    '发布/保存时会被拒绝并提示所需比例。TA 形象与社区头像不受影响。';

const String _releasedCropTitle = '裁剪界面解锁';
const String _releasedCropBody =
    '开启后裁剪界面不再锁定比例，也不再出现比例菜单，可以自由拖拽裁剪框。';

/// 自由剪图页的完整声明。
///
/// 关闭所有裁剪比例限制（角色卡形象、TA 形象、社区头像都放开），
/// 由 `FreeImageCrop` 在裁剪入口直接读这份设置。
final FieldsEntry freeImageCropEntry = FieldsEntry(
  id: 'freeImageCrop',
  groupId: SettingsGroupId.dataSecurity,
  icon: Icons.crop_free,
  title: '自由剪图',
  subtitle: '所有图片编辑器的裁剪比例限制',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'freeImageCrop.ratio',
      icon: Icons.crop_free,
      title: '裁剪比例',
      description: '关闭时按各槽位的固定比例锁定。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'freeImageCrop.freeImageCrop',
          title: _switchTitle,
          subtitle: _switchSubtitle,
          hint: _switchHint,
          key: 'freeImageCrop',
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'freeImageCrop.notice',
      icon: Icons.info_outline,
      title: '说明',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'freeImageCrop.serverRatioNotice',
          title: _ratioNoticeTitle,
          searchable: false,
          builder: (BuildContext context, _) => SettingHint(
            _ratioNoticeBody,
            icon: Icons.warning_amber_rounded,
          ),
        ),
        SettingAction(
          id: 'freeImageCrop.releasedCropNotice',
          title: _releasedCropTitle,
          searchable: false,
          builder: (BuildContext context, _) =>
              SettingHint(_releasedCropBody, icon: Icons.crop_free),
        ),
      ],
    ),
  ],
);
