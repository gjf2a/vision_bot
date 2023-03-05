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
  List<String> _projects = ["None"];
  List<String> _labels = ["None"];
  String _currentProject = "None";
  String _currentLabel = "None";
  String _test = "Alpha";

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
    /*
    Directory appDir = await getApplicationDocumentsDirectory();
    _applicationSupportDir = appDir.path;
    _projects = await api.listProjects(fileSystemPath: _applicationSupportDir);
    _currentProject = _projects[0];
    updateLabels(_currentProject);
     */
    Directory appDir = await getApplicationSupportDirectory();
    _applicationSupportDir = appDir.path;
    _projects = await listProjects(Directory(_applicationSupportDir));
    _currentProject = _projects.length == 0 ? "None" : _projects[0];
    updateLabels(_currentProject);
  }

  void updateProjects() {
    /*
    api.listProjects(fileSystemPath: _applicationSupportDir).then((updatedProjects) {
      setState(() {
        _projects = updatedProjects;
        updateLabels(_currentProject);
      });
    });
     */
    listProjects(Directory(_applicationSupportDir)).then((updatedProjects) {
      setState(() {
        _projects = updatedProjects;
        updateLabels(_currentProject);
      });
    });
  }

  void updateLabels(String project) {
    /*
    api.listLabels(fileSystemPath: _applicationSupportDir, project: project).then((updatedLabels) {
      setState(() {
        _currentProject = project;
        _labels = updatedLabels;
        _currentLabel = updatedLabels[0];
      });
    });
     */
    listLabels(Directory(_applicationSupportDir), project).then((updatedLabels) {
      setState(() {
        _currentProject = project;
        _labels = updatedLabels;
        _currentLabel = updatedLabels[0];
      });
    });
  }

  Widget projectChoices() {
    return makeChoices(_currentProject, _projects, updateLabels);
  }

  Widget labelChoices() {
    return makeChoices(_currentLabel, _labels, (label) {_currentLabel = label;});
  }

  Widget takePhoto() {
    return makeCmdButton("Take Photo", Colors.orange, () {
      api.storeImage(project: _currentProject, label: _currentLabel, fileSystemPath: _applicationSupportDir).then((value) {
        // From https://stackoverflow.com/questions/13110542/how-to-get-a-timestamp-in-dart
        DateTime now = DateTime.now();
        otherMsg = 'timestamp: ${now.hour}:${now.minute}:${now.second}.${now.millisecond}';
      });
    });
  }

  Widget addProject() {
    /*
    return makeCmdButton("Add Project", Colors.blue, () {
      api.addProject(fileSystemPath: _applicationSupportDir).then((value) {
        updateProjects();
      });
    });
     */
    return makeCmdButton("Add Project", Colors.blue, () {
      addNewProject(Directory(_applicationSupportDir)).then((value) {
        _currentProject = value;
        updateProjects();
      });
    });
  }

  /*Widget renameProject() {

  }*/

  Widget addLabel() {
    return makeCmdButton("Add Label", Colors.green, () {
      api.addLabel(fileSystemPath: _applicationSupportDir, project: _currentProject).then((value) {
        updateLabels(_currentProject);
      });
    });
  }

  /*Widget renameLabel() {

  }*/

  void _listenToSocket(Socket socket) {
    socket.listen((data) {
      String msg = String.fromCharCodes(data);
      print("received $msg");
      if (msg == "cmd") {
        if (_requests.isEmpty) {
          socket.write("None");
        } else {
          socket.write(_requests.removeFirst());
        }
      } else {
        getProcessedData(msg);
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