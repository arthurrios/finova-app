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
                        DashboardViewModel(container.financeRepository(), container.settings)
                    }
                }
            )
            val state by viewModel.state.collectAsStateWithLifecycle()
            DashboardScreen(state, viewModel, onOpenBudgets = { navController.navigate(Routes.budgets(it)) })
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
