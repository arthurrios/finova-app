package com.arthurrios.finova.ui.splash

import android.graphics.Color
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.login.LoginHeroHeight
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.Spacing
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The same size the system launch screen draws the mark at (res/drawable/splash_icon.xml). */
private val LogoSize = 178.dp

/** Port of SplashViewController / SplashView on iOS. */
@Composable
fun SplashRoute(
    viewModel: SplashViewModel,
    onLogin: () -> Unit,
    onDashboard: () -> Unit,
) {
    val step by viewModel.step.collectAsStateWithLifecycle()
    val activity = LocalActivity.current as? FragmentActivity
    val title = stringResource(R.string.biometric_prompt_title)
    val reason = stringResource(R.string.biometric_prompt_reason)
    val cancel = stringResource(R.string.alert_cancel)

    // White status bar icons on the dark splash; back to the default when it leaves.
    DisposableEffect(activity) {
        activity?.enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT))
        onDispose { activity?.enableEdgeToEdge() }
    }

    // The system launch screen already showed the logo, so it starts visible (iOS fades it in).
    // Hold it for the same 0.6s iOS waits before deciding.
    LaunchedEffect(Unit) {
        delay(600)
        viewModel.decide()
    }

    LaunchedEffect(step) {
        when (step) {
            SplashStep.AskBiometrics ->
                if (activity != null) viewModel.unlock(activity, title, reason, cancel) else onLogin()
            SplashStep.GoToLoginNow -> onLogin()
            SplashStep.GoToDashboard -> onDashboard()
            SplashStep.Waiting, SplashStep.GoToLogin -> Unit
        }
    }

    SplashScreen(animateToLogin = step == SplashStep.GoToLogin, onAnimationDone = onLogin)
}

/**
 * The dark gradient with the logo. [animateToLogin] plays the iOS hand-off: the logo rises and
 * grows into the login hero, the hero fades in, and the dark background fades away.
 */
@Composable
fun SplashScreen(animateToLogin: Boolean, onAnimationDone: () -> Unit) {
    val rise = remember { Animatable(0f) }
    val heroAlpha = remember { Animatable(0f) }
    val darkAlpha = remember { Animatable(1f) }
    // The system launch screen is flat Gray700; ease the gradient in so the switch is not a jump.
    val gradientAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) { gradientAlpha.animateTo(1f, tween(durationMillis = 500)) }

    BoxWithConstraints(Modifier.fillMaxSize().background(FinovaColors.Gray100)) {
        val density = LocalDensity.current
        val topInset = with(density) { WindowInsets.safeDrawing.getTop(this).toDp() }
        // Distance from the screen center to the center of the login hero.
        val riseBy = maxHeight / 2 - (topInset + LoginHeroHeight / 2)

        LaunchedEffect(animateToLogin) {
            if (!animateToLogin) return@LaunchedEffect
            rise.animateTo(1f, tween(durationMillis = 1000, easing = EaseOut))
            launch { heroAlpha.animateTo(1f, tween(durationMillis = 1000)) }
            darkAlpha.animateTo(0f, tween(durationMillis = 1000))
            onAnimationDone()
        }

        Box(
            Modifier
                .fillMaxSize()
                .alpha(darkAlpha.value)
                .background(FinovaColors.Gray700),
        ) {
            Box(Modifier.fillMaxSize().alpha(gradientAlpha.value).background(SplashGradient))
        }
        Image(
            painter = painterResource(R.drawable.login_image),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .safeDrawingPadding()
                .fillMaxWidth()
                .padding(horizontal = Spacing.S3)
                .height(LoginHeroHeight)
                .alpha(heroAlpha.value),
        )
        Image(
            painter = painterResource(R.drawable.finova_logo),
            contentDescription = null,
            modifier = Modifier
                .align(Alignment.Center)
                .size(LogoSize)
                .graphicsLayer {
                    translationY = -riseBy.toPx() * rise.value
                    val scale = 1f + 0.15f * rise.value
                    scaleX = scale
                    scaleY = scale
                    // The hero has its own copy of the logo; hand over to it as it fades in.
                    alpha = 1f - heroAlpha.value
                },
        )
    }
}

/** Colors.gradientBlack on iOS: Gray700 to #2D2D2D, nearly left to right. */
private val SplashGradient = Brush.horizontalGradient(
    colors = listOf(FinovaColors.Gray700, FinovaColors.GradientBlackEnd),
)
