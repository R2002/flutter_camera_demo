import 'dart:io';

import 'package:camera_demo_rfarms/screens/captures_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import './preview_screen.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // 各種コントローラ
  CameraController? controller;
  VideoPlayerController? videoController;
  // 画像
  File? _imageFile;
  File? _videoFile;
  File? _clipFile;
  // 画像ファイルリスト
  List<File> allFileList = [];
  // 画面調整
  final resolutionPresets = ResolutionPreset.values;
  ResolutionPreset currentResolutionPreset = ResolutionPreset.high;
  FlashMode? _currentFlashMode;
  // bool
  bool _isCameraInitialized = false;
  bool _isVideoCameraSelected = false;
  bool _isRecordingInProgress = false;
  bool _isRearCameraSelected = true;
  bool _isCameraPermissionGranted = false;
  // 数値
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoomLevel = 1.0;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;

  // 許可取得
  getPermissionStatus() async {
    await Permission.camera.request();
    var status = await Permission.camera.status;

    if (status.isGranted) {
      print('Camera Permission: GRANTED');
      setState(() {
        _isCameraPermissionGranted = true;
      });
      // Set and initialize the new camera
      onNewCameraSelected(cameras[0]);
      refreshAlreadyCapturedImages();
    } else {
      print('Camera Permission: DENIED');
    }
  }

  // カメラ設定
  void onNewCameraSelected(CameraDescription cameraDescription) async {
    final previousCameraController = controller;
    // Instantiating the camera controller
    final CameraController cameraController = CameraController(
      cameraDescription,
      currentResolutionPreset,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    // Dispose the previous controller
    await previousCameraController?.dispose();
    // スライダーリセット
    resetCameraValues();

    // Replace with the new controller
    if (mounted) {
      setState(() {
        controller = cameraController;
      });
    }

    // Update UI if controller updated
    cameraController.addListener(() {
      if (mounted) setState(() {});
    });

    // Initialize controller
    try {
      await cameraController.initialize();
      await Future.wait([
        cameraController
            .getMaxZoomLevel()
            .then((value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((value) => _minAvailableZoom = value),
        cameraController
            .getMinExposureOffset()
            .then((value) => _minAvailableExposureOffset = value),
        cameraController
            .getMaxExposureOffset()
            .then((value) => _maxAvailableExposureOffset = value),
      ]);
      _currentFlashMode = controller!.value.flashMode;
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
    }

    // Update the Boolean
    if (mounted) {
      setState(() {
        _isCameraInitialized = controller!.value.isInitialized;
      });
    }
  }

  // リセット
  void resetCameraValues() async {
    _currentZoomLevel = 1.0;
    _currentExposureOffset = 0.0;
  }

  // 撮影
  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController!.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }
    try {
      XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      print('Error occured while taking picture: $e');
      return null;
    }
  }

  // 撮影後プレビュー
  refreshAlreadyCapturedImages() async {
    final directory = await getApplicationDocumentsDirectory();
    List<FileSystemEntity> fileList = await directory.list().toList();
    allFileList.clear();
    List<Map<int, dynamic>> fileNames = [];

    fileList.forEach((file) {
      if (file.path.contains('.jpg') || file.path.contains('.mp4')) {
        allFileList.add(File(file.path));

        String name = file.path.split('/').last.split('.').first;
        fileNames.add({0: int.parse(name), 1: file.path.split('/').last});
      }
    });

    if (fileNames.isNotEmpty) {
      final recentFile =
          fileNames.reduce((curr, next) => curr[0] > next[0] ? curr : next);
      String recentFileName = recentFile[1];
      if (recentFileName.contains('.mp4')) {
        _imageFile = null;
        _videoFile = File('${directory.path}/$recentFileName');
        _startVideoPlayer();
      } else {
        _imageFile = File('${directory.path}/$recentFileName');
        _videoFile = null;
        videoController!.dispose();
      }

      setState(() {});
    }
  }

  // 表示調整
  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    controller!.setExposurePoint(offset);
    controller!.setFocusPoint(offset);
  }

  // 状態定義
  @override
  void initState() {
    // Hide the status bar
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    // View
    getPermissionStatus();
    super.initState();
  }

  // 停止
  @override
  void dispose() {
    controller?.dispose();
    videoController?.dispose();
    super.dispose();
  }

  // ライフサイクル変更
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // Free up memory when camera not active
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Reinitialize the camera with same properties
      onNewCameraSelected(cameraController.description);
    }
  }

  // 動画撮影開始
  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller;

    if (controller!.value.isRecordingVideo) {
      // A recording has already started, do nothing.
      return;
    }

    try {
      await cameraController!.startVideoRecording();
      setState(() {
        _isRecordingInProgress = true;
        print(_isRecordingInProgress);
      });
    } on CameraException catch (e) {
      print('Error starting to record video: $e');
    }
  }

  // 動画撮影終了
  Future<XFile?> stopVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      // Recording is already is stopped state
      return null;
    }

    try {
      XFile file = await controller!.stopVideoRecording();
      setState(() {
        _isRecordingInProgress = false;
      });
      return file;
    } on CameraException catch (e) {
      print('Error stopping video recording: $e');
      return null;
    }
  }

  // 動画撮影ポーズ
  Future<void> pauseVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      // Video recording is not in progress
      return;
    }

    try {
      await controller!.pauseVideoRecording();
    } on CameraException catch (e) {
      print('Error pausing video recording: $e');
    }
  }

  // 動画撮影再開
  Future<void> resumeVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      // No video recording was in progress
      return;
    }

    try {
      await controller!.resumeVideoRecording();
    } on CameraException catch (e) {
      print('Error resuming video recording: $e');
    }
  }

  // 動画プレイヤー再生
  Future<void> _startVideoPlayer() async {
    if (_videoFile != null) {
      videoController = VideoPlayerController.file(_videoFile!);
      await videoController!.initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized,
        // even before the play button has been pressed.
        setState(() {});
      });
      await videoController!.play();
      await videoController!.setLooping(true);
    }
  }

  // 表示
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isCameraPermissionGranted
            ? _isCameraInitialized
                ? Column(children: [
                    AspectRatio(
                      aspectRatio: 1 / controller!.value.aspectRatio,
                      child: Stack(children: [
                        CameraPreview(
                          controller!,
                          child: LayoutBuilder(builder: (BuildContext context,
                              BoxConstraints constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) =>
                                  onViewFinderTap(details, constraints),
                            );
                          }),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16.0,
                            8.0,
                            16.0,
                            8.0,
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8.0,
                                        right: 8.0,
                                      ),
                                      child: DropdownButton<ResolutionPreset>(
                                        dropdownColor: Colors.black87,
                                        underline: Container(),
                                        value: currentResolutionPreset,
                                        items: [
                                          for (ResolutionPreset preset
                                              in resolutionPresets)
                                            DropdownMenuItem(
                                              child: Text(
                                                preset
                                                    .toString()
                                                    .split('.')[1]
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              ),
                                              value: preset,
                                            )
                                        ],
                                        onChanged: (value) {
                                          setState(() {
                                            currentResolutionPreset = value!;
                                            _isCameraInitialized = false;
                                          });
                                          onNewCameraSelected(
                                              controller!.description);
                                        },
                                        hint: const Text("Select item"),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      right: 8.0, top: 16.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10.0),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        _currentExposureOffset
                                                .toStringAsFixed(1) +
                                            'x',
                                        style: const TextStyle(
                                            color: Colors.black),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: Container(
                                      height: 30,
                                      child: Slider(
                                        value: _currentExposureOffset,
                                        min: _minAvailableExposureOffset,
                                        max: _maxAvailableExposureOffset,
                                        activeColor: Colors.white,
                                        inactiveColor: Colors.white30,
                                        onChanged: (value) async {
                                          setState(() {
                                            _currentExposureOffset = value;
                                          });
                                          await controller!
                                              .setExposureOffset(value);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Slider(
                                        value: _currentZoomLevel,
                                        min: _minAvailableZoom,
                                        max: _maxAvailableZoom,
                                        activeColor: Colors.white,
                                        inactiveColor: Colors.white30,
                                        onChanged: (value) async {
                                          setState(() {
                                            _currentZoomLevel = value;
                                          });
                                          await controller!.setZoomLevel(value);
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(10.0),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(
                                            _currentZoomLevel
                                                    .toStringAsFixed(1) +
                                                'x',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      InkWell(
                                        onTap: _isRecordingInProgress
                                            ? () async {
                                                if (controller!
                                                    .value.isRecordingPaused) {
                                                  await resumeVideoRecording();
                                                } else {
                                                  await pauseVideoRecording();
                                                }
                                              }
                                            : () {
                                                setState(() {
                                                  _isCameraInitialized = false;
                                                });
                                                onNewCameraSelected(cameras[
                                                    _isRearCameraSelected
                                                        ? 1
                                                        : 0]);
                                                setState(() {
                                                  _isRearCameraSelected =
                                                      !_isRearCameraSelected;
                                                });
                                              },
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            const Icon(
                                              Icons.circle,
                                              color: Colors.black38,
                                              size: 60,
                                            ),
                                            _isRecordingInProgress
                                                ? controller!
                                                        .value.isRecordingPaused
                                                    ? const Icon(
                                                        Icons.play_arrow,
                                                        color: Colors.white,
                                                        size: 30,
                                                      )
                                                    : const Icon(
                                                        Icons.pause,
                                                        color: Colors.white,
                                                        size: 30,
                                                      )
                                                : Icon(
                                                    _isRearCameraSelected
                                                        ? Icons.camera_front
                                                        : Icons.camera_rear,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: _isVideoCameraSelected
                                            ? () async {
                                                if (_isRecordingInProgress) {
                                                  XFile? rawVideo =
                                                      await stopVideoRecording();
                                                  File videoFile =
                                                      File(rawVideo!.path);

                                                  int currentUnix = DateTime
                                                          .now()
                                                      .millisecondsSinceEpoch;

                                                  final directory =
                                                      await getApplicationDocumentsDirectory();

                                                  String fileFormat = videoFile
                                                      .path
                                                      .split('.')
                                                      .last;

                                                  _videoFile =
                                                      await videoFile.copy(
                                                    '${directory.path}/$currentUnix.$fileFormat',
                                                  );

                                                  _startVideoPlayer();
                                                } else {
                                                  await startVideoRecording();
                                                }
                                              }
                                            : () async {
                                                XFile? rawImage =
                                                    await takePicture();
                                                File imageFile =
                                                    File(rawImage!.path);

                                                int currentUnix = DateTime.now()
                                                    .millisecondsSinceEpoch;

                                                final directory =
                                                    await getApplicationDocumentsDirectory();

                                                String fileFormat = imageFile
                                                    .path
                                                    .split('.')
                                                    .last;

                                                print(fileFormat);

                                                await imageFile.copy(
                                                  '${directory.path}/$currentUnix.$fileFormat',
                                                );

                                                refreshAlreadyCapturedImages();
                                              },
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: _isVideoCameraSelected
                                                  ? Colors.white
                                                  : Colors.white38,
                                              size: 80,
                                            ),
                                            Icon(
                                              Icons.circle,
                                              color: _isVideoCameraSelected
                                                  ? Colors.red
                                                  : Colors.white,
                                              size: 65,
                                            ),
                                            _isVideoCameraSelected &&
                                                    _isRecordingInProgress
                                                ? const Icon(
                                                    Icons.stop_rounded,
                                                    color: Colors.white,
                                                    size: 32,
                                                  )
                                                : Container(),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: _videoFile != null
                                            ? () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        // 個別表示
                                                        PreviewScreen(
                                                      imageFile: _videoFile!,
                                                      fileList: allFileList,
                                                    ),
                                                  ),
                                                );
                                              }
                                            : _imageFile != null
                                                ? () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            // 個別表示
                                                            PreviewScreen(
                                                          imageFile:
                                                              _imageFile!,
                                                          fileList: allFileList,
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                : () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            // 全体表示
                                                            CapturesScreen(
                                                          imageFileList:
                                                              allFileList,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                        child: Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius:
                                                BorderRadius.circular(10.0),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            image: _imageFile != null
                                                ? DecorationImage(
                                                    image:
                                                        FileImage(_imageFile!),
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                          ),
                                          child: _videoFile != null
                                              // && videoController!
                                              //         .value.isInitialized
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8.0),
                                                  child:
                                                      videoController != null &&
                                                              videoController!
                                                                  .value
                                                                  .isInitialized
                                                          ? AspectRatio(
                                                              aspectRatio:
                                                                  videoController!
                                                                      .value
                                                                      .aspectRatio,
                                                              child: VideoPlayer(
                                                                  videoController!),
                                                            )
                                                          : null,
                                                )
                                              : Container(),
                                        ),
                                      ),
                                    ]),
                              ]),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8.0,
                                        right: 4.0,
                                      ),
                                      child: TextButton(
                                        onPressed: _isRecordingInProgress
                                            ? null
                                            : () {
                                                if (_isVideoCameraSelected) {
                                                  setState(() {
                                                    _isVideoCameraSelected =
                                                        false;
                                                  });
                                                }
                                              },
                                        style: TextButton.styleFrom(
                                          primary: _isVideoCameraSelected
                                              ? Colors.black54
                                              : Colors.black,
                                          backgroundColor:
                                              _isVideoCameraSelected
                                                  ? Colors.white30
                                                  : Colors.white,
                                        ),
                                        child: const Text('IMAGE'),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4.0, right: 8.0),
                                      child: TextButton(
                                        onPressed: () {
                                          if (!_isVideoCameraSelected) {
                                            setState(() {
                                              _isVideoCameraSelected = true;
                                            });
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          primary: _isVideoCameraSelected
                                              ? Colors.black
                                              : Colors.black54,
                                          backgroundColor:
                                              _isVideoCameraSelected
                                                  ? Colors.white
                                                  : Colors.white30,
                                        ),
                                        child: const Text('VIDEO'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16.0, 8.0, 16.0, 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      setState(() {
                                        _currentFlashMode = FlashMode.off;
                                      });
                                      await controller!.setFlashMode(
                                        FlashMode.off,
                                      );
                                    },
                                    child: Icon(
                                      Icons.flash_off,
                                      color: _currentFlashMode == FlashMode.off
                                          ? Colors.amber
                                          : Colors.white,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      setState(() {
                                        _currentFlashMode = FlashMode.auto;
                                      });
                                      await controller!.setFlashMode(
                                        FlashMode.auto,
                                      );
                                    },
                                    child: Icon(
                                      Icons.flash_auto,
                                      color: _currentFlashMode == FlashMode.auto
                                          ? Colors.amber
                                          : Colors.white,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      setState(() {
                                        _currentFlashMode = FlashMode.always;
                                      });
                                      await controller!.setFlashMode(
                                        FlashMode.always,
                                      );
                                    },
                                    child: Icon(
                                      Icons.flash_on,
                                      color:
                                          _currentFlashMode == FlashMode.always
                                              ? Colors.amber
                                              : Colors.white,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      setState(() {
                                        _currentFlashMode = FlashMode.torch;
                                      });
                                      await controller!.setFlashMode(
                                        FlashMode.torch,
                                      );
                                    },
                                    child: Icon(
                                      Icons.highlight,
                                      color:
                                          _currentFlashMode == FlashMode.torch
                                              ? Colors.amber
                                              : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ])
                : const Center(
                    child: Text(
                      'LOADING',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(),
                  const Text(
                    'Permission denied',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      getPermissionStatus();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Give permission',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}