package com.arthurrios.finova.data.db

import android.content.Context
import androidx.room.AutoMigration
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import java.security.MessageDigest

/**
 * One database file per signed-in user, like iOS keeps `UserData/<uid>/`. Allocations, cards and
 * tags join here in later slices, so nothing leaks between accounts on the same phone.
 *
 * Nothing is released yet, but a debug build may already hold data, so every schema change is a
 * real migration: version 2 adds the card tables.
 */
@Database(
    entities = [
        TransactionEntity::class,
        BudgetEntity::class,
        RecurringExclusionEntity::class,
        UserSettingsEntity::class,
        CreditCardEntity::class,
        StatementEntity::class,
    ],
    version = 2,
    exportSchema = true,
    autoMigrations = [AutoMigration(from = 1, to = 2)],
)
@TypeConverters(Converters::class)
abstract class FinovaDatabase : RoomDatabase() {
    abstract fun transactions(): TransactionDao
    abstract fun budgets(): BudgetDao
    abstract fun recurringExclusions(): RecurringExclusionDao
    abstract fun userSettings(): UserSettingsDao
    abstract fun creditCards(): CreditCardDao
    abstract fun statements(): StatementDao

    companion object {
        fun open(context: Context, uid: String): FinovaDatabase =
            Room.databaseBuilder(context.applicationContext, FinovaDatabase::class.java, fileName(uid)).build()

        /** A hash, so the file name does not expose the account id. */
        fun fileName(uid: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(uid.toByteArray())
            return "finova_" + digest.take(8).joinToString("") { "%02x".format(it) } + ".db"
        }
    }
}
