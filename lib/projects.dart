import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as dartui;

const String projectDirName = "projects";

String filenameFromPath(String path) {
  return path.split("/").last;
}

Future<List<String>> listProjects(Directory fileSystemPath) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  List<String> result = projectDir.listSync().map((f) => filenameFromPath(f.path)).toList();
  return result.isEmpty ? ["No projects"] : result;
}

Future<Directory> getProjectDir(Directory fileSystemPath) async {
  for (FileSystemEntity file in fileSystemPath.listSync()) {
    if (file.path.endsWith(projectDirName)) {
      return Directory(file.path);
    }
  }
  Directory projectDir = Directory("${fileSystemPath.path}/$projectDirName");
  return await projectDir.create();
}

Future<List<String>> listLabels(Directory fileSystemPath, String project) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  for (FileSystemEntity file in projectDir.listSync()) {
    if (file.path.endsWith(project)) {
      return Directory(file.path).listSync().map((f) => filenameFromPath(f.path)).toList();
    }
  }
  return ["No labels"];
}

Future<String> addNewProject(Directory fileSystemPath) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  String name = await inventName("proj", projectDir);
  Directory newDir = Directory("${projectDir.path}/$name");
  Directory createdDir = await newDir.create();
  return createdDir.path.endsWith(name) ? name : "Failed to create";
}

Future<void> renameExistingProject(Directory fileSystemPath, String oldName, String newName) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  Directory namedDir = Directory("${projectDir.path}/$oldName");
  namedDir.rename("${projectDir.path}/$newName");
}

Future<String> inventName(String prefix, Directory nameDir) async {
  int nameNum = nameDir.listSync().length + 1;
  return "$prefix$nameNum";
}

Future<String> addNewLabel(Directory fileSystemPath, String project) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  for (FileSystemEntity file in projectDir.listSync()) {
    if (file.path.endsWith(project)) {
      Directory thisProjectDir = Directory(file.path);
      String name = await inventName("label", thisProjectDir);
      Directory newDir = Directory("${thisProjectDir.path}/$name");
      Directory createdDir = await newDir.create();
      return createdDir.path.endsWith(name) ? name : "Failed to create";
    }
  }
  return "Project $project does not exist";
}

Future<void> renameExistingLabel(Directory fileSystemPath, String project, String oldName, String newName) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  Directory namedDir = Directory("${projectDir.path}/$project/$oldName");
  namedDir.rename("${projectDir.path}/$project/$newName");
}

// How to do this: https://stackoverflow.com/questions/69600988/flutter-convert-ui-image-to-a-file
Future<String> saveImage(dartui.Image img, Directory fileSystemPath, String project, String label) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  final data = await img.toByteData(format: dartui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List();
  DateTime now = DateTime.now();
  String photoName = "ph_${now.hour}_${now.minute}_${now.second}_${now.millisecond}.png";
  File file = File("${projectDir.path}/$project/$label/$photoName");
  file = await file.writeAsBytes(bytes, flush: true);
  return photoName;
}

Future<List<dartui.Image>> loadImages(Directory fileSystemPath, String project, String label) async {
  Directory projectDir = await getProjectDir(fileSystemPath);
  Directory labelDir = Directory("${projectDir.path}/$project/$label");
  List<dartui.Image> result = [];
  for (FileSystemEntity f in labelDir.listSync()) {
    File file = File(f.path);
    Uint8List data = await file.readAsBytes();
    // From https://stackoverflow.com/a/64906539/906268
    dartui.Codec codec = await dartui.instantiateImageCodec(data);
    dartui.FrameInfo frame = await codec.getNextFrame();
    result.add(frame.image);
  }
  return result;
}