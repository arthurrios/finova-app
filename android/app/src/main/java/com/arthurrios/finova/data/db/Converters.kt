package com.arthurrios.finova.data.db

import androidx.room.TypeConverter
import java.time.LocalDate
import java.time.YearMonth

/**
 * Dates are stored as epoch days and months as yyyymm integers. Neither depends on the time zone,
 * unlike the iOS epoch-second month anchors.
 */
class Converters {
    @TypeConverter fun fromDate(value: LocalDate?): Long? = value?.toEpochDay()
    @TypeConverter fun toDate(value: Long?): LocalDate? = value?.let(LocalDate::ofEpochDay)
    @TypeConverter fun fromMonth(value: YearMonth?): Int? = value?.let { it.year * 100 + it.monthValue }
    @TypeConverter fun toMonth(value: Int?): YearMonth? = value?.let { YearMonth.of(it / 100, it % 100) }
}
