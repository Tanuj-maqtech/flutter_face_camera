import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emoji On  Face Overlay',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ARFaceOverlay(),
    );
  }
}

class ARFaceOverlay extends StatefulWidget {
  @override
  _ARFaceOverlayState createState() => _ARFaceOverlayState();
}

class _ARFaceOverlayState extends State<ARFaceOverlay> {
  CameraController? _cameraController;
  bool _isDetecting = false;
  List<Face>? _faces;

  @override
  void initState() {
    super.initState();

  }

  Future<void> _checkPermissionsAndInitializeCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _initializeCamera();
    } else {
      print('Camera permission denied');
    }
  }

  Future<void> _requestNotificationPermissions() async {
    final PermissionStatus status = await Permission.notification.request();
    if (status.isGranted) {
      await _checkPermissionsAndInitializeCamera();
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _initializeCamera() async {
    final frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.high,
    );

    await _cameraController!.initialize();

    _cameraController!.startImageStream((image) {
      if (_isDetecting) return;
      _isDetecting = true;

      _detectFaces(image).then((faces) {
        setState(() {
          _faces = faces;
        });
        _isDetecting = false;
      }).catchError((error) {
        print('Error detecting faces: $error');
        _isDetecting = false;
      });
    });
  }

  Future<List<Face>> _detectFaces(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final InputImageRotation imageRotation =
        InputImageRotationMethods.fromRawValue(_cameraController!.description.sensorOrientation) ??
            InputImageRotation.Rotation_180deg;

    final InputImageFormat inputImageFormat =
        InputImageFormatMethods.fromRawValue(image.format.raw) ?? InputImageFormat.NV21;

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final List<InputImagePlaneMetadata> planeData = image.planes.map(
          (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    final inputImage = InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    final faceDetector = GoogleMlKit.vision.faceDetector(FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
    ));

    try {
      final faces = await faceDetector.processImage(inputImage);
      print('Detected faces: ${faces.length}');
      return faces;
    } catch (e) {
      print('Failed to detect faces: $e');
      return [];
    }
  }

  void _toggleCamera() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _requestNotificationPermissions();
     // _checkPermissionsAndInitializeCamera();
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AR Face Overlay')),
      body: Column(
        children: [
          Expanded(
            child: _cameraController == null || !_cameraController!.value.isInitialized
                ? Container(
              color: Colors.black,
              child: const Center(child: CircularProgressIndicator()),
            )
                : Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController!),
                _buildFaceOverlay(),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _toggleCamera,
            child: Text('Open Camera'),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceOverlay() {
    if (_faces == null || _faces!.isEmpty) {
      return Container();
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        painter: FacePainter(_faces!, _cameraController!.value.previewSize!),
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;

  FacePainter(this.faces, this.imageSize);

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (Face face in faces) {
      final rect = Rect.fromLTRB(
        face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        face.boundingBox.right * scaleX,
        face.boundingBox.bottom * scaleY,
      );

      final double emojiSize = rect.width * 2;

      final emojiPainter = TextPainter(
        text: TextSpan(
          text: '😀',
          style: TextStyle(fontSize: emojiSize),
        ),
        textDirection: TextDirection.ltr,
      );

      emojiPainter.layout();

      final emojiOffset = Offset(
        rect.left,
        rect.top - (rect.height / 2),
      );
      print('Painting emoji at offset: $emojiOffset');

      emojiPainter.paint(canvas, emojiOffset);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}