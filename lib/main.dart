import 'dart:collection';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vision_bot/robot.dart';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'ffi.dart';

import 'package:collection/collection.dart';

import 'projects.dart';

import 'dart:ui' as dartui;

const int ourPort = 8888;

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const SelectorPage(title: 'Flutter Demo Home Page'),
    );
  }
}

class SelectorPage extends StatefulWidget {
  const SelectorPage({super.key, required this.title});

  final String title;

  @override
  State<SelectorPage> createState() => SelectorPageState();
}

abstract class VisionRunner {
  Widget display(SelectorPageState selector);
  CameraImagePainter livePicture();

  String getReply(String message, Queue<String> requests, Directory fileSystemPath) {
    if (!requests.isEmpty) {
      return requests.removeFirst();
    } else {
      return "None";
    }
  }
}

class SelectorPageState extends State<SelectorPage> {
  late CameraController controller;
  final Queue<String> _requests = Queue();
  VisionRunner? running;

  String ipAddr = "Awaiting IP Address...";
  String incoming = "Setting up server...";
  String otherMsg = "";
  RobotStatus _robotStatus = RobotStatus.notStarted;
  RobotState _robotState = RobotState(left: WheelAction.stop, right: WheelAction.stop);

  String _applicationSupportDir = "";
  List<String> projects = ["None"];
  List<String> labels = ["None"];
  String currentProject = "None";
  String currentLabel = "None";
  String _test = "Alpha";

  List<PhotoInfo> loadedPhotos = [];
  int _currentPhoto = 0;

  Directory appDir() {
    return Directory(_applicationSupportDir);
  }

  Widget startStopButton() {
    if (_robotStatus == RobotStatus.notStarted) {
      return makeCmdButton("Start", Colors.purple, () {
        api.resetPositionEstimate().then((value) {
          setState(() {
            _robotStatus = RobotStatus.started;
          });
          _requests.addLast('Start');
          print("Sending Start");
        });
      });
    } else if (_robotStatus == RobotStatus.started) {
      return makeCmdButton("Stop", Colors.red, () {
        api.resetPositionEstimate().then((value) {
          setState(() {
            _robotStatus = RobotStatus.notStarted;
          });
          _requests.addLast('Stop');
          print("Sending Stop");
        });
      });
    } else {
      return const Text("Robot stopped");
    }
  }

  @override
  void initState() {
    super.initState();
    controller = CameraController(_cameras[0], ResolutionPreset.low);
    _setupProjects();
    _setupServer();
    _findIPAddress();
  }

  Future<void> _findIPAddress() async {
    // Thank you https://stackoverflow.com/questions/52411168/how-to-get-device-ip-in-dart-flutter
    String? ip = await NetworkInfo().getWifiIP();
    setState(() {
      ipAddr = "My IP: ${ip!}";
    });
  }

