package com.arthurrios.finova.ui.navigation

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.navArgument
import com.arthurrios.finova.ui.budgets.BudgetsScreen
import com.arthurrios.finova.ui.cards.AddCreditCardScreen
import com.arthurrios.finova.ui.profile.ProfileScreen
import com.arthurrios.finova.ui.profile.ProfileViewModel
import com.arthurrios.finova.ui.early.EarlyPaymentScreen
import com.arthurrios.finova.ui.early.EarlyPaymentViewModel
import com.arthurrios.finova.ui.statement.StatementDetailsScreen
import com.arthurrios.finova.ui.statement.StatementPaymentScreen
import com.arthurrios.finova.ui.statement.StatementPaymentViewModel
import com.arthurrios.finova.ui.statement.StatementDetailsViewModel
import com.arthurrios.finova.ui.cards.AddCreditCardViewModel
import com.arthurrios.finova.ui.cards.CreditCardsScreen
import com.arthurrios.finova.ui.cards.CreditCardsViewModel
import com.arthurrios.finova.ui.details.TransactionDetailsScreen
import com.arthurrios.finova.ui.details.TransactionDetailsViewModel
import com.arthurrios.finova.ui.budgets.BudgetsViewModel
import androidx.navigation.compose.composable
import androidx.compose.runtime.LaunchedEffect
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.arthurrios.finova.R
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.Biometrics
import com.arthurrios.finova.ui.dashboard.DashboardViewModel
import com.arthurrios.finova.appContainer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.ui.dashboard.DashboardScreen
import com.arthurrios.finova.ui.login.LoginRoute
import com.arthurrios.finova.ui.login.LoginViewModel
import com.arthurrios.finova.ui.register.RegisterRoute
import com.arthurrios.finova.ui.register.RegisterViewModel
import com.arthurrios.finova.ui.splash.SplashRoute
import com.arthurrios.finova.ui.splash.SplashViewModel
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Routes. Port of AppFlowController.swift. */
object Routes {
    const val SPLASH = "splash"
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val DASHBOARD = "dashboard"
    const val BUDGETS = "budgets?month={month}"
    const val DETAILS = "details/{id}"
    fun details(id: Long) = "details/$id"
    const val CARDS = "cards"
    const val PROFILE = "profile"
    const val SETTINGS = "settings"
    const val NOTIFICATION_SETTINGS = "settings/notifications"
    const val NOTIFICATIONS = "notifications"
    const val EARLY = "early/{id}"
    fun early(id: Long) = "early/$id"
    const val STATEMENT = "statement/{id}"
    fun statement(id: Long) = "statement/$id"
    const val PAY_STATEMENT = "statement/{id}/pay"
    fun payStatement(id: Long) = "statement/$id/pay"
    /** Add when id is 0, edit otherwise. */
    const val CARD_FORM = "cards/form?id={id}"
    fun cardForm(id: Long = 0) = "cards/form?id=$id"
    const val TAGS = "tags"
    const val TAG_EDIT = "tags/{id}"
    fun tagEdit(id: String) = "tags/$id"
    const val TAG_CATEGORIES = "tags/{id}/categories"
    fun tagCategories(id: String) = "tags/$id/categories"
    /** A category's allocation (or unallocated spending) in a month; month is yyyyMM. */
    const val ALLOCATION = "allocation/{category}/{month}"
    fun allocation(month: java.time.YearMonth, category: com.arthurrios.finova.domain.model.TransactionCategory) =
        "allocation/${category.key}/${month.year * 100 + month.monthValue}"
    fun budgets(month: java.time.YearMonth?) = "budgets?month=" + (month?.let { it.year * 100 + it.monthValue } ?: 0)
}

