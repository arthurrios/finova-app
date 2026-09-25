package com.arthurrios.finova.ui.navigation

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
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.arthurrios.finova.R
import com.arthurrios.finova.auth.AuthRepository
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.security.Biometrics
import com.arthurrios.finova.ui.login.LoginRoute
import com.arthurrios.finova.ui.login.LoginViewModel
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Routes. Port of AppFlowController.swift; screens not yet ported show a placeholder. */
object Routes {
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val DASHBOARD = "dashboard"
}

@Composable
fun FinovaNavHost() {
    val navController = rememberNavController()
    val appContext = LocalContext.current.applicationContext

    NavHost(navController = navController, startDestination = Routes.LOGIN) {
        composable(Routes.LOGIN) {
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
        composable(Routes.REGISTER) { PlaceholderScreen("Register") }
        composable(Routes.DASHBOARD) { PlaceholderScreen("Dashboard") }
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
