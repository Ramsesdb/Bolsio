# ML Kit text recognition — we only bundle the Latin recognizer, but the
# plugin's initialize() references all script-specific recognizer classes.
# Tell R8 these absent classes are expected.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.vision.text.** { *; }

# image_picker / permission_handler use reflection for plugin registration
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.plugins.**

# speech_to_text — plugin channel classes referenced via reflection from
# native side; R8 shrinker will otherwise strip them in --release and the
# `listen()` call becomes a no-op with no error emitted.
-keep class com.csdcorp.speech_to_text.** { *; }
-dontwarn com.csdcorp.speech_to_text.**