@Composable
fun FinovaNavHost(
    startRoute: String? = null,
    notificationTarget: String? = null,
    onNotificationTargetOpened: () -> Unit = {},
) {
    val navController = rememberNavController()
    val appContext = LocalContext.current.applicationContext
    val currentEntry by navController.currentBackStackEntryAsState()
    // A tapped notification opens its transaction or statement, on top of the dashboard, once the
    // user is past the splash (and its sign-in and biometric checks), as iOS does.
    LaunchedEffect(notificationTarget, currentEntry) {
        val target = com.arthurrios.finova.domain.notifications.NotificationTarget.decode(notificationTarget) ?: return@LaunchedEffect
        if (runCatching { navController.getBackStackEntry(Routes.DASHBOARD) }.isFailure) return@LaunchedEffect
        navController.navigate(target.route())
        onNotificationTargetOpened()
    }

    NavHost(navController = navController, startDestination = startRoute ?: Routes.SPLASH) {
        composable(
            Routes.SPLASH,
            // The splash animates into login itself, so the switch must not add its own fade.
            exitTransition = { ExitTransition.None },
        ) {
            val viewModel: SplashViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        SplashViewModel(
                            AuthRepository(appContext),
                            UserSettingsStore(appContext),
                            Biometrics(appContext),
                        )
                    }
                }
            )
            SplashRoute(
                viewModel = viewModel,
                onLogin = {
                    navController.navigate(Routes.LOGIN) {
                        popUpTo(Routes.SPLASH) { inclusive = true }
                    }
                },
                onDashboard = {
                    navController.navigate(Routes.DASHBOARD) {
                        popUpTo(Routes.SPLASH) { inclusive = true }
                    }
                },
            )
        }
        composable(
            Routes.LOGIN,
            enterTransition = {
                if (initialState.destination.route == Routes.SPLASH) EnterTransition.None else null
            },
        ) {
            val viewModel: LoginViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        LoginViewModel(
                            AuthRepository(appContext),
                            UserSettingsStore(appContext),
                            Biometrics(appContext),
                        )
                    }
                }
            )
            LoginRoute(
                viewModel = viewModel,
                onSignedIn = {
                    navController.navigate(Routes.DASHBOARD) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                },
                onRegister = { navController.navigate(Routes.REGISTER) },
            )
        }
        composable(Routes.REGISTER) {
            val viewModel: RegisterViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        RegisterViewModel(
                            AuthRepository(appContext),
                            UserSettingsStore(appContext),
                            Biometrics(appContext),
                        )
                    }
                }
            )
            RegisterRoute(
                viewModel = viewModel,
                onRegistered = {
                    navController.navigate(Routes.DASHBOARD) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                },
                onBackToLogin = { navController.popBackStack() },
            )
        }
        composable(Routes.DASHBOARD) {
            val viewModel: DashboardViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        DashboardViewModel(container.financeRepository(), container.settings, container.cardRepository(), container.allocationRepository(), container.tagRepository())
                    }
                }
            )
            val state by viewModel.state.collectAsStateWithLifecycle()
            // Read again each time the dashboard shows, so a photo picked in My Account appears.
            var avatar by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
            androidx.lifecycle.compose.LifecycleResumeEffect(Unit) {
                val container = appContext.appContainer
                avatar = container.profileImages.load(container.currentUid())?.asImageBitmap()
                onPauseOrDispose { }
            }
            val unread by appContext.appContainer.notificationHistory().items.collectAsStateWithLifecycle()
            // Asks once for permission to send reminders (Android 13+), as iOS asks at first launch.
            val askNotifications = androidx.activity.compose.rememberLauncherForActivityResult(
                androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
            ) { }
            androidx.compose.runtime.LaunchedEffect(Unit) {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU &&
                    androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.POST_NOTIFICATIONS) !=
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ) askNotifications.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            }
            DashboardScreen(
                state.copy(unreadNotifications = unread.count { !it.isRead }),
                viewModel,
                onOpenNotifications = { navController.navigate(Routes.NOTIFICATIONS) },
                avatar = avatar,
                onOpenProfile = { navController.navigate(Routes.PROFILE) },
                onOpenBudgets = { navController.navigate(Routes.budgets(it)) },
                onOpenTransaction = { navController.navigate(Routes.details(it)) },
                onCreateCard = { navController.navigate(Routes.cardForm()) },
                onOpenStatement = { navController.navigate(Routes.statement(it)) },
                onOpenAllocation = { month, category -> navController.navigate(Routes.allocation(month, category)) },
                onOpenTags = { navController.navigate(Routes.TAGS) },
                onEditTag = { navController.navigate(Routes.tagEdit(it)) },
            )
        }
        composable(Routes.TAGS) {
            com.arthurrios.finova.ui.tags.AllocationTagsScreen(
                tagsViewModel(),
                onBack = { navController.popBackStack() },
                onEdit = { navController.navigate(Routes.tagEdit(it)) },
            )
        }
        composable(Routes.TAG_EDIT) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            com.arthurrios.finova.ui.tags.AllocationTagEditScreen(
                tagsViewModel(),
                tagId = id,
                onBack = { navController.popBackStack() },
                onCategories = { navController.navigate(Routes.tagCategories(id)) },
            )
        }
        composable(Routes.TAG_CATEGORIES) { entry ->
            com.arthurrios.finova.ui.tags.AllocationTagCategoriesScreen(
                tagsViewModel(),
                tagId = entry.arguments?.getString("id").orEmpty(),
                onBack = { navController.popBackStack() },
            )
        }
        composable(
            Routes.ALLOCATION,
            arguments = listOf(navArgument("category") { type = NavType.StringType }, navArgument("month") { type = NavType.IntType }),
        ) { entry ->
            val key = entry.arguments?.getString("category").orEmpty()
            val packed = entry.arguments?.getInt("month") ?: 0
            val category = com.arthurrios.finova.domain.model.TransactionCategory.entries.firstOrNull { it.key == key }
                ?: com.arthurrios.finova.domain.model.TransactionCategory.entries.first()
            val month = java.time.YearMonth.of(packed / 100, (packed % 100).coerceIn(1, 12))
            val viewModel: com.arthurrios.finova.ui.allocation.AllocationDetailsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        com.arthurrios.finova.ui.allocation.AllocationDetailsViewModel(
                            container.financeRepository(), container.allocationRepository(), container.settings, category, month,
                        )
                    }
                }
            )
            com.arthurrios.finova.ui.allocation.AllocationDetailsScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onOpenTransaction = { navController.navigate(Routes.details(it)) },
            )
        }
        composable(Routes.STATEMENT, arguments = listOf(navArgument("id") { type = NavType.LongType })) { entry ->
            val id = entry.arguments?.getLong("id") ?: 0L
            val viewModel: StatementDetailsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        StatementDetailsViewModel(container.financeRepository(), container.cardRepository(), container.settings, id)
                    }
                }
            )
            StatementDetailsScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onOpenTransaction = { navController.navigate(Routes.details(it)) },
                onPay = { navController.navigate(Routes.payStatement(id)) },
            )
        }
        composable(Routes.PAY_STATEMENT, arguments = listOf(navArgument("id") { type = NavType.LongType })) { entry ->
            val id = entry.arguments?.getLong("id") ?: 0L
            val viewModel: StatementPaymentViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        StatementPaymentViewModel(container.financeRepository(), container.cardRepository(), container.settings, id)
                    }
                }
            )
            StatementPaymentScreen(viewModel, onBack = { navController.popBackStack() })
        }
        composable(Routes.DETAILS, arguments = listOf(navArgument("id") { type = NavType.LongType })) { entry ->
            val id = entry.arguments?.getLong("id") ?: 0L
            val viewModel: TransactionDetailsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        TransactionDetailsViewModel(container.financeRepository(), container.settings, id, container.cardRepository())
                    }
                }
            )
            TransactionDetailsScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onCreateCard = { navController.navigate(Routes.cardForm()) },
                onPayEarly = { navController.navigate(Routes.early(id)) },
                onOpenTransaction = { navController.navigate(Routes.details(it)) },
            )
        }
        composable(Routes.EARLY, arguments = listOf(navArgument("id") { type = NavType.LongType })) { entry ->
            val id = entry.arguments?.getLong("id") ?: 0L
            val viewModel: EarlyPaymentViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        EarlyPaymentViewModel(container.financeRepository(), container.cardRepository(), container.settings, id)
                    }
                }
            )
            EarlyPaymentScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                // The selection is replaced by the payment made, so back returns to the transaction
                // the user started from, as on iOS.
                onPaid = { paymentId ->
                    navController.navigate(Routes.details(paymentId)) { popUpTo(Routes.EARLY) { inclusive = true } }
                },
            )
        }
        composable(
            Routes.BUDGETS,
            arguments = listOf(navArgument("month") { type = NavType.IntType; defaultValue = 0 }),
        ) { entry ->
            val raw = entry.arguments?.getInt("month") ?: 0
            val month = if (raw > 0) java.time.YearMonth.of(raw / 100, raw % 100) else null
            val viewModel: BudgetsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        BudgetsViewModel(container.financeRepository(), container.settings, month)
                    }
                }
            )
            BudgetsScreen(viewModel, onBack = { navController.popBackStack() }, onManageTags = { navController.navigate(Routes.TAGS) })
        }
        composable(Routes.PROFILE) {
            val viewModel: ProfileViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
                        ProfileViewModel(appContext.appContainer, "Finova v${info.versionName} (${info.longVersionCode})")
                    }
                }
            )
            ProfileScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onCreditCards = { navController.navigate(Routes.CARDS) },
                onSettings = { navController.navigate(Routes.SETTINGS) },
                onLoggedOut = {
                    navController.navigate(Routes.LOGIN) { popUpTo(0) { inclusive = true } }
                },
            )
        }
        composable(Routes.SETTINGS) {
            val viewModel: com.arthurrios.finova.ui.settings.SettingsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
                        com.arthurrios.finova.ui.settings.SettingsViewModel(appContext.appContainer, info.versionName.orEmpty())
                    }
                }
            )
            com.arthurrios.finova.ui.settings.SettingsScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onNotifications = { navController.navigate(Routes.NOTIFICATION_SETTINGS) },
                onSignedOut = { navController.navigate(Routes.LOGIN) { popUpTo(0) { inclusive = true } } },
            )
        }
        composable(Routes.NOTIFICATION_SETTINGS) {
            com.arthurrios.finova.ui.notifications.NotificationSettingsScreen(appContext.appContainer.notificationSettings, onBack = { navController.popBackStack() })
        }
        composable(Routes.NOTIFICATIONS) {
            com.arthurrios.finova.ui.notifications.NotificationHistoryScreen(
                appContext.appContainer.notificationHistory(),
                onBack = { navController.popBackStack() },
                onOpen = { navController.navigate(it.route()) },
            )
        }
        composable(Routes.CARDS) {
            val viewModel: CreditCardsViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        CreditCardsViewModel(container.cardRepository(), container.settings)
                    }
                }
            )
            CreditCardsScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onAdd = { navController.navigate(Routes.cardForm()) },
                onEdit = { navController.navigate(Routes.cardForm(it)) },
            )
        }
        composable(
            Routes.CARD_FORM,
            arguments = listOf(navArgument("id") { type = NavType.LongType; defaultValue = 0L }),
        ) { entry ->
            val id = entry.arguments?.getLong("id")?.takeIf { it > 0 }
            val viewModel: AddCreditCardViewModel = viewModel(
                factory = viewModelFactory {
                    initializer {
                        val container = appContext.appContainer
                        AddCreditCardViewModel(container.cardRepository(), container.financeRepository(), container.settings, id)
                    }
                }
            )
            AddCreditCardScreen(
                viewModel,
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() },
            )
        }
    }
}

@Composable
private fun tagsViewModel(): com.arthurrios.finova.ui.tags.TagsViewModel {
    val appContext = LocalContext.current.applicationContext
    return viewModel(factory = viewModelFactory { initializer { com.arthurrios.finova.ui.tags.TagsViewModel(appContext.appContainer.tagRepository()) } })
}

private fun com.arthurrios.finova.domain.notifications.NotificationTarget.route(): String = when (this) {
    is com.arthurrios.finova.domain.notifications.NotificationTarget.Transaction -> Routes.details(id)
    is com.arthurrios.finova.domain.notifications.NotificationTarget.Statement -> Routes.statement(id)
}
