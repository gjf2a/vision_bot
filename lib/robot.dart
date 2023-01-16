import 'dart:ui' as dartui;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ffi.dart';
import 'main.dart';

class SimpleImageRunner extends VisionRunner {
  final CameraImagePainter _livePicture = CameraImagePainter(api.yuvRgba);

  @override
  CameraImagePainter livePicture() {
    return _livePicture;
  }

  @override
  Widget display(SelectorPageState selector) {
    return MaterialApp(
        home: Scaffold(
            appBar: AppBar(
                title: const Text("This is a title")),
            body: Center(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CustomPaint(painter: _livePicture),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          selector.startStopButton(),
                          Text(selector.ipAddr),
                          Text("Grabbed: ${_livePicture.frameCount()} (${_livePicture.width()} x ${_livePicture.height()}) FPS: ${_livePicture.fps().toStringAsFixed(2)}"),
                          Text(selector.incoming),
                          Text(_livePicture.lastMessage),
                          //selector.returnToStartButton(),
                        ],
                      ),
                    ]
                )
            )
        )
    );
  }
}

class AkazeImageRunner extends VisionRunner {
  final CameraImagePainter _livePicture = CameraImagePainter(api.akazeView);

  @override
  Widget display(SelectorPageState selector) {
    return MaterialApp(
        home: Scaffold(
            appBar: AppBar(
                title: const Text("This is a title")),
            body: Center(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CustomPaint(painter: _livePicture),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          selector.startStopButton(),
                          Text(selector.ipAddr),
                          Text("Grabbed: ${_livePicture.frameCount()} (${_livePicture.width()} x ${_livePicture.height()}) FPS: ${_livePicture.fps().toStringAsFixed(2)}"),
                          Text(selector.incoming),
                          Text(_livePicture.lastMessage),
                          //selector.returnToStartButton(),
                        ],
                      ),
                    ]
                )
            )
        )
    );
  }

  @override
  CameraImagePainter livePicture() {
    return _livePicture;
  }
}



class AkazeImageFlowRunner extends VisionRunner {
  final CameraImagePainter _livePicture = CameraImagePainter(api.akazeFlow);

  @override
  Widget display(SelectorPageState selector) {
    return MaterialApp(
        home: Scaffold(
            appBar: AppBar(
                title: const Text("This is a title")),
            body: Center(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CustomPaint(painter: _livePicture),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          selector.startStopButton(),
                          Text(selector.ipAddr),
                          Text("Grabbed: ${_livePicture.frameCount()} (${_livePicture.width()} x ${_livePicture.height()}) FPS: ${_livePicture.fps().toStringAsFixed(2)}"),
                          Text(selector.incoming),
                          Text(_livePicture.lastMessage),
                          //selector.returnToStartButton(),
                        ],
                      ),
                    ]
                )
            )
        )
    );
  }

  @override
  CameraImagePainter livePicture() {
    return _livePicture;
  }
}

class CameraImagePainter extends CustomPainter {
  late dartui.Image _lastImage;
  String lastMessage = "No messages yet";
  bool _initialized = false;
  int _width = 0, _height = 0;
  DateTime _start = DateTime.now();
  double _fps = 0.0;
  int _frameCount = 0;
  bool _ready = true;
  Future<ImageResponse> Function({required ImageData img, dynamic hint}) imageMaker;

  CameraImagePainter(this.imageMaker);

  Future<void> setImage(CameraImage img) async {
    _ready = false;
    if (!_initialized) {
      _start = DateTime.now();
      _initialized = true;
    }
    ImageResponse response = await imageMaker(img: from(img));
    _lastImage = await makeImageFrom(response.img, img.width, img.height);
    lastMessage = response.msg;
    _width = _lastImage.width;
    _height = _lastImage.height;
    _frameCount += 1;
    Duration elapsed = DateTime.now().difference(_start);
    _fps = _frameCount / elapsed.inSeconds;
    _ready = true;
  }

  double fps() {return _fps;}
  int frameCount() {return _frameCount;}
  int width() {return _width;}
  int height() {return _height;}
  bool ready() {return _ready;}

  void resetFps() {
    _fps = 0.0;
    _frameCount = 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_initialized) {
      canvas.drawImage(_lastImage, Offset(-_width/2, -_height/2), Paint());
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => _initialized;
}

ImageData from(CameraImage img) {
  return ImageData(ys: img.planes[0].bytes, us: img.planes[1].bytes, vs: img.planes[2].bytes, width: img.width, height: img.height, uvRowStride: img.planes[1].bytesPerRow, uvPixelStride: img.planes[1].bytesPerPixel!);
}

// This is super-clunky. I wonder if there's a better way...
Future<dartui.Image> makeImageFrom(Uint8List intensities, int width, int height) async {
  dartui.ImmutableBuffer rgba = await dartui.ImmutableBuffer.fromUint8List(intensities);
  dartui.Codec c = await dartui.ImageDescriptor.raw(rgba, width: width, height: height, pixelFormat: dartui.PixelFormat.rgba8888).instantiateCodec(targetWidth: width, targetHeight: height);
  dartui.FrameInfo frame = await c.getNextFrame();
  dartui.Image result = frame.image.clone();
  frame.image.dispose();
  return result;
}

enum WheelAction {
  forward, backward, stop
}

WheelAction fromSpeed(int speed) {
  if (speed < 0) {
    return WheelAction.backward;
  } else if (speed > 0) {
    return WheelAction.forward;
  } else {
    return WheelAction.stop;
  }
}

class RobotState {
  final WheelAction left;
  final WheelAction right;

  RobotState({required this.left, required this.right});

  RobotState.decode(SensorData data) : left = fromSpeed(data.leftSpeed), right = fromSpeed(data.rightSpeed);

  bool straight() {
    return left == WheelAction.forward && right == WheelAction.forward;
  }
}