  Future<void> _setupServer() async {
    try {
      ServerSocket server = await ServerSocket.bind(InternetAddress.anyIPv4, ourPort);
      server.listen(_listenToSocket); // StreamSubscription<Socket>
      setState(() {
        incoming = "Server ready";
      });
    } on SocketException catch (e) {
      print("ServerSocket setup error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error: $e"),
      ));
    }
  }

  Future<void> _setupProjects() async {
    Directory appDir = await getApplicationSupportDirectory();
    _applicationSupportDir = appDir.path;
    projects = await listProjects(Directory(_applicationSupportDir));
    currentProject = projects.isEmpty ? "None" : projects[0];
    updateLabels(currentProject);
  }

  void updateProjects() {
    listProjects(Directory(_applicationSupportDir)).then((updatedProjects) {
      setState(() {
        projects = updatedProjects;
        updateLabels(currentProject);
      });
    });
  }

  void updateLabels(String project) {
    listLabels(Directory(_applicationSupportDir), project).then((updatedLabels) {
      setState(() {
        currentProject = project;
        labels = updatedLabels;
        if (updatedLabels.isNotEmpty) {
          currentLabel = updatedLabels[0];
          refreshImages(0);
        } else {
          loadedPhotos = [];
        }
      });
    });
  }

  Widget photoColumn() {
    if (loadedPhotos.isEmpty) {
      return const Text("No photos");
    } else {
      List<Widget> column = [];
      column.add(SizedBox(height: 100, child: CustomPaint(painter: StillPhotoPainter(loadedPhotos[_currentPhoto].photo))));
      column.add(Text(loadedPhotos[_currentPhoto].filename()));

      if (_currentPhoto > 0) {
        column.add(TextButton(onPressed: () { setState(() {
          _currentPhoto -= 1;
        });}, child: const Text("Previous"),));
      }

      if (_currentPhoto + 1 < loadedPhotos.length) {
        column.add(TextButton(onPressed: () {setState(() {
          _currentPhoto += 1;
        });}, child: const Text("Next")));
      }

      column.add(deletePhoto());

      return Column(mainAxisAlignment: MainAxisAlignment.center, children: column);
    }
  }

  void refreshImages(int photoChoice) {
    loadImages(Directory(_applicationSupportDir), currentProject, currentLabel).then((loaded) {
      setState(() {
        loadedPhotos = loaded;
        _currentPhoto = photoChoice;
      });
    });
  }

  Widget projectChoices() {
    return makeChoices(currentProject, projects, updateLabels);
  }

  Widget labelChoices() {
    return makeChoices(currentLabel, labels, (label) {
      currentLabel = label;
      refreshImages(0);
    });
  }

  Widget takePhoto() {
    return makeCmdButton("Take Photo", Colors.orange, () {
      dartui.Image img = running!.livePicture().getImage();
      int sizeBeforeSave = loadedPhotos.length;
      saveImage(img, Directory(_applicationSupportDir), currentProject, currentLabel).then((value) {
        setState(() {
          otherMsg = value;
          refreshImages(sizeBeforeSave);
        });
      });
    });
  }

  Widget deletePhoto() {
    return makeCmdButton("Delete Photo", Colors.red, () {
      if (loadedPhotos.isNotEmpty) {
        File deleteMe = File(loadedPhotos[_currentPhoto].filePath);
        deleteMe.delete().then((value) {
          setState(() {
            otherMsg = "deleted";
            if (loadedPhotos.length > 1) {
              _currentPhoto -= 1;
            }
            refreshImages(_currentPhoto);
          });
        });
      }
    });
  }

  Widget addProject() {
    return makeCmdButton("Add Project", Colors.blue, () {
      addNewProject(Directory(_applicationSupportDir)).then((value) {
        currentProject = value;
        updateProjects();
      });
    });
  }

  Widget renameProject() {
    // SizedBox() fixes RenderBox problem:
    // https://stackoverflow.com/questions/51809451/how-to-solve-renderbox-was-not-laid-out-in-flutter-in-a-card-widget
    return SizedBox(width: 150,
    child: TextField(
      decoration: const InputDecoration(hintText: "Rename Project", border: UnderlineInputBorder()),
      onSubmitted: (value) {
        renameExistingProject(Directory(_applicationSupportDir), currentProject, value).then((nothing) {
          setState(() {
            currentProject = value;
            updateProjects();
          });
        });
        },
    ));
  }

  Widget addLabel() {
    return makeCmdButton("Add Label", Colors.green, () {
      addNewLabel(Directory(_applicationSupportDir), currentProject).then((value) {
        updateLabels(currentProject);
      });
    });
  }

  Widget renameLabel() {
    return SizedBox(width: 150, child: TextField(
      decoration: const InputDecoration(hintText: "Rename Label"),
      onSubmitted: (value) {
        renameExistingLabel(Directory(_applicationSupportDir), currentProject, currentLabel, value).then((nothing) {
          currentLabel = value;
          updateLabels(currentProject);
        });
      },
    ));
  }

  void _listenToSocket(Socket socket) {
    socket.listen((data) {
      String msg = String.fromCharCodes(data);
      print("received $msg");
      if (running != null) {
        socket.write(running!.getReply(msg, _requests, appDir()));
      } else {
        // The "if" clause represents what I should really be doing on an
        // engineering level - each VisionRunner should process incoming
        // messages in its own way.
        //
        // This is old code I wrote when trying to build a SLAM navigator.
        // It assumes a very specific robot layout.
        // I should probably delete it, but I am hesitant for some reason.
        if (msg == "cmd") {
          if (_requests.isEmpty) {
            socket.write("None");
          } else {
            socket.write(_requests.removeFirst());
          }
        } else {
          getProcessedData(msg);
        }
      }
      socket.close();
    });
  }

  Future<void> getProcessedData(String incomingData) async {
    String processed = await api.processSensorData(incomingData: incomingData);
    SensorData data = await api.parseSensorData(incomingData: incomingData);
    _robotState = RobotState.decode(data);
    setState(() {
      incoming = processed;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (running == null) {
      return MaterialApp(
          home: Scaffold(
              appBar: AppBar(
                  title: const Text("This is a title")),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(_applicationSupportDir),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          selectorButton(
                              "Image", Colors.blue, () => SimpleImageRunner()),
                          selectorButton(
                              "Akaze", Colors.cyan, () => AkazeImageRunner()),
                          selectorButton(
                              "Akaze Flow", Colors.green, () => AkazeImageFlowRunner()),
                          selectorButton(
                              "Photographer", Colors.yellow, () => PhotoImageRunner()),
                          selectorButton("Knn", Colors.deepPurple, () => KnnImageRunner()),
                        ]
                    )
                  ]
                )
              )
          )
      );
    } else {
      return running!.display(this);
    }
  }

  Widget selectorButton(String label, Color color, VisionRunner Function() runner) {
    return makeCmdButton(label, color, () {
      running = runner();
      controller.initialize().then((_) {
        if (!mounted) {
          return;
        }
        controller.startImageStream((image) {
          setState(() {
            if (running != null) {
              if (running!.livePicture().ready()) {
                print("Got an image...");
                running!.livePicture().setImage(image).whenComplete(() {
                  print("Processed image.");
                });
              } else {
                print("Dropped image.");
              }
            }
          });
        });
        setState(() {});
      }).catchError((Object e) {
        if (e is CameraException) {
          switch (e.code) {
            case 'CameraAccessDenied':
              print('User denied camera access.');
              break;
            default:
              print('Handle other errors.');
              break;
          }
        }
      });
    });
  }

  Widget returnToStartButton() {
    return makeCmdButton("Return to start", Colors.red, () {
      if (running != null) {
        controller.stopImageStream();
        running = null;
      }
    });
  }

  Widget makeChoices(String current, List<String> options, void Function(String) cmd) {
    return Row(
      children: [
        Column(children: options.mapIndexed((index, element) =>
            TextButton(
                onPressed: () {
                  setState(() {cmd(options[index]);});
                  },
                child: Text(
                    "$element",
                  style: TextStyle(color: current == element ? Colors.red : Colors.blue),
                ))).toList()),
      ],
    );
  }

  Widget testDropdown() {
    return makeChoices(_test, ["Alpha", "Beta", "Gamma"], (s) {_test = s;});
  }
}

Widget makeCmdButton(String label, Color color, void Function() cmd) {
  return SizedBox(
      width: 100,
      height: 100,
      child: ElevatedButton(
          onPressed: cmd,
          style: ElevatedButton.styleFrom(
              backgroundColor: color,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20))),
          child: Text(label)));
}

enum RobotStatus {
  notStarted, started, stopped;
}

class StillPhotoPainter extends CustomPainter {
  final dartui.Image _photo;

  StillPhotoPainter(this._photo);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(_photo, Offset(-_photo.width/2, -_photo.height/2), Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}