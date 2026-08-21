import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

/// YOLO/ONNXによる一時停止標識検知を管理するクラス
class YoloService {
  CameraController? _cameraController;
  bool _isProcessing = false;

  /// カメラの初期化とリアルタイム検知の開始
  Future<void> startDetection(Function(bool isDetected) onDetectionResult) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // 背面カメラを使用
      _cameraController = CameraController(
        cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // フレームごとの画像ストリームを取得
      _cameraController!.startImageStream((CameraImage image) async {
        if (_isProcessing) return; // 推論中はスキップ
        _isProcessing = true;

        try {
          // --- ここで ONNX モデルに画像（image）を入力して推論 ---
          bool isStopSign = await _runOnnxInference(image);

          // 親（main.dart）へ判定結果を通知
          onDetectionResult(isStopSign);
        } catch (e) {
          debugPrint('推論エラー: $e');
        } finally {
          _isProcessing = false;
        }
      });
    } catch (e) {
      debugPrint('カメラ初期化エラー: $e');
    }
  }

  /// ONNXモデルでの推論処理（ダミー・調整用プレースホルダー）
  Future<bool> _runOnnxInference(CameraImage image) async {
    // TODO: 実際の ONNX runtime への前処理・推論・後処理ロジックをここに記述
    // 現在は動作テスト用のダミー処理
    return false;
  }

  /// カメラリソースの解放
  void stopDetection() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _cameraController = null;
  }
}
