package com.zaskarstartup.zaskia

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal class FluxChannel(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "zaskia/flux")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "generate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.argument<List<String>>("args")
            val output = call.argument<String>("output")
            if (args == null || output == null) {
                result.error("arguments", "Faltan los parámetros de FLUX.", null)
                return@setMethodCallHandler
            }
            executor.execute { generate(args, File(output), result) }
        }
    }

    private fun generate(args: List<String>, output: File, result: MethodChannel.Result) {
        try {
            val manager = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memory = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
            if (memory.lowMemory || memory.availMem < 5L * 1024 * 1024 * 1024) {
                main.post { result.error("memory", "FLUX necesita al menos 5 GiB de RAM disponible en esta versión experimental.", null) }
                return
            }
            val executable = File(app.applicationInfo.nativeLibraryDir, "libzaskia_flux.so")
            val log = File(output.parentFile, "flux.log")
            val process = ProcessBuilder(listOf(executable.absolutePath) + args)
                .redirectErrorStream(true)
                .redirectOutput(log)
                .start()
            if (!process.waitFor(30, TimeUnit.MINUTES)) {
                process.destroyForcibly()
                process.waitFor()
                main.post { result.error("timeout", "FLUX superó el tiempo de generación.", null) }
                return
            }
            if (process.exitValue() != 0 || !output.isFile || output.length() == 0L) {
                main.post { result.error("engine", "FLUX no generó la imagen. Revisa que los tres archivos correspondan a klein 4B.", null) }
                return
            }
            main.post { result.success(null) }
        } catch (error: Exception) {
            main.post { result.error("engine", "No se pudo ejecutar el motor FLUX en este dispositivo.", null) }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
