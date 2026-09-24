class FairyTaleItem {
  final String title;
  final String category; // '格林童话' | '安徒生童话' | '经典世界童话' | '中国经典童话'
  final String synopsis; // 简短故事摘要
  final String recommendedStyle; // 推荐画风 id
  final String emoji;

  const FairyTaleItem({
    required this.title,
    required this.category,
    required this.synopsis,
    required this.recommendedStyle,
    required this.emoji,
  });
}

class FairyTaleCatalog {
  static const List<String> categories = [
    '全部热门',
    '格林童话',
    '安徒生童话',
    '世界经典',
    '中国经典',
  ];

  static const List<FairyTaleItem> tales = [
    // --- 格林童话 ---
    FairyTaleItem(
      title: '小红帽的故事',
      category: '格林童话',
      synopsis: '乖巧的小姑娘探望生病外婆，遇到狡猾大灰狼，猎人机智解救。',
      recommendedStyle: 'watercolor',
      emoji: '🧺',
    ),
    FairyTaleItem(
      title: '白雪公主与七个小矮人',
      category: '格林童话',
      synopsis: '美丽纯洁的白雪公主避开恶毒王后，在森林小矮人家收获真挚友谊。',
      recommendedStyle: 'vintage-storybook',
      emoji: '🍎',
    ),
    FairyTaleItem(
      title: '灰姑娘',
      category: '格林童话',
      synopsis: '善良坚韧的辛德瑞拉在水晶鞋与南瓜马车的奇迹下迎来幸福。',
      recommendedStyle: 'watercolor',
      emoji: '👠',
    ),
    FairyTaleItem(
      title: '睡美人',
      category: '格林童话',
      synopsis: '中了沉睡诅咒的公主在被荆棘包围的古堡中，等待被真爱唤醒。',
      recommendedStyle: 'oil',
      emoji: '🌹',
    ),
    FairyTaleItem(
      title: '糖果屋历险记',
      category: '格林童话',
      synopsis: '汉赛尔与格莱特兄妹在森林深处遭遇奇幻的姜饼屋与女巫。',
      recommendedStyle: 'claymation',
      emoji: '🍭',
    ),
    FairyTaleItem(
      title: '不来梅的音乐家',
      category: '格林童话',
      synopsis: '驴、狗、猫和公鸡四个年迈动物伙伴齐心协力赶跑强盗。',
      recommendedStyle: 'woodcut',
      emoji: '🎵',
    ),
    FairyTaleItem(
      title: '青蛙王子',
      category: '格林童话',
      synopsis: '小公主守信履行承诺，被诅咒的青蛙最终蜕变为英俊的王子。',
      recommendedStyle: 'watercolor',
      emoji: '🐸',
    ),
    FairyTaleItem(
      title: '长发公主 (莴苣姑娘)',
      category: '格林童话',
      synopsis: '高塔上的金发女孩用闪亮的金色长发编织希望与勇气。',
      recommendedStyle: 'colored-pencil',
      emoji: '👱‍♀️',
    ),
    FairyTaleItem(
      title: '勇敢的小裁缝',
      category: '格林童话',
      synopsis: '“一打打七个”的小裁缝凭借智慧与勇气智斗巨人与独角兽。',
      recommendedStyle: 'crayon',
      emoji: '✂️',
    ),
    FairyTaleItem(
      title: '渔夫和他的妻子',
      category: '格林童话',
      synopsis: '神奇的金鱼与贪得无厌的愿望，寓教于乐的贪婪警示故事。',
      recommendedStyle: 'watercolor',
      emoji: '🐟',
    ),
    FairyTaleItem(
      title: '狼和七只小羊',
      category: '格林童话',
      synopsis: '机智的小羊藏在钟摆后，羊妈妈勇敢救出被吞肚里的小羊。',
      recommendedStyle: 'claymation',
      emoji: '🐑',
    ),
    FairyTaleItem(
      title: '金鹅',
      category: '格林童话',
      synopsis: '善良的傻瓜得到一只神奇金鹅，引来一连串粘在一起的搞笑故事。',
      recommendedStyle: 'vintage-storybook',
      emoji: '🪿',
    ),

    // --- 安徒生童话 ---
    FairyTaleItem(
      title: '丑小鸭',
      category: '安徒生童话',
      synopsis: '经历冷眼与磨难的笨拙灰色雏鸟，最终在春光中展翅化作白天鹅。',
      recommendedStyle: 'watercolor',
      emoji: '🦢',
    ),
    FairyTaleItem(
      title: '海的女儿',
      category: '安徒生童话',
      synopsis: '深海小美人鱼为了灵魂与真爱，勇敢化作浪花守护人间。',
      recommendedStyle: 'watercolor',
      emoji: '🧜‍♀️',
    ),
    FairyTaleItem(
      title: '卖火柴的小女孩',
      category: '安徒生童话',
      synopsis: '寒冷除夕夜的微弱火光中，闪烁着温暖、爱与慈祥祖母的笑脸。',
      recommendedStyle: 'oil',
      emoji: '🕯️',
    ),
    FairyTaleItem(
      title: '皇帝的新装',
      category: '安徒生童话',
      synopsis: '爱慕虚荣的皇帝与骗子裁缝，被天真孩子一句真话戳破谎言。',
      recommendedStyle: 'vintage-storybook',
      emoji: '👑',
    ),
    FairyTaleItem(
      title: '拇指姑娘',
      category: '安徒生童话',
      synopsis: '郁金香中诞生的娇小女孩历经波折，随燕子飞往光明花之王国。',
      recommendedStyle: 'colored-pencil',
      emoji: '🌷',
    ),
    FairyTaleItem(
      title: '坚定的锡兵',
      category: '安徒生童话',
      synopsis: '单腿锡兵在险象环生的人世间冒险，至死不渝守护跳舞小纸人。',
      recommendedStyle: 'vintage-storybook',
      emoji: '💂',
    ),
    FairyTaleItem(
      title: '豌豆公主',
      category: '安徒生童话',
      synopsis: '二十层鸭绒垫下的一颗小小豌豆，见证真正高贵娇嫩的公主。',
      recommendedStyle: 'colored-pencil',
      emoji: '🛏️',
    ),
    FairyTaleItem(
      title: '夜莺',
      category: '安徒生童话',
      synopsis: '真诚纯美的树林夜莺用美妙歌声战胜死神，抚慰病弱的君王。',
      recommendedStyle: 'guofeng',
      emoji: '🐦',
    ),
    FairyTaleItem(
      title: '野天鹅',
      category: '安徒生童话',
      synopsis: '坚毅的艾丽莎忍痛编织荨麻披肩，拯救被诅咒成天鹅的十一位哥哥。',
      recommendedStyle: 'watercolor',
      emoji: '🪶',
    ),
    FairyTaleItem(
      title: '冰雪女王',
      category: '安徒生童话',
      synopsis: '小格尔达凭借纯真的爱与无畏的勇气，融化加伊心中的冰屑。',
      recommendedStyle: 'watercolor',
      emoji: '❄️',
    ),

    // --- 世界经典童话 ---
    FairyTaleItem(
      title: '三只小猪',
      category: '世界经典',
      synopsis: '勤劳务实的小猪建造坚固的砖瓦房，巧妙智斗狂妄大灰狼。',
      recommendedStyle: 'claymation',
      emoji: '🐷',
    ),
    FairyTaleItem(
      title: '穿靴子的猫',
      category: '世界经典',
      synopsis: '智谋过人的神猫穿上长靴，帮助穷困主人逆袭成为卡拉巴斯侯爵。',
      recommendedStyle: 'vintage-storybook',
      emoji: '🐱',
    ),
    FairyTaleItem(
      title: '木偶奇遇记',
      category: '世界经典',
      synopsis: '说谎鼻子会长长的小木偶匹诺曹，历经磨难蜕变成诚实真正小男孩。',
      recommendedStyle: 'claymation',
      emoji: '🤥',
    ),
    FairyTaleItem(
      title: '杰克与豌豆',
      category: '世界经典',
      synopsis: '神奇魔豆直插云霄通往天空巨人的城堡，开启勇敢冒险。',
      recommendedStyle: 'watercolor',
      emoji: '🌱',
    ),
    FairyTaleItem(
      title: '美女与野兽',
      category: '世界经典',
      synopsis: '外表凶恶城堡主人的内心救赎，看透外表的真爱打破魔咒。',
      recommendedStyle: 'oil',
      emoji: '🥀',
    ),
    FairyTaleItem(
      title: '爱丽丝梦游仙境',
      category: '世界经典',
      synopsis: '追赶白兔跌入奇异树洞，进入红桃王后与疯帽子的奇幻魔法世界。',
      recommendedStyle: 'watercolor',
      emoji: '🐰',
    ),
    FairyTaleItem(
      title: '绿野仙踪',
      category: '世界经典',
      synopsis: '桃乐丝与稻草人、铁皮人、胆小狮在黄砖路上寻觅智慧、真心与勇气。',
      recommendedStyle: 'anime',
      emoji: '🌪️',
    ),
    FairyTaleItem(
      title: '小飞侠彼得·潘',
      category: '世界经典',
      synopsis: '永远不想长大的少年彼得·潘带领温迪飞往永无岛，与虎克船长斗智。',
      recommendedStyle: 'anime',
      emoji: '🧚‍♂️',
    ),
    FairyTaleItem(
      title: '小王子',
      category: '世界经典',
      synopsis: '来自 B612 小行星的纯洁王子，关于玫瑰、狐狸与驯养的永恒童话。',
      recommendedStyle: 'watercolor',
      emoji: '🪐',
    ),
    FairyTaleItem(
      title: '阿拉丁神灯',
      category: '世界经典',
      synopsis: '摩擦神灯唤醒法力无边的巨灵，贫穷少年战胜邪恶魔法师。',
      recommendedStyle: 'guofeng',
      emoji: '🪔',
    ),
    FairyTaleItem(
      title: '拔萝卜',
      category: '世界经典',
      synopsis: '老爷爷、老奶奶、小姑娘和小动物们齐心协力拔出巨型大萝卜。',
      recommendedStyle: 'crayon',
      emoji: '🥕',
    ),
    FairyTaleItem(
      title: '姜饼人历险记',
      category: '世界经典',
      synopsis: '“跑跑跑，谁也追不上我！”从烤炉跳出狂奔的俏皮姜饼小人。',
      recommendedStyle: 'claymation',
      emoji: '🍪',
    ),

    // --- 中国经典民间童话 ---
    FairyTaleItem(
      title: '神笔马良',
      category: '中国经典',
      synopsis: '勤劳善良的马良得到神笔画物成真，为穷人造福惩治贪婪官吏。',
      recommendedStyle: 'guofeng',
      emoji: '🖌️',
    ),
    FairyTaleItem(
      title: '九色鹿',
      category: '中国经典',
      synopsis: '敦煌壁画传奇：善良美丽的九色鹿救人于危难，以德报怨的大爱故事。',
      recommendedStyle: 'guofeng',
      emoji: '🦌',
    ),
    FairyTaleItem(
      title: '宝莲灯 (沉香劈山救母)',
      category: '中国经典',
      synopsis: '少年沉香历经千难万险拜师学艺，手持宝莲灯勇劈华山救出母亲。',
      recommendedStyle: 'guofeng',
      emoji: '🏮',
    ),
    FairyTaleItem(
      title: '小蝌蚪找妈妈',
      category: '中国经典',
      synopsis: '水墨童年回忆：池塘里的小蝌蚪询问鸭子、大鱼，终于找到青蛙妈妈。',
      recommendedStyle: 'guofeng',
      emoji: '🐸',
    ),
    FairyTaleItem(
      title: '大闹天宫 (齐天大圣)',
      category: '中国经典',
      synopsis: '花果山美猴王孙悟空腾云驾雾、金箍棒挥洒自如的神奇神话篇章。',
      recommendedStyle: 'guofeng',
      emoji: '🐒',
    ),
    FairyTaleItem(
      title: '老鼠嫁女',
      category: '中国经典',
      synopsis: '传统生肖幽默民俗：鼠老爹为女儿挑选世上最强者当新郎的欢喜趣事。',
      recommendedStyle: 'crayon',
      emoji: '🐭',
    ),
  ];
}
