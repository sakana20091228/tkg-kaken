import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.camera.request();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('カメラ取得失敗: $e');
  }
  
  try {
    OrtEnv.instance.init();
  } catch (e) {
    debugPrint('OrtEnv 初期化エラー: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOLO 標識検知アプリ',
      theme: ThemeData.dark(),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  OrtSession? session;
  bool isDetecting = false;
  int frameCounter = 0;
  String statusMessage = 'モデルロード中...';
  
  List<List<double>> recognitions = [];
  final List<String> labels = ['一時停止', '最高速度', '車両通行止め', '歩行者専用', '指定方向外進行禁止'];

  @override
  void initState() {
    super.initState();
    initModelAndCamera();
  }

  Future<void> initModelAndCamera() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final targetFile = File('${appDocDir.path}/best.onnx');

      // 常に新しいモデルをアセットから書き出す
      final byteData = await rootBundle.load('assets/best.onnx');
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      await targetFile.writeAsBytes(bytes, flush: true);

      final sessionOptions = OrtSessionOptions();
      // Androidのハードウェア加速(NNAPI)を試みる

      session = OrtSession.fromFile(targetFile, sessionOptions);
      
      setState(() {
        statusMessage = 'AI推論準備完了 (標識にかざしてください)';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'モデルエラー: $e';
      });
    }

    if (cameras.isEmpty) return;
    controller = CameraController(
      cameras[0],
      ResolutionPreset.low,
      enableAudio: false,
    );

    await controller?.initialize();
    if (!mounted) return;

    controller?.startImageStream((CameraImage image) {
      // 3フレームに1回処理（描画を最優先にする）
      frameCounter++;
      if (frameCounter % 3 != 0) return;

      if (isDetecting || session == null) return;
      isDetecting = true;
      processImageAndRunInference(image);
    });

    setState(() {});
  }

  Future<void> processImageAndRunInference(CameraImage image) async {
    try {
      // YUV420から簡易RGB変換
      final convertedImage = convertYUV420ToRGB(image);
      
      // 320x320に高速リサイズ
      final resizedImage = img.copyResize(
        convertedImage, 
        width: 320, 
        height: 320,
        interpolation: img.Interpolation.nearest,
      );

      // 320x320x3 の Float32List
      final inputBytes = Float32List(1 * 3 * 320 * 320);
      int pixelIndex = 0;
      
      // NCHW フォーマット (1, 3, 320, 320)
      for (int c = 0; c < 3; c++) {
        for (int y = 0; y < 320; y++) {
          for (int x = 0; x < 320; x++) {
            final pixel = resizedImage.getPixel(x, y);
            double val = 0.0;
            if (c == 0) val = pixel.r / 255.0;
            if (c == 1) val = pixel.g / 255.0;
            if (c == 2) val = pixel.b / 255.0;
            inputBytes[pixelIndex++] = val;
          }
        }
      }

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputBytes,
        [1, 3, 320, 320],
      );

      final runOptions = OrtRunOptions();
      final inputs = {'images': inputTensor};
      final outputs = session?.run(runOptions, inputs);
      
      inputTensor.release();
      runOptions.release();

      if (outputs != null && outputs.isNotEmpty) {
        final value = outputs[0]?.value;
        if (value is List) {
          parseYoloOutput(value, image.width.toDouble(), image.height.toDouble());
        }
      }
    } catch (e) {
      debugPrint('推論エラー: $e');
    } finally {
      if (mounted) {
        setState(() {
          isDetecting = false;
        });
      }
    }
  }

  void parseYoloOutput(List<dynamic> output, double imgWidth, double imgHeight) {
    List<List<double>> candidates = [];
    try {
      var tensorData = output;
      if (tensorData.length == 1 && tensorData[0] is List) {
        tensorData = tensorData[0] as List<dynamic>;
      }

      int numAttributes = tensorData.length;
      if (numAttributes < 5) return;
      int numAnchors = (tensorData[0] as List).length;

      double highestScoreInFrame = 0.0;

      for (int i = 0; i < numAnchors; i++) {
        double maxScore = 0.0;
        int maxClassId = 0;

        for (int c = 4; c < numAttributes; c++) {
          double score = (tensorData[c][i] as num).toDouble();
          if (score > maxScore) {
            maxScore = score;
            maxClassId = c - 4;
          }
        }

        if (maxScore > highestScoreInFrame) {
          highestScoreInFrame = maxScore;
        }

        // スコアの閾値（反応が良すぎたら 0.25〜0.3 に戻してください）
        if (maxScore > 0.15) {
          double cx = (tensorData[0][i] as num).toDouble();
          double cy = (tensorData[1][i] as num).toDouble();
          double w = (tensorData[2][i] as num).toDouble();
          double h = (tensorData[3][i] as num).toDouble();

          // 0.0 ～ 1.0 の相対割合（比率）に変換して保持
          double rx1 = (cx - w / 2) / 320.0;
          double ry1 = (cy - h / 2) / 320.0;
          double rx2 = (cx + w / 2) / 320.0;
          double ry2 = (cy + h / 2) / 320.0;

          candidates.add([rx1, ry1, rx2, ry2, maxScore, maxClassId.toDouble()]);
        }
      }

      debugPrint('フレーム内の最高スコア: $highestScoreInFrame');

      recognitions = applyNMS(candidates, 0.45);
      
      if (mounted) {
        setState(() {
          statusMessage = 'AI推論中 (最高スコア: ${(highestScoreInFrame * 100).toStringAsFixed(1)}%)';
        });
      }
    } catch (e) {
      debugPrint('パースエラー: $e');
    }
  }
  List<List<double>> applyNMS(List<List<double>> boxes, double iouThreshold) {
    boxes.sort((a, b) => b[4].compareTo(a[4]));
    List<List<double>> result = [];

    while (boxes.isNotEmpty) {
      var best = boxes.removeAt(0);
      result.add(best);

      boxes.removeWhere((box) {
        if (box[5] != best[5]) return false;
        double iou = calculateIoU(best, box);
        return iou > iouThreshold;
      });
    }

    return result;
  }

  double calculateIoU(List<double> a, List<double> b) {
    double x1 = max(a[0], b[0]);
    double y1 = max(a[1], b[1]);
    double x2 = min(a[2], b[2]);
    double y2 = min(a[3], b[3]);

    double intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    double areaA = (a[2] - a[0]) * (a[3] - a[1]);
    double areaB = (b[2] - b[0]) * (b[3] - b[1]);

    return intersection / (areaA + areaB - intersection);
  }

  img.Image convertYUV420ToRGB(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final rgbImage = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * yRowStride + x;
        final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yVal = yPlane.bytes[yIndex];
        final int uVal = uPlane.bytes[uvIndex] - 128;
        final int vVal = vPlane.bytes[uvIndex] - 128;

        int r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
        int g = (yVal - 0.337633 * uVal - 0.698001 * vVal).round().clamp(0, 255);
        int b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return rgbImage;
  }

  @override
  void dispose() {
    controller?.dispose();
    session?.release();
    OrtEnv.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('標識リアルタイム検知'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          CameraPreview(controller!),
          
          Positioned.fill(
            child: CustomPaint(
              painter: BoundingBoxPainter(recognitions, labels),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<List<double>> recognitions;
  final List<String> labels;

  BoundingBoxPainter(this.recognitions, this.labels);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    for (var reg in recognitions) {
      // 比率データ(0.0~1.0)を、画面の実際の縦横サイズ(size)に掛け合わせる
      // ※カメラ画像が横向きで処理されるため、XとYを入れ替えて画面にフィットさせます
      double left = reg[1] * size.width;
      double top = reg[0] * size.height;
      double right = reg[3] * size.width;
      double bottom = reg[2] * size.height;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, paint);

      final classId = reg[5].toInt();
      final labelText = classId < labels.length ? labels[classId] : '標識';
      
      final textSpan = TextSpan(
        text: ' $labelText ${(reg[4] * 100).toStringAsFixed(0)}% ',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.red,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(left, max(0.0, top - 25)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}