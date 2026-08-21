import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

// 他メンバーのファイルをインポート
import 'yolo.dart';
import 'sensor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '計測アプリ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MeasurementScreen(),
    );
  }
}

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SensorService _sensorService = SensorService();
  final YoloService _yoloService = YoloService(); // YOLOサービスを追加

  // 警告状態・アニメーション管理
  bool _isWarning = false;
  bool _isRedBackground = true;
  Timer? _blinkTimer;

  // センサー・AI判定用フラグ
  double _currentY = 0.0;
  bool _isStopSignDetected = false; // YOLOからの検出フラグ
  bool _isNotBraking = false;        // 減速なしフラグ

  @override
  void initState() {
    super.initState();
    // Aさんのセンサーを裏で監視スタート
    _sensorService.startListening((x, y, z) {
      _onSensorUpdated(x, y, z);
    });

  // 2. YOLO検知のスタート
    _yoloService.startDetection((isDetected) {
      if (mounted) {
        setState(() {
          _isStopSignDetected = isDetected; // 検知フラグ更新
        });
        _checkAndTriggerWarning(); // 条件確認
      }
    });
  }

  // 1. 加速度の更新時に呼ばれる処理
  void _onSensorUpdated(double x, double y, double z) {
    const double brakingThreshold = -2.0; // 減速判定の閾値

    if (mounted) {
      setState(() {
        _currentY = y;
        _isNotBraking = y > brakingThreshold;
      });
    }

    // 2つの条件をチェックして自動で警告を発動
    _checkAndTriggerWarning();
  }

  // 2. 2つの条件が揃ったか確認する関数
  void _checkAndTriggerWarning() {
    if (_isStopSignDetected && _isNotBraking && !_isWarning) {
      _triggerWarning(); // 点滅＆警告音を発動
    }
  }

  // 3. 警告発動処理
  Future<void> _triggerWarning() async {
    _blinkTimer?.cancel();

    setState(() {
      _isWarning = true;
      _isRedBackground = true;
    });

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('alarm.mp3'));
    } catch (e) {
      debugPrint('音声再生エラー: $e');
    }

    // 点滅処理 (250ms周期)
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      setState(() {
        _isRedBackground = !_isRedBackground;
      });
    });

    // 3秒後に自動終了
    Timer(const Duration(seconds: 3), () {
      _resetWarning();
    });
  }

  void _resetWarning() {
    _blinkTimer?.cancel();
    if (mounted) {
      setState(() {
        _isWarning = false;
      });
    }
  }

  @override
  void dispose() {
    _yoloService.stopDetection(); // カメラ停止
    _sensorService.stopListening();
    _blinkTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = _isWarning
        ? (_isRedBackground ? Colors.red : Colors.yellow)
        : Colors.black;

    final Color textColor = _isWarning ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('計測アプリ'),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  _isWarning ? '止\nま\nれ' : '計\n測\n中',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            // センサーと検知結果のステータス表示
            Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Column(
                children: [
                  Text(
                    'Y軸: ${_currentY.toStringAsFixed(2)} | 減速なし: $_isNotBraking',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isStopSignDetected ? '標識検知: あり' : '標識検知: なし',
                      style: TextStyle(
                        fontSize: 16,
                        color: _isStopSignDetected ? Colors.redAccent : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
