import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
// Only for openAppSettings (opens CivicBuddy's page in Android Settings).
import 'package:geolocator/geolocator.dart' show Geolocator;

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? controller;

  bool isInitializing = true;
  bool isTakingPicture = false;

  // The user said "Don't allow" to Android's camera permission popup.
  bool _permissionDenied = false;

  XFile? capturedImage;

  // Zoom range reported by the camera, and the current level.
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _zoomAtPinchStart = 1;
  bool _isPinching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings after allowing the camera: try again.
    if (state == AppLifecycleState.resumed &&
        _permissionDenied &&
        !isInitializing) {
      initializeCamera();
    }
  }

  /// Starts the camera. The camera plugin asks Android's native permission
  /// popup ("Allow CivicBuddy to take pictures and record video?") here when
  /// needed.
  Future<void> initializeCamera() async {
    CameraController? newController;

    if (controller == null && !isInitializing) {
      setState(() {
        isInitializing = true;
        _permissionDenied = false;
      });
    }

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera found');
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      newController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await newController.initialize();

      if (!mounted) {
        await newController.dispose();
        return;
      }

      setState(() {
        controller = newController;
        isInitializing = false;
        _permissionDenied = false;
      });

      _loadZoomRange(newController);
    } catch (e) {
      await newController?.dispose();

      if (!mounted) return;

      final denied =
          e is CameraException &&
          const {
            'CameraAccessDenied', // Android and iOS
            'CameraAccessDeniedWithoutPrompt', // iOS
            'CameraAccessRestricted', // iOS
          }.contains(e.code);

      setState(() {
        isInitializing = false;
        _permissionDenied = denied;
      });

      if (!denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start the camera. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> captureImage() async {
    if (controller == null ||
        !controller!.value.isInitialized ||
        isTakingPicture) {
      return;
    }

    setState(() {
      isTakingPicture = true;
    });

    try {
      final image = await controller!.takePicture();

      if (!mounted) return;

      setState(() {
        capturedImage = image;
        isTakingPicture = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isTakingPicture = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to capture image: $e')));
    }
  }

  // ------------------------------------------------------------
  // Zoom
  // ------------------------------------------------------------

  /// Right after initialize() the Android (CameraX) plugin still reports a
  /// placeholder 1x-1x range until the camera is running, so poll briefly
  /// for the real one. Cameras that truly cannot zoom stay 1x-only.
  Future<void> _loadZoomRange(CameraController camera) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final minZoom = await camera.getMinZoomLevel();
        final maxZoom = await camera.getMaxZoomLevel();

        if (!mounted || controller != camera) return;

        if (maxZoom > 1 || minZoom < 1) {
          setState(() {
            _minZoom = minZoom;
            _maxZoom = maxZoom;
            _zoom = 1.clamp(minZoom, maxZoom).toDouble();
          });
          return;
        }
      } catch (_) {
        // Zoom state not available yet; try again.
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted || controller != camera) return;
    }
  }

  Future<void> _setZoom(double zoom) async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized) return;

    final clamped = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if ((clamped - _zoom).abs() < 0.01) return;

    setState(() => _zoom = clamped);

    try {
      await camera.setZoomLevel(clamped);
    } catch (_) {
      // Ignore: the next pinch or button tap tries again.
    }
  }

  /// Zoom buttons like the phone camera: 0.5x only with an ultra-wide lens,
  /// 2x and 5x only when the camera can zoom that far.
  List<double> get _zoomPresets => [
    if (_minZoom < 1) _minZoom,
    1,
    if (_maxZoom >= 2) 2,
    if (_maxZoom >= 5) 5,
  ];

  /// The button that "owns" the current zoom: the largest preset at or below it.
  double get _activePreset =>
      _zoomPresets.lastWhere((p) => p <= _zoom + 0.05, orElse: () => _minZoom);

  String _zoomLabel(double zoom) {
    final rounded = zoom.roundToDouble();
    return (zoom - rounded).abs() < 0.05
        ? '${rounded.toInt()}x'
        : '${zoom.toStringAsFixed(1)}x';
  }

  void retakeImage() {
    setState(() {
      capturedImage = null;
    });
  }

  void useImage() {
    if (capturedImage == null) return;

    Navigator.pop(context, capturedImage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  /// Shown instead of the preview when the camera could not start. When the
  /// permission was denied, "Allow camera" asks Android's popup again (while
  /// Android still allows asking) and "Open settings" covers the case where
  /// Android no longer shows it.
  Widget _cameraBlockedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _permissionDenied
                  ? Icons.no_photography_outlined
                  : Icons.videocam_off_outlined,
              color: Colors.white,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              _permissionDenied
                  ? 'Camera permission needed'
                  : 'Camera unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _permissionDenied
                  ? 'CivicBuddy needs the camera to take photos of garbage '
                        'spots. Tap Allow camera, or allow it in Settings.'
                  : 'The camera could not be started.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: initializeCamera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_permissionDenied ? 'Allow camera' : 'Try again'),
            ),
            if (_permissionDenied) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: Geolocator.openAppSettings,
                child: const Text('Open settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: capturedImage == null ? buildCameraView() : buildImagePreview(),
      ),
    );
  }

  Widget buildCameraView() {
    return Stack(
      children: [
        Positioned.fill(
          child: isInitializing
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : controller != null && controller!.value.isInitialized
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) => _zoomAtPinchStart = _zoom,
                  onScaleUpdate: (details) {
                    // Two fingers only, so a single tap or drag never zooms.
                    if (details.pointerCount < 2) return;
                    if (!_isPinching) setState(() => _isPinching = true);
                    _setZoom(_zoomAtPinchStart * details.scale);
                  },
                  onScaleEnd: (_) {
                    if (_isPinching) setState(() => _isPinching = false);
                  },
                  child: Center(child: CameraPreview(controller!)),
                )
              : _cameraBlockedView(),
        ),

        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Row(
            children: [
              _circleButton(
                icon: Icons.close,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Capture Garbage',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),

        // Shutter and hints only while the camera is running.
        if (controller != null && controller!.value.isInitialized)
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: captureImage,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isTakingPicture ? Colors.grey : Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Current zoom, shown large while pinching.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _isPinching ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _zoomLabel(_zoom),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        if (controller != null &&
            controller!.value.isInitialized &&
            _zoomPresets.length > 1)
          Positioned(
            bottom: 128,
            left: 0,
            right: 0,
            child: Center(child: _zoomControls()),
          )
        else if (controller != null && controller!.value.isInitialized)
          const Positioned(
            bottom: 125,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Tap to capture',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }

  /// 0.5x / 1x / 2x / 5x buttons. The active one shows the exact zoom
  /// (e.g. 1.6x after pinching), like the built-in camera app.
  Widget _zoomControls() {
    final active = _activePreset;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in _zoomPresets)
            GestureDetector(
              onTap: () => _setZoom(preset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: preset == active ? 46 : 36,
                height: preset == active ? 46 : 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(
                    alpha: preset == active ? 0.7 : 0.35,
                  ),
                ),
                child: Text(
                  preset == active ? _zoomLabel(_zoom) : _zoomLabel(preset),
                  style: TextStyle(
                    color: preset == active
                        ? const Color(0xFFFFD54F)
                        : Colors.white,
                    fontSize: preset == active ? 13 : 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildImagePreview() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(File(capturedImage!.path), fit: BoxFit.contain),
        ),

        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Row(
            children: [
              _circleButton(
                icon: Icons.close,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),

        Positioned(
          bottom: 30,
          left: 20,
          right: 20,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: retakeImage,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: ElevatedButton.icon(
                  onPressed: useImage,
                  icon: const Icon(Icons.check),
                  label: const Text('Use Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}
