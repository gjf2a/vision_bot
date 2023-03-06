import 'dart:io';

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