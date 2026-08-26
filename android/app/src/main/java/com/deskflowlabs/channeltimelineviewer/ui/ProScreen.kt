package com.deskflowlabs.channeltimelineviewer.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.billing.ProBillingManager
import com.deskflowlabs.channeltimelineviewer.billing.ProEntitlementStore

/**
 * Pro（買い切り）の説明と購入。
 *
 * 表示で必ず守ること（Play の要件でもあり、利用者への説明としても必要）:
 * - 買い切りであること／サブスクリプションではないこと
 * - Pro で解放されるのは「複数チャンネル保存」であること
 * - 無料でも1チャンネルは主要機能込みで使えること
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProScreen(
    billing: ProBillingManager,
    entitlement: ProEntitlementStore,
    onBack: () -> Unit,
) {
    val isPro by entitlement.isPro.collectAsStateWithLifecycle()
    val price by billing.priceText.collectAsStateWithLifecycle()
    val isBusy by billing.isBusy.collectAsStateWithLifecycle()
    val messageRes by billing.messageRes.collectAsStateWithLifecycle()
    val activity = LocalContext.current.findActivity()

    // 画面を開くたびに購入状態と価格を読み直す（他端末で買った直後でも合うように）。
    LaunchedEffect(Unit) { billing.refresh() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.pro_name)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_close))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.pro_headline),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                stringResource(R.string.pro_benefit_multichannel),
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                stringResource(R.string.pro_notsubscription),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            SectionCard(
                header = stringResource(R.string.pro_freefeatures_header),
                body = stringResource(R.string.pro_freefeatures_body),
                extra = stringResource(R.string.pro_free_summary),
            )
            SectionCard(
                header = stringResource(R.string.pro_profeatures_header),
                body = stringResource(R.string.pro_profeatures_body),
            )

            if (isPro) {
                Text(
                    stringResource(R.string.pro_owned),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            } else {
                Button(
                    onClick = { activity?.let(billing::purchase) },
                    enabled = !isBusy && activity != null,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (isBusy) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp).padding(end = 4.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(
                        price?.let { stringResource(R.string.pro_buy_format, it) }
                            ?: stringResource(R.string.pro_buy)
                    )
                }
                if (price == null) {
                    Text(
                        stringResource(R.string.pro_price_loading),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            TextButton(
                onClick = billing::restore,
                enabled = !isBusy,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.pro_restore))
            }
            Text(
                stringResource(R.string.pro_restore_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            messageRes?.let { res ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(stringResource(res), style = MaterialTheme.typography.bodyMedium)
                        TextButton(onClick = billing::clearMessage) {
                            Text(stringResource(R.string.common_close))
                        }
                    }
                }
            }

            Text(
                stringResource(R.string.disclaimer_short),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 24.dp),
            )
        }
    }
}

@Composable
private fun SectionCard(header: String, body: String, extra: String? = null) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(header, style = MaterialTheme.typography.titleSmall)
            Text(body, style = MaterialTheme.typography.bodySmall)
            extra?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Compose の Context から Activity を辿る。
 * 購入フロー（Activity が要る）と、プレイヤーの全画面表示（重ねる先が要る）で使う。
 */
internal fun Context.findActivity(): Activity? {
    var context: Context? = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}
