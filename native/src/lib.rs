// Both commands from the present (native) directory:
//
// To bridge:
// flutter_rust_bridge_codegen --rust-input src\api.rs --dart-output ..\lib\bridge_generated.dart --dart-decl-output ..\lib\bridge_definitions.dart
//
// To compile, after generating bridge:
// cargo ndk -o ..\android\app\src\main\jniLibs build --release

mod api;
mod bridge_generated;
mod image_proc;
