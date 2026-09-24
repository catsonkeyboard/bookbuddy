import 'package:flutter/material.dart';
import '../models/fairy_tale_catalog.dart';
import 'create_book_screen.dart';

class TaleRecommendationDialog extends StatefulWidget {
  const TaleRecommendationDialog({super.key});

  @override
  State<TaleRecommendationDialog> createState() => _TaleRecommendationDialogState();
}

class _TaleRecommendationDialogState extends State<TaleRecommendationDialog> {
  String _selectedCategory = '全部热门';

  @override
  Widget build(BuildContext context) {
    final filteredTales = _selectedCategory == '全部热门'
        ? FairyTaleCatalog.tales
        : FairyTaleCatalog.tales.where((t) => t.category == _selectedCategory).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF1E1C18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Text('🌟', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 10),
                      Text(
                        '经典童话故事灵感库',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '挑选心仪的经典童话，一键直接带入标题、故事梗概与推荐画风开始生成',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // 分类切换标签
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: FairyTaleCatalog.categories.map((cat) {
                    final isSel = cat == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSel,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 故事卡片网格列表
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 110,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filteredTales.length,
                  itemBuilder: (ctx, i) {
                    final tale = filteredTales[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateBookScreen(
                              initialTitle: tale.title,
                              initialSynopsis: tale.synopsis,
                              initialStyleId: tale.recommendedStyle,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF26231E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF38332A)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF332D23),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(tale.emoji, style: const TextStyle(fontSize: 22)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tale.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD8A24A).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tale.category,
                                          style: const TextStyle(fontSize: 10, color: Color(0xFFD8A24A)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tale.synopsis,
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
