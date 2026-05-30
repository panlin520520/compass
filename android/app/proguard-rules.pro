# Flutter / Android release
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Gson / reflection used by some plugins
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# Geolocator / Play Services (if present)
-dontwarn com.google.android.gms.**

# OkHttp (transitive)
-dontwarn okhttp3.**
-dontwarn okio.**
