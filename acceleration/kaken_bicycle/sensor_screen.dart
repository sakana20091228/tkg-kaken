import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '加速度の値',
      theme: ThemeData.dark(),
      home: const AccelerometerScreen(),
    );
  }
}

class AccelerometerScreen extends StatefulWidget {
  const AccelerometerScreen({super.key});

  @override
  State<AccelerometerScreen> createState() => _AccelerometerScreenState();
}

class _AccelerometerScreenState extends State<AccelerometerScreen> {
  // 加速度の値 (X, Y, Z)
  double aX = 0.0;
  double aY = 0.0;
  double aZ = 0.0;

  // センサーのイベント購読用サブスクリプション
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;

  @override
  void initState() {
    super.initState();
    // JSの window.addEventListener('devicemotion', ...) に相当する処理
    // userAccelerometerEventStream は重力を除いた純粋な移動加速度を取得できます
    _accelSubscription = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        setState(() {
          aX = event.x;
          aY = event.y;
          aZ = event.z;
        });
      },
      onError: (error) {
        debugPrint('センサーエラー: $error');
      },
    );
  }

  @override
  void dispose() {
    // 画面破棄時にセンサーの読み取りを停止
    _accelSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('加速度の値'),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'X: ${aX.toStringAsFixed(2)}\n'
            'Y: ${aY.toStringAsFixed(2)}\n'
            'Z: ${aZ.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 24,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
