# Keep rules for the day R8 is switched on in build.gradle (minifyEnabled).
# Nothing here is active while minifyEnabled = false.

# Flutter embedding — entry points are found reflectively by the engine.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Play Services keep their own consumer rules, but Firestore and
# Functions serialize model classes reflectively; keep annotated members.
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
}

# Crashlytics needs line numbers and source files to symbolicate.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Flutter's embedding references Play Core's SplitCompatApplication to support
# deferred components. PlaySphere ships a single, non-deferred module, so the
# Play Core library is not a dependency and the reference is dead — but R8
# treats an unresolved reference as a hard error, not a warning. This is the
# one rule every Flutter app needs before minification will complete.
-dontwarn com.google.android.play.core.**
