package com.deskflowlabs.channeltimelineviewer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.deskflowlabs.channeltimelineviewer.ui.theme.ChannelTimelineTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ChannelTimelineTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    Placeholder()
                }
            }
        }
    }
}

@Composable
private fun Placeholder() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text = "Channel Timeline Viewer", style = MaterialTheme.typography.titleLarge)
    }
}
