package com.pranith.finance.personal_finance

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val backupFolderRequestCode = 9201
    private var backupFolderResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finkeep/app_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "openAppInfo" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finkeep/backup_folder")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickTree") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (backupFolderResult != null) {
                    result.error("PICKER_OPEN", "The folder picker is already open.", null)
                    return@setMethodCallHandler
                }
                backupFolderResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }
                try {
                    startActivityForResult(intent, backupFolderRequestCode)
                } catch (error: Exception) {
                    backupFolderResult = null
                    result.error("PICKER_UNAVAILABLE", "The system folder picker could not open.", null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != backupFolderRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = backupFolderResult
        backupFolderResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        val treeUri = data.data!!
        val requiredFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val returnedFlags = data.flags and requiredFlags
        if (returnedFlags != requiredFlags) {
            result?.error("FOLDER_ACCESS_DENIED", "Read and write access was not granted.", null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(treeUri, requiredFlags)
            val permission = contentResolver.persistedUriPermissions.firstOrNull {
                it.uri == treeUri
            }
            if (permission?.isReadPermission != true || permission.isWritePermission != true) {
                result?.error("FOLDER_ACCESS_DENIED", "Folder access could not be preserved.", null)
                return
            }
            result?.success(treeUri.toString())
        } catch (error: SecurityException) {
            result?.error("FOLDER_ACCESS_DENIED", "Folder access could not be preserved.", null)
        }
    }
}
