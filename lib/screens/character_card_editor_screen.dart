import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';

class CharacterCardEditorScreen extends StatefulWidget {
  final CharacterCard? card;
  final CharacterStorageService? storage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const CharacterCardEditorScreen({
    super.key,
    this.card,
    this.storage,
    this.engine,
    this.loadSettings,
  });

  @override
  State<CharacterCardEditorScreen> createState() =>
      _CharacterCardEditorScreenState();
}

class _CharacterCardEditorScreenState extends State<CharacterCardEditorScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.card == null ? '新建角色' : '编辑角色')),
      body: const Center(child: Text('编辑页将在下一任务实现')),
    );
  }
}
