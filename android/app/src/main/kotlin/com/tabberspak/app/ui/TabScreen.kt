package com.tabberspak.app.ui

import androidx.compose.runtime.Composable
import com.tabberspak.app.AppModel

// TA4 replaces this with its port of the iPhone's TabScreen.swift.

@Composable
fun TabScreen(model: AppModel) = PendingScreen(model, "Tab")
