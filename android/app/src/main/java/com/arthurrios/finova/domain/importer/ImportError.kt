package com.arthurrios.finova.domain.importer

import java.text.Normalizer

/**
 * A failure that stops the whole file. Per-row failures are [RowError] and live on the plan, so a bad
 * line never costs the user the other nine hundred. Port of ImportError.swift.
 */
sealed class ImportError : Exception() {
    data object CannotReadFile : ImportError()
    data class FileTooLarge(val bytes: Int, val limit: Int) : ImportError()
    data class TooManyRows(val count: Int, val limit: Int) : ImportError()
    data object EmptyFile : ImportError()

    /** The bytes did not decode as text under any candidate encoding. */
    data object NotTextual : ImportError()
    data class UnterminatedQuote(val line: Int) : ImportError()

    /** No column looked like a date, or none like an amount. */
    data object NoUsableColumns : ImportError()

    /**
     * The file is not a CSV at all: a spreadsheet, PDF or other binary picked by mistake. Detected
     * from magic bytes BEFORE decoding, so the message names the real format.
     */
    data class WrongFileFormat(val detected: DetectedFileFormat, val encrypted: Boolean = false) : ImportError()

    /** The file decoded as text but never resolved into columns under any delimiter. */
    data class NotTabular(val details: String) : ImportError()

    /** Dates read as dd/MM on some rows and as MM/dd on others. */
    data object InconsistentDateFormat : ImportError()
    data object Cancelled : ImportError()
}

/**
 * Accent- and case-folded, for matching only (iOS `normalizedForSearch`). "Ação" and "ACAO" fold to
 * the same "acao".
 */
fun String.normalizedForSearch(): String =
    Normalizer.normalize(this, Normalizer.Form.NFD).replace(CombiningMarks, "").lowercase()

private val CombiningMarks = Regex("\\p{Mn}+")
