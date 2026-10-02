import 'package:flutter/material.dart';

/// 再次调用模型（重画定妆照、重新识别照片）之前的确认，防止误触后又生成一次。
/// 只有点了确认按钮才返回 true；取消、点对话框外、返回键都算否。
Future<bool> confirmRegenerate(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '重新生成',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
