package com.arthurrios.finova.domain.importer

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/** What a file ACTUALLY is, by its leading bytes. Port of DetectedFileFormat. */
enum class DetectedFileFormat {
    /** A ZIP container: .xlsx, .ods, .numbers. */
    ZipContainer,
    /** OLE2 compound document: legacy .xls, what Brazilian banks most often hand out. */
    Ole2Document,
    Pdf,
    Rtf,
    /** Decodes as text but is dense with control characters. */
    OtherBinary,
    Text,
}

/**
 * Magic bytes, checked BEFORE decoding, so a spreadsheet or PDF is named as such instead of being
 * parsed into line noise. Port of FileFormatSniffer.swift.
 */
object FileFormatSniffer {
    private const val BINARY_CONTROL_RATIO = 0.02

    fun detect(data: ByteArray): DetectedFileFormat {
        fun startsWith(vararg bytes: Int) = data.size >= bytes.size && bytes.indices.all { data[it] == bytes[it].toByte() }
        if (startsWith(0x50, 0x4B)) return DetectedFileFormat.ZipContainer
        if (startsWith(0xD0, 0xCF, 0x11, 0xE0)) return DetectedFileFormat.Ole2Document
        if (startsWith('%'.code, 'P'.code, 'D'.code, 'F'.code)) return DetectedFileFormat.Pdf
        if (startsWith('{'.code, '\\'.code, 'r'.code, 't'.code, 'f'.code)) return DetectedFileFormat.Rtf
        // A UTF-16 or UTF-32 byte-order mark is text, even though half its bytes are NUL. (iOS counts
        // those NULs as control bytes and turns Excel's "Unicode text" export away.)
        if (startsWith(0xFF, 0xFE) || startsWith(0xFE, 0xFF) || startsWith(0x00, 0x00, 0xFE, 0xFF)) return DetectedFileFormat.Text

        val sample = data.copyOf(minOf(data.size, 4096))
        if (sample.isEmpty()) return DetectedFileFormat.Text
        val controls = sample.count { val b = it.toInt() and 0xFF; b < 0x09 || (b in 0x0E..0x1F) || b == 0x7F }
        return if (controls.toDouble() / sample.size > BINARY_CONTROL_RATIO) DetectedFileFormat.OtherBinary else DetectedFileFormat.Text
    }
}

/**
 * Bytes to text, for files nobody validated. Port of EncodingSniffer.swift. The order is the design:
 * Latin-1 never fails, so a UTF-8 export with one damaged byte must NOT fall back to it, or every
 * accented word in the file becomes mojibake for good. UTF-8 shape is measured first.
 */
object EncodingSniffer {
    data class Result(val text: String, val encoding: String, val wasLossy: Boolean)

    private const val UTF8_CONFIDENCE = 0.99

    fun decode(data: ByteArray): Result? {
        if (data.isEmpty()) return null
        // 1. A byte-order mark is proof, not evidence.
        decodeByteOrderMark(data)?.let { return it }
        // 2. Strict UTF-8, the common case.
        strict(data, Charsets.UTF_8)?.let { return Result(stripBom(it), "UTF-8", false) }
        // 3. Not strictly valid, but how close? A 99% UTF-8 file is UTF-8 with damage.
        if (utf8Validity(data) >= UTF8_CONFIDENCE) return Result(stripBom(String(data, Charsets.UTF_8)), "UTF-8", true)
        // 4. A single-byte encoding. Windows-1252 first: a superset of Latin-1 for printable text, and
        //    what Excel on Windows writes.
        for (name in listOf("windows-1252", "ISO-8859-1")) {
            val text = strict(data, Charset.forName(name)) ?: continue
            // The signature of UTF-8 bytes read one at a time: we just got it backwards.
            if (looksLikeMisreadUtf8(text)) return Result(stripBom(String(data, Charsets.UTF_8)), "UTF-8", true)
            return Result(stripBom(text), if (name == "windows-1252") "Windows-1252" else "ISO-8859-1", false)
        }
        return null
    }

    private fun decodeByteOrderMark(data: ByteArray): Result? {
        fun startsWith(vararg bytes: Int) = data.size >= bytes.size && bytes.indices.all { data[it] == bytes[it].toByte() }
        return when {
            startsWith(0xEF, 0xBB, 0xBF) -> {
                val body = data.copyOfRange(3, data.size)
                val text = strict(body, Charsets.UTF_8)
                Result(text ?: String(body, Charsets.UTF_8), "UTF-8", text == null)
            }
            // UTF-32 marks begin like UTF-16 ones, so they are ruled out first.
            startsWith(0xFF, 0xFE, 0x00, 0x00) -> strict(data.copyOfRange(4, data.size), Charset.forName("UTF-32LE"))?.let { Result(it, "UTF-32", false) }
            startsWith(0x00, 0x00, 0xFE, 0xFF) -> strict(data.copyOfRange(4, data.size), Charset.forName("UTF-32BE"))?.let { Result(it, "UTF-32", false) }
            startsWith(0xFF, 0xFE) -> strict(data.copyOfRange(2, data.size), Charsets.UTF_16LE)?.let { Result(stripBom(it), "UTF-16", false) }
            startsWith(0xFE, 0xFF) -> strict(data.copyOfRange(2, data.size), Charsets.UTF_16BE)?.let { Result(stripBom(it), "UTF-16", false) }
            else -> null
        }
    }

    private fun strict(data: ByteArray, charset: Charset): String? = try {
        charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(data)).toString()
    } catch (_: CharacterCodingException) {
        null
    }

    /** A BOM decoded as content glues U+FEFF to the first header cell and costs the first column. */
    private fun stripBom(text: String) = text.removePrefix("﻿")

    /**
     * The share of multi-byte sequence starts followed by well-formed continuation bytes. Pure ASCII
     * scores 1; Latin-1 text with accents scores near 0.
     */
    fun utf8Validity(data: ByteArray): Double {
        var sequences = 0
        var valid = 0
        var i = 0
        while (i < data.size) {
            val b = data[i].toInt() and 0xFF
            if (b < 0x80) { i++; continue }
            val width = when (b) {
                in 0xC2..0xDF -> 2
                in 0xE0..0xEF -> 3
                in 0xF0..0xF4 -> 4
                else -> { sequences++; i++; continue }
            }
            sequences++
            val end = i + width
            if (end <= data.size && (1 until width).all { (data[i + it].toInt() and 0xC0) == 0x80 }) {
                valid++
                i = end
            } else {
                i++
            }
        }
        return if (sequences == 0) 1.0 else valid.toDouble() / sequences
    }

    /** `Ã` or `Â` followed by a Latin-1 supplement character: UTF-8 bytes read one at a time. */
    fun looksLikeMisreadUtf8(text: String): Boolean {
        for (i in 1 until text.length) {
            val previous = text[i - 1]
            val code = text[i].code
            if ((previous == 'Ã' || previous == 'Â') && (code in 0xA0..0xBF || code in 0x80..0x9F)) return true
        }
        return false
    }
}
