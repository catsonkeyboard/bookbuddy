import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/fairy_tale_catalog.dart';
import 'package:bookbuddy/models/style_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 画风目录与童话目录的数据一致性防护。
///
/// 背景：曾出现童话 recommendedStyle 指向不存在画风 id 的悬空引用，
/// 查找画风时抛 StateError 导致用户端红屏。本测试保证增删画风/童话时
/// 一旦出现悬空引用或分类漂移，测试立刻失败。
void main() {
  final styleIds = StyleCatalog.styles.map((s) => s.id).toSet();

  group('StyleCatalog 自身约束', () {
    test('画风 id 非空且不重复', () {
      expect(styleIds.length, StyleCatalog.styles.length);
      for (final style in StyleCatalog.styles) {
        expect(style.id.isNotEmpty, true, reason: '画风 ${style.name} 的 id 为空');
        expect(style.name.isNotEmpty, true, reason: '画风 ${style.id} 的 name 为空');
        expect(style.prefix.isNotEmpty, true,
            reason: '画风 ${style.id} 的提示词 prefix 为空');
        expect(style.negative.isNotEmpty, true,
            reason: '画风 ${style.id} 的 negative 为空');
      }
    });

    test('目录非空', () {
      expect(StyleCatalog.styles.isNotEmpty, true);
    });
  });

  group('FairyTaleCatalog 与 StyleCatalog 的引用一致性', () {
    test('每条童话的 recommendedStyle 都命中画风 id 集合', () {
      final dangling = <String>[];
      for (final tale in FairyTaleCatalog.tales) {
        if (!styleIds.contains(tale.recommendedStyle)) {
          dangling.add('${tale.title} -> ${tale.recommendedStyle}');
        }
      }
      expect(
        dangling,
        isEmpty,
        reason: '以下童话的推荐画风 id 在 StyleCatalog 中不存在（悬空引用）：$dangling',
      );
    });

    test('每条童话的 category 都在 FairyTaleCatalog.categories 内', () {
      final orphan = <String>[];
      for (final tale in FairyTaleCatalog.tales) {
        if (!FairyTaleCatalog.categories.contains(tale.category)) {
          orphan.add('${tale.title} -> ${tale.category}');
        }
      }
      expect(
        orphan,
        isEmpty,
        reason: '以下童话的分类不在筛选分类列表中：$orphan',
      );
    });

    test('童话必填字段非空', () {
      for (final tale in FairyTaleCatalog.tales) {
        expect(tale.title.isNotEmpty, true, reason: '存在空标题童话');
        expect(tale.category.isNotEmpty, true, reason: '${tale.title} 分类为空');
        expect(tale.recommendedStyle.isNotEmpty, true,
            reason: '${tale.title} 推荐画风为空');
        expect(tale.synopsis.isNotEmpty, true, reason: '${tale.title} 摘要为空');
        expect(tale.emoji.isNotEmpty, true, reason: '${tale.title} emoji 为空');
      }
    });

    test('童话标题不重复', () {
      final titles = FairyTaleCatalog.tales.map((t) => t.title).toList();
      expect(titles.toSet().length, titles.length,
          reason: '童话标题存在重复：$titles');
    });
  });

  group('StyleCatalog.byIdOrDefault 回落行为', () {
    test('null 回落默认画风（目录首个：水彩童话）', () {
      final style = StyleCatalog.byIdOrDefault(null);
      expect(style.id, StyleCatalog.styles.first.id);
      expect(style.id, 'watercolor');
      expect(style.name, '水彩童话');
    });

    test('不存在的 id 回落默认画风', () {
      final style = StyleCatalog.byIdOrDefault('不存在的id');
      expect(style.id, StyleCatalog.styles.first.id);
      expect(style.id, 'watercolor');
    });

    test('空字符串回落默认画风', () {
      final style = StyleCatalog.byIdOrDefault('');
      expect(style.id, StyleCatalog.styles.first.id);
    });

    test('真实 id 命中对应画风', () {
      final style = StyleCatalog.byIdOrDefault('guofeng');
      expect(style.id, 'guofeng');
      expect(style.name, '国风水墨');
    });

    test('目录中每个 id 都能命中自身', () {
      for (final expected in StyleCatalog.styles) {
        final actual = StyleCatalog.byIdOrDefault(expected.id);
        expect(actual.id, expected.id);
        expect(actual.name, expected.name);
      }
    });
  });

  group('存储默认值与画风目录的联动', () {
    test('PictureBook.fromJson 的默认 styleId 存在于画风目录', () {
      // book.dart 中 fromJson 缺 styleId 时回落 'watercolor'，
      // 该默认值必须真实存在于目录，否则旧书打开即悬空。
      final book = PictureBook.fromJson({'id': 'b1', 'title': '旧书'});
      expect(
        styleIds.contains(book.styleId),
        true,
        reason: 'PictureBook.fromJson 默认 styleId "${book.styleId}" 不在画风目录中',
      );
    });
  });
}
