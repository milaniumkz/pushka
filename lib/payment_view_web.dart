import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'payment_status_detector.dart';

class PushkaPaymentView extends StatefulWidget {
  const PushkaPaymentView({
    required this.url,
    this.onPaymentFinished,
    super.key,
  });

  final String url;
  final VoidCallback? onPaymentFinished;

  @override
  State<PushkaPaymentView> createState() => _PushkaPaymentViewState();
}

class _PushkaPaymentViewState extends State<PushkaPaymentView> {
  late final String viewType;
  var finished = false;

  @override
  void initState() {
    super.initState();
    viewType = 'pushka-payment-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = widget.url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      frame.setAttribute('allow', 'payment *; clipboard-read; clipboard-write');
      frame.onLoad.listen((_) {
        final value = frame.src;
        if (!finished && isFinalPaymentSignal(value)) {
          finished = true;
          widget.onPaymentFinished?.call();
        }
      });
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewType);
  }
}
