# Add project specific ProGuard rules here.
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep Flutter engine classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep specific services for Wire app
-keep class dev.sagarm.wire.** { *; }

# WebRTC
-keep class org.webrtc.** { *; }

# WebSocket
-keep class io.flutter.plugin.web_socket_channel.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Permissions
-keep class com.baseflow.permissionhandler.** { *; }

# Battery Plus
-keep class dev.fluttercommunity.plus.battery.** { *; }

# Bluetooth
-keep class com.boskokg.flutter_blue_plus.** { *; }

# Optimize but keep important stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
