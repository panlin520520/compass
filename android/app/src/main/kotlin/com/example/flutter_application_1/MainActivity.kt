package com.example.flutter_application_1

import android.app.Activity
import android.content.ContentValues
import android.media.AudioManager
import android.media.ToneGenerator
import android.content.pm.PackageManager.ResolveInfoFlags
import android.os.Build
import android.os.Environment
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "liji_image_saver"
    private val vibrationChannelName = "haptic_feedback"
    private val appUtilsChannelName = "compass_app_utils"
    private var galleryPickPendingResult: MethodChannel.Result? = null
    private var pickVisualMediaLauncher: ActivityResultLauncher<PickVisualMediaRequest>? = null

    companion object {
        private const val GALLERY_PICK_REQUEST_CODE = 48291
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == GALLERY_PICK_REQUEST_CODE) {
            val pending = galleryPickPendingResult
            galleryPickPendingResult = null
            if (pending != null) {
                if (resultCode == Activity.RESULT_OK) {
                    val uri = data?.data
                    pending.success(
                        if (uri != null) copyGalleryUriToCache(uri) else null
                    )
                } else {
                    pending.success(null)
                }
                return
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pickVisualMediaLauncher = registerForActivityResult(
            ActivityResultContracts.PickVisualMedia(),
        ) { uri ->
            val pending = galleryPickPendingResult
            galleryPickPendingResult = null
            pending?.success(
                if (uri != null) copyGalleryUriToCache(uri) else null,
            )
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "saveImageToGallery" -> {
                        val bytes = call.argument<ByteArray>("imageBytes")
                        val name = call.argument<String>("name") ?: "liji_${System.currentTimeMillis()}.png"
                        if (bytes == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val ok = saveImageToGallery(bytes, name)
                        result.success(ok)
                    }

                    "shareImage" -> {
                        val bytes = call.argument<ByteArray>("imageBytes")
                        val name = call.argument<String>("name") ?: "liji_${System.currentTimeMillis()}.png"
                        if (bytes == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val ok = shareImage(bytes, name)
                        result.success(ok)
                    }

                    "pickImageFromGallery" -> launchSystemGalleryPicker(result)

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUtilsChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "canOpenUrl" -> {
                        val url = call.argument<String>("url")
                        result.success(url != null && canOpenExternalUrl(url))
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        result.success(url != null && openExternalUrl(url))
                    }
                    else -> result.notImplemented()
                }
            }

        // 振动反馈通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, vibrationChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "vibrate" -> {
                        val duration = call.argument<Int>("duration") ?: 200
                        val amplitude = call.argument<Int>("amplitude") ?: 255
                        vibrate(duration, amplitude)
                        result.success(true)
                    }
                    "playSound" -> {
                        playClickSound()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun vibrate(duration: Int, amplitude: Int) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0+ 使用 VibrationEffect
                val effect = VibrationEffect.createOneShot(
                    duration.toLong(),
                    amplitude.coerceIn(1, 255)
                )
                vibrator.vibrate(effect)
            } else {
                // Android 8.0 以下使用旧 API
                @Suppress("DEPRECATION")
                vibrator.vibrate(duration.toLong())
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playClickSound() {
        try {
            // 使用 ToneGenerator 播放系统提示音
            // TONE_PROP_BEEP 是一个短促的提示音，类似点击声
            val toneGenerator = ToneGenerator(AudioManager.STREAM_SYSTEM, 100)
            toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP, 50) // 50ms 的短促提示音
            
            // 延迟后释放资源
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                toneGenerator.release()
            }, 100)
        } catch (e: Exception) {
            e.printStackTrace()
            // 如果 ToneGenerator 失败，尝试使用系统声音
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                // 播放系统点击声（需要系统支持）
                audioManager.playSoundEffect(AudioManager.FX_KEY_CLICK)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }

    /** 优先调起各品牌系统图库；鸿蒙/Android 13+ 优先系统 Photo Picker。 */
    private fun launchSystemGalleryPicker(result: MethodChannel.Result) {
        galleryPickPendingResult = result

        // Android 13+ / 多数鸿蒙机型：系统相册选择器（不依赖图库包名解析）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                pickVisualMediaLauncher?.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                )
                return
            } catch (_: Exception) {
                // 继续尝试品牌图库
            }
        }

        val intents = buildGalleryPickIntents()
        if (intents.isNotEmpty()) {
            tryLaunchGalleryIntents(intents, 0, result)
            return
        }

        launchFallbackGalleryPicker(result)
    }

    private fun launchFallbackGalleryPicker(result: MethodChannel.Result) {
        val fallbacks = listOf(
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                type = "image/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
        )
        for (intent in fallbacks) {
            if (resolveActivityCompat(intent) == null) continue
            try {
                galleryPickPendingResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(intent, GALLERY_PICK_REQUEST_CODE)
                return
            } catch (_: Exception) {
            }
        }
        galleryPickPendingResult = null
        result.error("NO_GALLERY", "未找到系统图库应用", null)
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun resolveActivityCompat(intent: Intent): ResolveInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.resolveActivity(
                intent,
                ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
    }

    private fun queryIntentActivitiesCompat(intent: Intent): List<ResolveInfo> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
        }
    }

    private fun tryLaunchGalleryIntents(
        intents: List<Intent>,
        index: Int,
        result: MethodChannel.Result,
    ) {
        if (index >= intents.size) {
            launchFallbackGalleryPicker(result)
            return
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intents[index], GALLERY_PICK_REQUEST_CODE)
        } catch (e: Exception) {
            tryLaunchGalleryIntents(intents, index + 1, result)
        }
    }

    /** 会打开「最近」/文档选择器的包名，必须排除。 */
    private fun isExcludedPickerPackage(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return pkg == "com.android.documentsui" ||
            pkg == "com.google.android.documentsui" ||
            pkg == "com.android.providers.media.module" ||
            pkg.contains("documentsui") ||
            pkg.contains("filemanager") ||
            pkg.contains("fileexplorer") ||
            pkg.contains("hidisk") ||
            pkg.contains("downloadui")
    }

    private fun isGalleryLikePackage(packageName: String): Boolean {
        val pkg = packageName.lowercase()
        return pkg.contains("gallery") ||
            pkg.contains("photos") ||
            pkg.contains("media.gallery") ||
            pkg == "com.huawei.photos" ||
            pkg == "com.huawei.gallery" ||
            pkg == "com.hihonor.photos"
    }

    private fun galleryPackageScore(packageName: String): Int {
        return when (packageName) {
            "com.huawei.photos" -> 200
            "com.huawei.gallery" -> 195
            "com.hihonor.photos" -> 190
            "com.miui.gallery" -> 180
            "com.oppo.gallery3d", "com.coloros.gallery3d" -> 170
            "com.vivo.gallery" -> 165
            "com.sec.android.gallery3d" -> 160
            "com.oneplus.gallery" -> 155
            "com.google.android.apps.photos" -> 150
            "com.android.gallery3d" -> 140
            "com.meizu.media.gallery" -> 135
            else -> if (isGalleryLikePackage(packageName)) 80 else 0
        }
    }

    private fun isComponentAvailable(component: ComponentName): Boolean {
        return try {
            packageManager.getActivityInfo(component, PackageManager.MATCH_DEFAULT_ONLY)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun intentForComponent(component: ComponentName, mediaUri: Uri): Intent {
        return Intent(Intent.ACTION_PICK, mediaUri).apply {
            this.component = component
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            applyHuaweiGalleryExtras(this, component.packageName)
        }
    }

    /** 华为/鸿蒙图库：尽量进入「相册」而非「最近」页 */
    private fun applyHuaweiGalleryExtras(intent: Intent, packageName: String?) {
        val pkg = packageName ?: return
        if (!pkg.startsWith("com.huawei") && !pkg.startsWith("com.hihonor")) return
        intent.putExtra("inner_album", true)
        intent.putExtra("pick_only", true)
        intent.putExtra("show_camera_item", false)
        intent.putExtra("from_package", applicationContext.packageName)
    }

    private fun intentsForPackage(pkg: String, mediaUri: Uri): List<Intent> {
        if (!isPackageInstalled(pkg)) return emptyList()
        val out = mutableListOf<Intent>()

        // 华为/鸿蒙部分机型注册的自定义 Action
        if (pkg.startsWith("com.huawei") || pkg.startsWith("com.hihonor")) {
            listOf(
                "com.huawei.photos.intent.action.PICK_IMAGE",
                "com.huawei.gallery.action.GET_IMAGE",
                "android.intent.action.HW_GALLERY",
                "com.huawei.hmos.photos.action.PICK",
            ).forEach { action ->
                val custom = Intent(action).apply {
                    setPackage(pkg)
                    type = "image/*"
                    data = mediaUri
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    applyHuaweiGalleryExtras(this, pkg)
                }
                if (resolveActivityCompat(custom) != null || pkg.startsWith("com.huawei")) {
                    out.add(custom)
                }
            }
        }

        val pickIntent = Intent(Intent.ACTION_PICK, mediaUri).apply {
            setPackage(pkg)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            applyHuaweiGalleryExtras(this, pkg)
        }
        out.add(pickIntent)

        val getIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            setPackage(pkg)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            applyHuaweiGalleryExtras(this, pkg)
        }
        out.add(getIntent)

        return out
    }

    private fun buildGalleryPickIntents(): List<Intent> {
        val mediaUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val result = mutableListOf<Intent>()
        val seen = mutableSetOf<String>()

        fun add(intent: Intent?) {
            if (intent == null) return
            val key = "${intent.component?.packageName}/${intent.component?.className}/${intent.action}"
            if (seen.add(key)) {
                result.add(intent)
            }
        }

        // 1) 华为/鸿蒙：显式 Activity（resolveActivity 常为 false，但组件仍可用）
        val explicitComponents = listOf(
            ComponentName("com.huawei.photos", "com.huawei.photos.app.GalleryMain"),
            ComponentName("com.huawei.photos", "com.huawei.photos.app.MainActivity"),
            ComponentName("com.huawei.photos", "com.huawei.gallery.app.Gallery"),
            ComponentName("com.huawei.photos", "com.huawei.photos.app.PhotoMain"),
            ComponentName("com.huawei.photos", "com.huawei.photos.app.PickerActivity"),
            ComponentName("com.huawei.photos", "com.huawei.photos.app.picker.PhotoPickerActivity"),
            ComponentName("com.huawei.gallery", "com.huawei.gallery.app.GalleryMain"),
            ComponentName("com.hihonor.photos", "com.hihonor.photos.app.GalleryMain"),
        )
        for (cn in explicitComponents) {
            if (isComponentAvailable(cn) || isPackageInstalled(cn.packageName)) {
                add(intentForComponent(cn, mediaUri))
            }
        }

        // 2) 已知图库包名（华为/鸿蒙优先）
        val galleryPackages = listOf(
            "com.huawei.photos",
            "com.huawei.gallery",
            "com.hihonor.photos",
            "com.miui.gallery",
            "com.oppo.gallery3d",
            "com.coloros.gallery3d",
            "com.vivo.gallery",
            "com.sec.android.gallery3d",
            "com.oneplus.gallery",
            "com.google.android.apps.photos",
            "com.android.gallery3d",
            "com.meizu.media.gallery",
        )
        for (pkg in galleryPackages) {
            intentsForPackage(pkg, mediaUri).forEach { add(it) }
        }

        // 3) 扫描系统已注册的 PICK/GET_CONTENT，选图库类应用（排除「最近」文档 UI）
        val queryBases = listOf(
            Intent(Intent.ACTION_PICK, mediaUri),
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
            },
        )
        val resolveList = mutableListOf<ResolveInfo>()
        for (base in queryBases) {
            resolveList.addAll(queryIntentActivitiesCompat(base))
        }
        resolveList
            .map { it.activityInfo }
            .distinctBy { "${it.packageName}/${it.name}" }
            .filter { !isExcludedPickerPackage(it.packageName) }
            .filter { galleryPackageScore(it.packageName) > 0 }
            .sortedByDescending { galleryPackageScore(it.packageName) }
            .forEach { info ->
                add(
                    Intent(Intent.ACTION_PICK, mediaUri).apply {
                        setClassName(info.packageName, info.name)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        applyHuaweiGalleryExtras(this, info.packageName)
                    },
                )
            }

        // 不使用无包名/无组件的通用 PICK，鸿蒙上会落到「最近」文档选择器
        return result
    }

    private fun copyGalleryUriToCache(uri: Uri): String? {
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            val ext = when (contentResolver.getType(uri)) {
                "image/png" -> ".png"
                "image/webp" -> ".webp"
                "image/gif" -> ".gif"
                else -> ".jpg"
            }
            val cacheFile = File(cacheDir, "picked_${System.currentTimeMillis()}$ext")
            FileOutputStream(cacheFile).use { output ->
                input.copyTo(output)
            }
            input.close()
            cacheFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun shareImage(pngBytes: ByteArray, name: String): Boolean {
        return try {
            val resolver = applicationContext.contentResolver
            val fileName = if (name.endsWith(".png")) name else "$name.png"

            // 先插入到相册（与保存逻辑类似），得到一个 content:// Uri
            val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + File.separator + "LijiCompassShare"
                    )
                }
                resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            } else {
                val picturesDir =
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                val dir = File(picturesDir, "LijiCompassShare").apply {
                    if (!exists()) mkdirs()
                }
                val file = File(dir, fileName)
                resolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    ContentValues().apply {
                        put(MediaStore.MediaColumns.DATA, file.absolutePath)
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                    }
                )
            }

            if (uri == null) return false

            resolver.openOutputStream(uri).use { stream ->
                if (stream == null) return false
                stream.write(pngBytes)
                stream.flush()
            }

            // 调用系统分享面板（微信好友、朋友圈、QQ、收藏等由系统列出）
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(shareIntent, "分享测量图片")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)

            true
        } catch (e: Exception) {
            e.printStackTrace()
            try {
                Toast.makeText(applicationContext, "发送失败: ${e.message}", Toast.LENGTH_SHORT).show()
            } catch (_: Exception) {
            }
            false
        }
    }
    private fun saveImageToGallery(pngBytes: ByteArray, name: String): Boolean {
        return try {
            val resolver = applicationContext.contentResolver
            val fileName = if (name.endsWith(".png")) name else "$name.png"

            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + File.separator + "LijiCompass"
                    )
                }
                resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            } else {
                // Android 9 及以下，直接写入公共图片目录
                val picturesDir =
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                val dir = File(picturesDir, "LijiCompass").apply {
                    if (!exists()) mkdirs()
                }
                val file = File(dir, fileName)
                resolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    ContentValues().apply {
                        put(MediaStore.MediaColumns.DATA, file.absolutePath)
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                    }
                )
            }

            if (uri == null) return false

            val output: OutputStream? = resolver.openOutputStream(uri)
            output.use { stream ->
                if (stream == null) return false
                stream.write(pngBytes)
                stream.flush()
            }

            true
        } catch (e: Exception) {
            e.printStackTrace()
            try {
                Toast.makeText(applicationContext, "保存失败: ${e.message}", Toast.LENGTH_SHORT).show()
            } catch (_: Exception) {
            }
            false
        }
    }

    private fun canOpenExternalUrl(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                .isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    private fun openExternalUrl(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
