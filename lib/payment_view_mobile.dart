import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController controller;
  var loading = true;
  var finished = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            _detectFinalState(request.url);
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            _detectFinalState(url);
            setState(() => loading = true);
          },
          onPageFinished: (url) async {
            setState(() => loading = false);
            _detectFinalState(url);
            try {
              final body = await controller.runJavaScriptReturningResult(
                "document.body ? document.body.innerText : ''",
              );
              _detectFinalState('$body');
            } catch (_) {
              // Cross-origin pages can block body inspection. URL detection still works.
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _detectFinalState(String value) {
    if (finished || !isFinalPaymentSignal(value)) {
      return;
    }
    finished = true;
    widget.onPaymentFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
