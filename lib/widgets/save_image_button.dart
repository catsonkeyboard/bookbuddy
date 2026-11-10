import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_export_service.dart';

/// 单张原图导出入口，手机保存到相册，桌面使用系统文件保存窗口。
class SaveImageButton extends StatefulWidget {
  const SaveImageButton({
    super.key,
    required this.name,
    required this.label,
    required this.loadBytes,
    this.enabled = true,
    this.iconOnly = false,
    this.foregroundColor,
  });

  final String name;
  final String label;
  final Future<Uint8List> Function() loadBytes;
  final bool enabled;
  final bool iconOnly;
  final Color? foregroundColor;

  @override
  State<SaveImageButton> createState() => _SaveImageButtonState();
}

class _SaveImageButtonState extends State<SaveImageButton> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || !widget.enabled) return;
    final name = widget.name;
    final loadBytes = widget.loadBytes;
    setState(() => _saving = true);
    try {
      final bytes = await loadBytes();
      if (!mounted) return;
      final result = await ImageExportService().save(bytes, name: name);
      if (!mounted || result == ImageExportResult.cancelled) return;
      _showMessage(
        result == ImageExportResult.gallery ? '图片已保存到相册' : '图片已保存到所选位置',
      );
    } on ImageExportException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('图片保存失败，请确认图片仍存在且存储空间充足后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.enabled && !_saving ? _save : null;
    final icon = _saving
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.foregroundColor,
            ),
          )
        : const Icon(Icons.save_alt);
    if (widget.iconOnly) {
      return IconButton(
        tooltip: widget.label,
        onPressed: onPressed,
        icon: icon,
        color: widget.foregroundColor,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(widget.label),
    );
  }
}
