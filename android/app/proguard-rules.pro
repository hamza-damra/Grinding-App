# Release builds are minified by R8.
#
# mobile_scanner / ML Kit barcode scanning: ML Kit wires its barcode scanner
# together by reflection (ComponentRegistrar classes named in the merged
# manifest). mobile_scanner's own consumer rule keeps only `com.google.mlkit.*`
# (one level), so R8 renamed/stripped the barcode internals and
# BarcodeScanning.getClient() threw a NullPointerException on every start.
# The scanner reported that as a generic camera error («تعذر تشغيل الكاميرا»)
# although the camera permission was granted — debug builds were not affected.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-dontwarn com.google.mlkit.**
