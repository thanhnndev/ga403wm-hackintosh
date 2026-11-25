// SPDX-License-Identifier: BSD-3-Clause-Clear
// FlutterBench: a scrolling list + animated cards; prints one FLUTTERBENCH line per second from FrameTiming
// (frames = fps, build/raster p50 ms; total_max = worst vsync-to-raster-done span; slow counts totalSpan > 16.7 ms,
// which in debug builds includes the vsync wait, so read fps and build/raster instead). Copied into lib/main.dart of a `flutter create` app.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const marker = 'v1'; // run.sh edits this for the hot-reload test

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final timings = <FrameTiming>[];
  var second = 0;
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  Stream.periodic(const Duration(seconds: 1)).listen((_) {
    second++;
    if (timings.isEmpty) { debugPrint('FLUTTERBENCH t=$second frames=0'); return; }
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
    final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
    final total = timings.map((t) => ms(t.totalSpan)).toList()..sort();
    final slow = total.where((v) => v > 16.7).length;
    debugPrint('FLUTTERBENCH t=$second frames=${timings.length} build_p50=${build[build.length ~/ 2].toStringAsFixed(2)} '
        'raster_p50=${raster[raster.length ~/ 2].toStringAsFixed(2)} raster_max=${raster.last.toStringAsFixed(2)} '
        'total_max=${total.last.toStringAsFixed(2)} slow=$slow marker=$marker');
    timings.clear();
  });
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Bench()));
}

class Bench extends StatefulWidget {
  const Bench({super.key});
  @override
  State<Bench> createState() => _BenchState();
}

class _BenchState extends State<Bench> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scroll(true));
  }
  void _scroll(bool down) {
    if (!mounted || !scroll.hasClients) return;
    scroll.animateTo(down ? scroll.position.maxScrollExtent : 0, duration: const Duration(seconds: 4), curve: Curves.easeInOut)
        .then((_) => _scroll(!down));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('FlutterBench $marker')),
        body: ListView.builder(
          controller: scroll,
          itemCount: 400,
          itemBuilder: (_, i) => AnimatedBuilder(
            animation: c,
            builder: (_, __) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: HSVColor.fromAHSV(1, (i * 23 + c.value * 360) % 360, 0.35, 0.95).toColor(),
              child: ListTile(
                leading: Transform.rotate(angle: c.value * 2 * pi, child: const Icon(Icons.blur_on, size: 36)),
                title: Text('Row $i'),
                subtitle: LinearProgressIndicator(value: (c.value + i / 40) % 1),
              ),
            ),
          ),
        ),
      );
}
