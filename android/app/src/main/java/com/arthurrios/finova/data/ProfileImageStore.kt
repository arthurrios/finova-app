package com.arthurrios.finova.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import java.io.File
import java.security.MessageDigest

/**
 * The profile photo, one per account, kept in app storage (SecureLocalDataManager.saveProfileImage
 * on iOS). The file name is a hash so it does not expose the account id.
 */
class ProfileImageStore(private val context: Context) {
    private fun file(uid: String): File {
        val digest = MessageDigest.getInstance("SHA-256").digest(uid.toByteArray())
        val name = digest.take(8).joinToString("") { "%02x".format(it) }
        return File(File(context.filesDir, "profile").apply { mkdirs() }, "$name.jpg")
    }

    fun delete(uid: String) {
        file(uid).delete()
    }

    fun load(uid: String): Bitmap? = file(uid).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }

    /** Copies the picked picture in, scaled down to at most 512 px, since it only shows as an avatar. */
    fun save(uid: String, picked: Uri): Bitmap? = runCatching {
        val bitmap = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) decodeScaled(picked) else decodeScaledLegacy(picked)
        file(uid).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap
    }.getOrNull()

    @androidx.annotation.RequiresApi(android.os.Build.VERSION_CODES.P)
    private fun decodeScaled(picked: Uri): Bitmap =
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, picked)) { decoder, info, _ ->
            val longest = maxOf(info.size.width, info.size.height)
            if (longest > MAX_SIDE) {
                val scale = MAX_SIDE.toFloat() / longest
                decoder.setTargetSize((info.size.width * scale).toInt(), (info.size.height * scale).toInt())
            }
        }

    /** Android 8 has no ImageDecoder: read the size first, then decode at a power-of-two scale. */
    private fun decodeScaledLegacy(picked: Uri): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(picked).use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return context.contentResolver.openInputStream(picked).use { BitmapFactory.decodeStream(it, null, options) }
            ?: error("Could not read the picture")
    }

    private companion object {
        const val MAX_SIDE = 512
    }
}
