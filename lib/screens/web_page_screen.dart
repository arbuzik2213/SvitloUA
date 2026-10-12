import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../sources/dtek_bridge.dart';
import '../theme.dart';
import '../widgets/pressable.dart';

/// Офіційна сторінка обленерго всередині застосунку.
Future<void> openOfficialPage(
    BuildContext context, String title, String url) async {
  if (!DtekBridge.supported) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => WebPageScreen(title: title, url: url)),
  );
}

class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(children: [
              Pressable(
                onTap: () async {
                  if (await _controller.canGoBack()) {
                    await _controller.goBack();
                  } else if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(CupertinoIcons.back, color: p.ink, size: 22),
                ),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: body(15.5, weight: FontWeight.w600, color: p.ink),
                ),
              ),
              Pressable(
                onTap: () => launchUrl(
                  Uri.parse(widget.url),
                  mode: LaunchMode.externalApplication,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(CupertinoIcons.compass, color: p.ink, size: 22),
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 2,
            child: _progress < 100
                ? LinearProgressIndicator(
                    value: _progress / 100,
                    backgroundColor: Colors.transparent,
                    color: p.light,
                  )
                : null,
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ]),
      ),
    );
  }
}
