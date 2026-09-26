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
import androidx.navigation.compose.rememberNavController
import com.arthurrios.finova.R
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.Biometrics
import com.arthurrios.finova.ui.dashboard.DashboardViewModel
import com.arthurrios.finova.appContainer
import androidx.compose.runtime.getValue
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

/** Routes. Port of AppFlowController.swift; screens not yet ported show a placeholder. */
object Routes {
    const val SPLASH = "splash"
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val DASHBOARD = "dashboard"
    const val BUDGETS = "budgets?month={month}"
    const val DETAILS = "details/{id}"
    fun details(id: Long) = "details/$id"
    const val CARDS = "cards"
    const val STATEMENT = "statement/{id}"
    fun statement(id: Long) = "statement/$id"
    const val PAY_STATEMENT = "statement/{id}/pay"
    fun payStatement(id: Long) = "statement/$id/pay"
    /** Add when id is 0, edit otherwise. */
    const val CARD_FORM = "cards/form?id={id}"
    fun cardForm(id: Long = 0) = "cards/form?id=$id"
    fun budgets(month: java.time.YearMonth?) = "budgets?month=" + (month?.let { it.year * 100 + it.monthValue } ?: 0)
}

@Composable
fun FinovaNavHost(startRoute: String? = null) {
    val navController = rememberNavController()
    val appContext = LocalContext.current.applicationContext

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
                        DashboardViewModel(container.financeRepository(), container.settings, container.cardRepository())
                    }
                }
            )
            val state by viewModel.state.collectAsStateWithLifecycle()
            DashboardScreen(
                state,
                viewModel,
                onOpenBudgets = { navController.navigate(Routes.budgets(it)) },
                onOpenTransaction = { navController.navigate(Routes.details(it)) },
                onCreateCard = { navController.navigate(Routes.cardForm()) },
                onOpenStatement = { navController.navigate(Routes.statement(it)) },
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
            BudgetsScreen(viewModel, onBack = { navController.popBackStack() })
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
private fun PlaceholderScreen(name: String) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(FinovaColors.Gray100)
            .safeDrawingPadding()
            .padding(Spacing.S6),
        verticalArrangement = Arrangement.spacedBy(Spacing.S2),
    ) {
        Text(text = name, style = FinovaType.TitleLG, color = FinovaColors.MainMagenta)
        Text(text = stringResource(R.string.placeholder_body), style = FinovaType.TextSM, color = FinovaColors.Gray600)
    }
}
