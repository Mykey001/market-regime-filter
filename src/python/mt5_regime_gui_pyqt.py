#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║  ML Market Regime Trading System - PyQt5 Dashboard                          ║
║  Professional Real-Time Market Regime Detection and Trade Filtering         ║
║                                                                              ║
║  Version:     1.0.0                                                          ║
║  Platform:    MetaTrader 5                                                   ║
║  Framework:   PyQt5 with Dark Mode Theme                                     ║
║  ML Model:    Bayesian Gaussian Mixture Model (8 components)                ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

DESCRIPTION:
    This application provides a professional dark-mode dashboard for monitoring
    market regimes in real-time. It connects to MetaTrader 5, computes 14
    technical features, predicts market regime using ML, and filters EA trades
    via socket communication.

FEATURES:
    • Real-time regime detection (8 market states)
    • Socket server for EA integration (port 9090)
    • Configurable regime filters (allow/block trading)
    • Directional filter (trade with trend only)
    • Statistics panel (all 14 features visible)
    • Professional dark theme interface

USAGE:
    python mt5_regime_gui_pyqt.py

REQUIREMENTS:
    - Python 3.8+
    - PyQt5, MetaTrader5, pandas, numpy, scikit-learn, matplotlib, joblib
    - MT5 running and logged in
    - Model files: market_regime_gmm.pkl, scaler.pkl

AUTHOR:
    ML Trading System Developer

DATE:
    June 2026
"""

import json
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import sys
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QLabel, QPushButton, QComboBox, 
                             QLineEdit, QGroupBox, QCheckBox, QGridLayout,
                             QScrollArea, QTabWidget, QTableWidget, QTableWidgetItem,
                             QSplitter, QFrame, QRadioButton, QButtonGroup, QMessageBox)
from PyQt5.QtCore import QTimer, Qt, QThread, pyqtSignal
from PyQt5.QtGui import QFont, QPalette, QColor
import matplotlib
matplotlib.use("Qt5Agg")

from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure

import threading
import joblib
import os
import time
import socket

from feature_engine import compute_all_features, get_feature_matrix, FEATURE_NAMES

# ============================================================
# CONFIGURATION
# ============================================================

DEFAULT_SYMBOL = "XAUUSD"
DEFAULT_TIMEFRAME = mt5.TIMEFRAME_M5
DEFAULT_BARS = 800
REFRESH_SECONDS = 10

# Socket server configuration
SOCKET_HOST = "127.0.0.1"
SOCKET_PORT = 9090
SOCKET_ENABLED = True

# ============================================================
# LOAD SAVED MODEL AND SCALER
# ============================================================

# Get project root directory (2 levels up from src/python/)
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(os.path.dirname(script_dir))

# Model paths (search in models/ folder and fallback to script dir for backward compatibility)
MODEL_PATHS = [
    os.path.join(project_root, "models", "market_regime_gmm.pkl"),
    os.path.join(project_root, "models", "market_regime_model.pkl"),
    os.path.join(script_dir, "market_regime_model.pkl"),  # Fallback
    os.path.join(script_dir, "market_regime_gmm.pkl"),    # Fallback
]

SCALER_PATHS = [
    os.path.join(project_root, "models", "scaler.pkl"),
    os.path.join(project_root, "models", "regime_scaler.pkl"),
    os.path.join(script_dir, "regime_scaler.pkl"),  # Fallback
    os.path.join(script_dir, "scaler.pkl"),         # Fallback
]
METADATA_PATH = os.path.join(project_root, "models", "regime_metadata.json")

model = None
model_path = None
for path in MODEL_PATHS:
    if os.path.exists(path):
        try:
            model = joblib.load(path)
            model_path = path
            break
        except Exception:
            continue

scaler = None
scaler_path = None
for path in SCALER_PATHS:
    if os.path.exists(path):
        try:
            scaler = joblib.load(path)
            scaler_path = path
            break
        except Exception:
            continue

metadata = {}
if os.path.exists(METADATA_PATH):
    try:
        with open(METADATA_PATH, "r") as f:
            metadata = json.load(f)
    except Exception:
        metadata = {}

if model is None or scaler is None:
    raise Exception("Failed loading saved regime model or scaler.")

REGIME_MAP = metadata.get("regime_map", {})

# ============================================================
# REGIME LABELS - Named Regime 1-8
# ============================================================

REGIME_NAMES = {
    0: "Regime 1 - Low Vol Bullish",
    1: "Regime 2 - Neutral Consolidation",
    2: "Regime 3 - High Vol Bearish",
    3: "Regime 4 - Low Vol Bearish",
    4: "Regime 5 - Extreme Vol Spike",
    5: "Regime 6 - Crisis Mode",
    6: "Regime 7 - High Vol Mixed",
    7: "Regime 8 - Bearish Trending"
}

REGIME_COLORS = {
    0: "#00ff00", 1: "#ffa500", 2: "#ff0000", 3: "#9370db",
    4: "#ff1493", 5: "#dc143c", 6: "#ffd700", 7: "#ff4500"
}

REGIME_FILTER_CONFIG = {
    0: True, 1: True, 2: False, 3: True,
    4: False, 5: False, 6: True, 7: True,
}

REGIME_DIRECTION = {
    0: "bullish", 1: "neutral", 2: "bearish", 3: "bearish",
    4: "neutral", 5: "bearish", 6: "neutral", 7: "bearish",
}

USE_DIRECTIONAL_FILTER = True
DIRECTIONAL_FILTER_MODE = "strict"

# ============================================================
# MT5 FETCHER
# ============================================================

def fetch_market_data(symbol, timeframe, bars=DEFAULT_BARS):
    if not mt5.initialize():
        raise Exception(f"MT5 initialize failed: {mt5.last_error()}")
    
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        mt5.shutdown()
        raise Exception(f"Symbol {symbol} not found")
    
    if not symbol_info.visible:
        mt5.symbol_select(symbol, True)
    
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)
    mt5.shutdown()
    
    if rates is None:
        raise Exception("No rates received")
    
    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    return df

# ============================================================
# PREDICTION ENGINE
# ============================================================

def get_model_probabilities(model, X):
    if hasattr(model, "predict_proba"):
        return model.predict_proba(X)
    if hasattr(model, "score_samples"):
        result = model.score_samples(X)
        if isinstance(result, tuple) and len(result) == 2:
            return result[1]
    raise ValueError("Model does not support probability estimates")

def predict_regime(df):
    df_feat = compute_all_features(df)
    X, valid_df = get_feature_matrix(df_feat, drop_na=True)
    
    if len(valid_df) == 0:
        raise Exception("Not enough historical bars to compute features.")
    
    latest = valid_df.iloc[[-1]]
    X_latest = latest[FEATURE_NAMES].values.astype(np.float64)
    X_scaled = scaler.transform(X_latest)
    
    regime_id = model.predict(X_scaled)[0]
    probabilities = get_model_probabilities(model, X_scaled)[0]
    confidence = float(np.max(probabilities) * 100)
    
    regime_name = REGIME_MAP.get(str(regime_id), {}).get(
        "name", REGIME_NAMES.get(regime_id, f"Regime {regime_id}"))
    
    return {
        "regime_id": regime_id,
        "regime_name": regime_name,
        "confidence": confidence,
        "probabilities": probabilities,
        "price": latest["close"].iloc[0],
        "time": latest.index[0],
        "featured_df": valid_df,
        "features": {name: float(latest[name].iloc[0]) for name in FEATURE_NAMES if name in latest.columns}
    }

# ============================================================
# DARK MODE STYLESHEET
# ============================================================

DARK_STYLESHEET = """
QMainWindow, QWidget {
    background-color: #1e1e1e;
    color: #e0e0e0;
}
QGroupBox {
    background-color: #2d2d2d;
    border: 2px solid #3d3d3d;
    border-radius: 5px;
    margin-top: 10px;
    font-weight: bold;
    padding-top: 10px;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 10px;
    padding: 0 5px;
    color: #4da6ff;
}
QLabel {
    color: #e0e0e0;
}
QPushButton {
    background-color: #0d47a1;
    color: white;
    border: none;
    padding: 8px 15px;
    border-radius: 4px;
    font-weight: bold;
}
QPushButton:hover {
    background-color: #1565c0;
}
QPushButton:pressed {
    background-color: #0a3d91;
}
QLineEdit, QComboBox {
    background-color: #3d3d3d;
    color: #e0e0e0;
    border: 1px solid #5d5d5d;
    padding: 5px;
    border-radius: 3px;
}
QCheckBox {
    color: #e0e0e0;
    spacing: 5px;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
}
QCheckBox::indicator:unchecked {
    background-color: #3d3d3d;
    border: 2px solid #5d5d5d;
}
QCheckBox::indicator:checked {
    background-color: #0d47a1;
    border: 2px solid #1565c0;
}
QRadioButton {
    color: #e0e0e0;
}
QTableWidget {
    background-color: #2d2d2d;
    color: #e0e0e0;
    gridline-color: #3d3d3d;
    border: 1px solid #3d3d3d;
}
QTableWidget::item {
    padding: 5px;
}
QHeaderView::section {
    background-color: #1e1e1e;
    color: #4da6ff;
    padding: 5px;
    border: 1px solid #3d3d3d;
    font-weight: bold;
}
QTabWidget::pane {
    border: 1px solid #3d3d3d;
    background-color: #2d2d2d;
}
QTabBar::tab {
    background-color: #2d2d2d;
    color: #e0e0e0;
    padding: 8px 15px;
    border: 1px solid #3d3d3d;
}
QTabBar::tab:selected {
    background-color: #0d47a1;
    color: white;
}
"""

# ============================================================
# MAIN GUI CLASS
# ============================================================

class RegimeDashboard(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Market Regime Dashboard - PyQt5 Dark Mode")
        self.setGeometry(100, 100, 1600, 1000)
        
        # Data
        self.current_regime = None
        self.current_confidence = 0.0
        self.current_probabilities = None
        self.last_update_time = None
        self.current_features = {}
        self.running = True
        
        # Socket server
        self.socket_server = None
        self.server_running = False
        
        # Timeframe mapping
        self.timeframe_map = {
            "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15, "M30": mt5.TIMEFRAME_M30,
            "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4,
            "D1": mt5.TIMEFRAME_D1
        }
        
        self.init_ui()
        
        # Start auto-refresh timer
        self.timer = QTimer()
        self.timer.timeout.connect(self.auto_refresh)
        self.timer.start(REFRESH_SECONDS * 1000)
        
        # Start socket server
        if SOCKET_ENABLED:
            self.start_socket_server()
        
        # Initial update
        self.manual_refresh()
    
    def init_ui(self):
        """Initialize the UI components."""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        
        # Top control panel
        main_layout.addWidget(self.create_control_panel())
        
        # Main splitter for left and right sections
        splitter = QSplitter(Qt.Horizontal)
        
        # Left side - Charts and Live Data
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.addWidget(self.create_live_data_panel())
        left_layout.addWidget(self.create_chart_panel())
        splitter.addWidget(left_widget)
        
        # Right side - Tabs for Config and Analysis
        right_tabs = QTabWidget()
        right_tabs.addTab(self.create_probability_panel(), "Probabilities")
        right_tabs.addTab(self.create_filter_config_panel(), "Filter Config")
        right_tabs.addTab(self.create_statistics_panel(), "Statistics")
        right_tabs.addTab(self.create_directional_filter_panel(), "Directional Filter")
        splitter.addWidget(right_tabs)
        
        splitter.setSizes([1000, 600])
        main_layout.addWidget(splitter)
    
    def create_control_panel(self):
        """Create top control panel with symbol, timeframe, and refresh."""
        group = QGroupBox("Market Controls")
        layout = QHBoxLayout()
        
        layout.addWidget(QLabel("Symbol:"))
        self.symbol_input = QLineEdit(DEFAULT_SYMBOL)
        self.symbol_input.setMaximumWidth(150)
        layout.addWidget(self.symbol_input)
        
        layout.addWidget(QLabel("Timeframe:"))
        self.timeframe_combo = QComboBox()
        self.timeframe_combo.addItems(self.timeframe_map.keys())
        self.timeframe_combo.setCurrentText("M5")
        self.timeframe_combo.setMaximumWidth(100)
        layout.addWidget(self.timeframe_combo)
        
        self.refresh_btn = QPushButton("Refresh Now")
        self.refresh_btn.clicked.connect(self.manual_refresh)
        layout.addWidget(self.refresh_btn)
        
        layout.addStretch()
        
        self.server_status_label = QLabel("Server: STOPPED")
        self.server_status_label.setStyleSheet("color: #ffa500; font-weight: bold;")
        layout.addWidget(self.server_status_label)
        
        self.ea_status_label = QLabel("EA: Not Connected")
        self.ea_status_label.setStyleSheet("color: #808080;")
        layout.addWidget(self.ea_status_label)
        
        group.setLayout(layout)
        return group
    
    def create_live_data_panel(self):
        """Create live market analysis panel."""
        group = QGroupBox("Live Market Analysis")
        layout = QGridLayout()
        
        # Create labels
        labels = [
            ("Price:", 0), ("Regime:", 1), ("Confidence:", 2),
            ("Trade Status:", 3), ("Last Update:", 4), ("Model:", 5)
        ]
        
        self.price_label = QLabel("--")
        self.regime_label = QLabel("--")
        self.regime_label.setFont(QFont("Arial", 16, QFont.Bold))
        self.confidence_label = QLabel("--")
        self.trade_status_label = QLabel("--")
        self.trade_status_label.setFont(QFont("Arial", 12, QFont.Bold))
        self.update_time_label = QLabel("--")
        self.model_label = QLabel(os.path.basename(model_path) if model_path else "Unknown")
        
        value_labels = [
            self.price_label, self.regime_label, self.confidence_label,
            self.trade_status_label, self.update_time_label, self.model_label
        ]
        
        for (text, row), value_label in zip(labels, value_labels):
            label = QLabel(text)
            label.setFont(QFont("Arial", 10, QFont.Bold))
            layout.addWidget(label, row, 0, Qt.AlignRight)
            layout.addWidget(value_label, row, 1, Qt.AlignLeft)
        
        layout.setColumnStretch(1, 1)
        group.setLayout(layout)
        return group
    
    def create_chart_panel(self):
        """Create chart panel with price and RSI."""
        group = QGroupBox("Market Charts")
        layout = QVBoxLayout()
        
        self.figure = Figure(figsize=(10, 6), facecolor='#1e1e1e')
        self.canvas = FigureCanvas(self.figure)
        
        self.ax_price = self.figure.add_subplot(211, facecolor='#2d2d2d')
        self.ax_rsi = self.figure.add_subplot(212, facecolor='#2d2d2d')
        
        # Style the axes
        for ax in [self.ax_price, self.ax_rsi]:
            ax.tick_params(colors='#e0e0e0')
            ax.spines['bottom'].set_color('#3d3d3d')
            ax.spines['top'].set_color('#3d3d3d')
            ax.spines['left'].set_color('#3d3d3d')
            ax.spines['right'].set_color('#3d3d3d')
            ax.xaxis.label.set_color('#e0e0e0')
            ax.yaxis.label.set_color('#e0e0e0')
            ax.title.set_color('#4da6ff')
        
        layout.addWidget(self.canvas)
        group.setLayout(layout)
        return group
    
    def create_probability_panel(self):
        """Create probability table for all regimes."""
        widget = QWidget()
        layout = QVBoxLayout()
        
        self.prob_table = QTableWidget()
        self.prob_table.setColumnCount(3)
        self.prob_table.setHorizontalHeaderLabels(["Regime", "Name", "Probability"])
        self.prob_table.horizontalHeader().setStretchLastSection(True)
        self.prob_table.setEditTriggers(QTableWidget.NoEditTriggers)
        
        layout.addWidget(self.prob_table)
        widget.setLayout(layout)
        return widget
    
    def create_filter_config_panel(self):
        """Create filter configuration panel."""
        widget = QWidget()
        layout = QVBoxLayout()
        
        # Instructions
        info_label = QLabel("✓ Check to ALLOW trading  |  ✗ Uncheck to BLOCK trading")
        info_label.setFont(QFont("Arial", 10, QFont.Bold))
        info_label.setStyleSheet("color: #4da6ff;")
        layout.addWidget(info_label)
        
        # Checkboxes for each regime
        self.regime_checkboxes = {}
        checkbox_layout = QGridLayout()
        
        for i, (regime_id, name) in enumerate(REGIME_NAMES.items()):
            cb = QCheckBox(name)
            cb.setChecked(REGIME_FILTER_CONFIG.get(regime_id, True))
            cb.stateChanged.connect(lambda state, rid=regime_id: self.on_filter_changed(rid, state))
            self.regime_checkboxes[regime_id] = cb
            checkbox_layout.addWidget(cb, i // 2, i % 2)
        
        layout.addLayout(checkbox_layout)
        
        # Preset buttons
        preset_layout = QHBoxLayout()
        
        allow_all_btn = QPushButton("Allow All")
        allow_all_btn.clicked.connect(self.preset_allow_all)
        preset_layout.addWidget(allow_all_btn)
        
        block_all_btn = QPushButton("Block All")
        block_all_btn.clicked.connect(self.preset_block_all)
        preset_layout.addWidget(block_all_btn)
        
        conservative_btn = QPushButton("Conservative Mode")
        conservative_btn.clicked.connect(self.preset_conservative)
        preset_layout.addWidget(conservative_btn)
        
        layout.addLayout(preset_layout)
        layout.addStretch()
        
        widget.setLayout(layout)
        return widget
    
    def create_statistics_panel(self):
        """Create statistical analysis panel."""
        widget = QWidget()
        layout = QVBoxLayout()
        
        stats_label = QLabel("Feature Statistics")
        stats_label.setFont(QFont("Arial", 12, QFont.Bold))
        stats_label.setStyleSheet("color: #4da6ff;")
        layout.addWidget(stats_label)
        
        self.stats_table = QTableWidget()
        self.stats_table.setColumnCount(2)
        self.stats_table.setHorizontalHeaderLabels(["Feature", "Value"])
        self.stats_table.horizontalHeader().setStretchLastSection(True)
        self.stats_table.setEditTriggers(QTableWidget.NoEditTriggers)
        
        layout.addWidget(self.stats_table)
        widget.setLayout(layout)
        return widget
    
    def create_directional_filter_panel(self):
        """Create directional filter configuration panel."""
        widget = QWidget()
        layout = QVBoxLayout()
        
        # Enable checkbox
        self.dir_filter_checkbox = QCheckBox("Enable Directional Filter (Block counter-trend trades)")
        self.dir_filter_checkbox.setChecked(USE_DIRECTIONAL_FILTER)
        self.dir_filter_checkbox.setFont(QFont("Arial", 10, QFont.Bold))
        self.dir_filter_checkbox.stateChanged.connect(self.on_dir_filter_changed)
        layout.addWidget(self.dir_filter_checkbox)
        
        # Mode selection
        mode_label = QLabel("Filter Mode:")
        mode_label.setFont(QFont("Arial", 10, QFont.Bold))
        layout.addWidget(mode_label)
        
        self.mode_group = QButtonGroup()
        self.strict_radio = QRadioButton("Strict - Only with trend")
        self.neutral_radio = QRadioButton("Allow Neutral - Both ways in neutral regimes")
        self.disabled_radio = QRadioButton("Disabled - Allow all directions")
        
        self.mode_group.addButton(self.strict_radio, 0)
        self.mode_group.addButton(self.neutral_radio, 1)
        self.mode_group.addButton(self.disabled_radio, 2)
        
        if DIRECTIONAL_FILTER_MODE == "strict":
            self.strict_radio.setChecked(True)
        elif DIRECTIONAL_FILTER_MODE == "allow_neutral":
            self.neutral_radio.setChecked(True)
        else:
            self.disabled_radio.setChecked(True)
        
        self.strict_radio.toggled.connect(self.on_dir_mode_changed)
        self.neutral_radio.toggled.connect(self.on_dir_mode_changed)
        self.disabled_radio.toggled.connect(self.on_dir_mode_changed)
        
        layout.addWidget(self.strict_radio)
        layout.addWidget(self.neutral_radio)
        layout.addWidget(self.disabled_radio)
        
        # Direction examples
        examples_label = QLabel("\nDirection Examples:")
        examples_label.setFont(QFont("Arial", 10, QFont.Bold))
        layout.addWidget(examples_label)
        
        example1 = QLabel("• Bullish Regimes (R1): Allow BUY, Block SELL")
        example1.setStyleSheet("color: #00ff00;")
        layout.addWidget(example1)
        
        example2 = QLabel("• Bearish Regimes (R3, R4, R8): Allow SELL, Block BUY")
        example2.setStyleSheet("color: #ff0000;")
        layout.addWidget(example2)
        
        example3 = QLabel("• Neutral Regimes (R2, R5, R7): Allow both if 'Allow Neutral' mode")
        example3.setStyleSheet("color: #ffa500;")
        layout.addWidget(example3)
        
        layout.addStretch()
        widget.setLayout(layout)
        return widget
    
    # =============================================================
    # UPDATE METHODS
    # =============================================================
    
    def auto_refresh(self):
        """Auto-refresh triggered by timer."""
        self.fetch_and_update()
    
    def manual_refresh(self):
        """Manual refresh triggered by button."""
        self.fetch_and_update()
    
    def fetch_and_update(self):
        """Fetch market data and update UI."""
        symbol = self.symbol_input.text().strip()
        tf_name = self.timeframe_combo.currentText()
        timeframe = self.timeframe_map.get(tf_name, mt5.TIMEFRAME_M5)
        
        self.refresh_btn.setEnabled(False)
        self.refresh_btn.setText("Updating...")
        
        try:
            df = fetch_market_data(symbol, timeframe, DEFAULT_BARS)
            result = predict_regime(df)
            
            # Store current regime
            self.current_regime = result['regime_id']
            self.current_confidence = result['confidence']
            self.current_probabilities = result['probabilities']
            self.current_features = result.get('features', {})
            self.last_update_time = time.time()
            
            # Update UI
            self.update_live_data(result)
            self.update_probabilities(result['probabilities'])
            self.update_charts(result['featured_df'], result['regime_id'])
            self.update_statistics(result.get('features', {}))
            
            print(f"[UPDATE] Regime {result['regime_id']} ({REGIME_NAMES.get(result['regime_id'])}), "
                  f"Confidence {result['confidence']:.1f}%")
            
        except Exception as e:
            print(f"[ERROR] {e}")
            QMessageBox.warning(self, "Update Error", str(e))
        
        finally:
            self.refresh_btn.setEnabled(True)
            self.refresh_btn.setText("Refresh Now")
    
    def update_live_data(self, result):
        """Update live data panel."""
        regime_id = result['regime_id']
        regime_name = REGIME_NAMES.get(regime_id, f"Regime {regime_id}")
        regime_color = REGIME_COLORS.get(regime_id, "#ffffff")
        
        self.price_label.setText(f"{result['price']:.2f}")
        self.regime_label.setText(regime_name)
        self.regime_label.setStyleSheet(f"color: {regime_color}; font-weight: bold;")
        self.confidence_label.setText(f"{result['confidence']:.1f}%")
        
        # Trade status
        allow_trade = REGIME_FILTER_CONFIG.get(regime_id, True)
        if allow_trade:
            self.trade_status_label.setText("✓ ALLOWED")
            self.trade_status_label.setStyleSheet("color: #00ff00; font-weight: bold;")
        else:
            self.trade_status_label.setText("✗ BLOCKED")
            self.trade_status_label.setStyleSheet("color: #ff0000; font-weight: bold;")
        
        self.update_time_label.setText(time.strftime("%H:%M:%S"))
    
    def update_probabilities(self, probabilities):
        """Update probability table."""
        self.prob_table.setRowCount(len(probabilities))
        
        for i, prob in enumerate(probabilities):
            regime_name = REGIME_NAMES.get(i, f"Regime {i}")
            regime_color = REGIME_COLORS.get(i, "#ffffff")
            
            # Regime ID
            item_id = QTableWidgetItem(f"R{i+1}")
            item_id.setForeground(QColor(regime_color))
            self.prob_table.setItem(i, 0, item_id)
            
            # Regime Name
            item_name = QTableWidgetItem(regime_name)
            item_name.setForeground(QColor(regime_color))
            self.prob_table.setItem(i, 1, item_name)
            
            # Probability
            item_prob = QTableWidgetItem(f"{prob * 100:.2f}%")
            if i == self.current_regime:
                item_prob.setFont(QFont("Arial", 10, QFont.Bold))
                item_prob.setForeground(QColor(regime_color))
            self.prob_table.setItem(i, 2, item_prob)
    
    def update_charts(self, df, current_regime):
        """Update price and RSI charts."""
        self.ax_price.clear()
        self.ax_rsi.clear()
        
        # Price chart
        self.ax_price.plot(df.index, df['close'], label='Close Price', 
                          color='#4da6ff', linewidth=1.5)
        if 'price_position' in df.columns:
            self.ax_price.plot(df.index, df['price_position'] * df['close'].max(),
                              label='Price Position', color='#ffa500', 
                              linewidth=1, alpha=0.7)
        
        self.ax_price.set_title('Price Chart', color='#4da6ff', fontweight='bold')
        self.ax_price.set_ylabel('Price', color='#e0e0e0')
        self.ax_price.legend(loc='upper left', facecolor='#2d2d2d', 
                            edgecolor='#3d3d3d', labelcolor='#e0e0e0')
        self.ax_price.grid(True, alpha=0.2, color='#3d3d3d')
        
        # RSI chart
        if 'rsi_14' in df.columns:
            self.ax_rsi.plot(df.index, df['rsi_14'], label='RSI 14', 
                            color='#9370db', linewidth=1.5)
            self.ax_rsi.axhline(y=70, color='#ff0000', linestyle='--', 
                               alpha=0.5, label='Overbought')
            self.ax_rsi.axhline(y=30, color='#00ff00', linestyle='--', 
                               alpha=0.5, label='Oversold')
        
        regime_name = REGIME_NAMES.get(current_regime, f"Regime {current_regime}")
        self.ax_rsi.set_title(f'RSI - Current: {regime_name}', 
                             color='#4da6ff', fontweight='bold')
        self.ax_rsi.set_ylabel('RSI', color='#e0e0e0')
        self.ax_rsi.set_xlabel('Time', color='#e0e0e0')
        self.ax_rsi.legend(loc='upper left', facecolor='#2d2d2d', 
                          edgecolor='#3d3d3d', labelcolor='#e0e0e0')
        self.ax_rsi.grid(True, alpha=0.2, color='#3d3d3d')
        
        self.figure.tight_layout()
        self.canvas.draw()
    
    def update_statistics(self, features):
        """Update statistics table with feature values."""
        self.stats_table.setRowCount(len(features))
        
        for i, (feature_name, value) in enumerate(features.items()):
            # Feature name
            item_name = QTableWidgetItem(feature_name)
            self.stats_table.setItem(i, 0, item_name)
            
            # Feature value
            item_value = QTableWidgetItem(f"{value:.6f}")
            self.stats_table.setItem(i, 1, item_value)
    
    # =============================================================
    # CONFIGURATION CALLBACKS
    # =============================================================
    
    def on_filter_changed(self, regime_id, state):
        """Handle regime filter checkbox changes."""
        global REGIME_FILTER_CONFIG
        REGIME_FILTER_CONFIG[regime_id] = (state == Qt.Checked)
        
        status = "ALLOWED" if state == Qt.Checked else "BLOCKED"
        print(f"[CONFIG] Regime {regime_id+1} ({REGIME_NAMES.get(regime_id)}) -> {status}")
        
        # Update trade status if this is current regime
        if self.current_regime == regime_id:
            if state == Qt.Checked:
                self.trade_status_label.setText("✓ ALLOWED")
                self.trade_status_label.setStyleSheet("color: #00ff00; font-weight: bold;")
            else:
                self.trade_status_label.setText("✗ BLOCKED")
                self.trade_status_label.setStyleSheet("color: #ff0000; font-weight: bold;")
    
    def preset_allow_all(self):
        """Allow all regimes."""
        global REGIME_FILTER_CONFIG
        for regime_id, cb in self.regime_checkboxes.items():
            cb.setChecked(True)
            REGIME_FILTER_CONFIG[regime_id] = True
        print("[CONFIG] Preset: ALLOW ALL")
    
    def preset_block_all(self):
        """Block all regimes."""
        global REGIME_FILTER_CONFIG
        for regime_id, cb in self.regime_checkboxes.items():
            cb.setChecked(False)
            REGIME_FILTER_CONFIG[regime_id] = False
        print("[CONFIG] Preset: BLOCK ALL")
    
    def preset_conservative(self):
        """Conservative preset: block high volatility regimes."""
        global REGIME_FILTER_CONFIG
        conservative_config = {0: True, 1: True, 2: False, 3: True,
                              4: False, 5: False, 6: True, 7: True}
        
        for regime_id, allow in conservative_config.items():
            if regime_id in self.regime_checkboxes:
                self.regime_checkboxes[regime_id].setChecked(allow)
                REGIME_FILTER_CONFIG[regime_id] = allow
        
        print("[CONFIG] Preset: CONSERVATIVE (Block R3, R5, R6)")
    
    def on_dir_filter_changed(self, state):
        """Handle directional filter enable/disable."""
        global USE_DIRECTIONAL_FILTER
        USE_DIRECTIONAL_FILTER = (state == Qt.Checked)
        status = "ENABLED" if USE_DIRECTIONAL_FILTER else "DISABLED"
        print(f"[CONFIG] Directional Filter -> {status}")
    
    def on_dir_mode_changed(self):
        """Handle directional filter mode changes."""
        global DIRECTIONAL_FILTER_MODE
        
        if self.strict_radio.isChecked():
            DIRECTIONAL_FILTER_MODE = "strict"
        elif self.neutral_radio.isChecked():
            DIRECTIONAL_FILTER_MODE = "allow_neutral"
        else:
            DIRECTIONAL_FILTER_MODE = "disabled"
        
        print(f"[CONFIG] Directional Mode -> {DIRECTIONAL_FILTER_MODE}")
    
    # =============================================================
    # SOCKET SERVER
    # =============================================================
    
    def start_socket_server(self):
        """Start socket server thread."""
        self.socket_thread = threading.Thread(target=self.run_socket_server)
        self.socket_thread.daemon = True
        self.socket_thread.start()
        print(f"[SERVER] Started on {SOCKET_HOST}:{SOCKET_PORT}")
    
    def run_socket_server(self):
        """Socket server main loop."""
        try:
            self.socket_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.socket_server.bind((SOCKET_HOST, SOCKET_PORT))
            self.socket_server.listen(5)
            self.socket_server.settimeout(1.0)
            
            self.server_running = True
            self.server_status_label.setText(f"Server: RUNNING on {SOCKET_PORT}")
            self.server_status_label.setStyleSheet("color: #00ff00; font-weight: bold;")
            
            while self.running and self.server_running:
                try:
                    client_socket, address = self.socket_server.accept()
                    print(f"[SERVER] EA connected from {address}")
                    self.ea_status_label.setText(f"EA: Connected {address[0]}")
                    self.ea_status_label.setStyleSheet("color: #00ff00;")
                    
                    client_thread = threading.Thread(target=self.handle_client,
                                                    args=(client_socket, address))
                    client_thread.daemon = True
                    client_thread.start()
                    
                except socket.timeout:
                    continue
                except Exception as e:
                    if self.running:
                        print(f"[SERVER] Accept error: {e}")
                    break
        
        except Exception as e:
            print(f"[SERVER] Failed to start: {e}")
            self.server_status_label.setText(f"Server: ERROR")
            self.server_status_label.setStyleSheet("color: #ff0000;")
        
        finally:
            if self.socket_server:
                self.socket_server.close()
            self.server_running = False
    
    def handle_client(self, client_socket, address):
        """Handle EA client connection."""
        try:
            client_socket.settimeout(30.0)
            buffer = ""
            
            while self.running:
                try:
                    data = client_socket.recv(4096).decode('utf-8')
                    if not data:
                        break
                    
                    buffer += data
                    
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        if line.strip():
                            self.process_ea_request(client_socket, line.strip())
                
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"[SERVER] Client error: {e}")
                    break
        
        finally:
            client_socket.close()
            self.ea_status_label.setText("EA: Disconnected")
            self.ea_status_label.setStyleSheet("color: #808080;")
            print(f"[SERVER] EA disconnected from {address}")
    
    def process_ea_request(self, client_socket, message):
        """Process trade request from EA."""
        try:
            data = json.loads(message)
            msg_type = data.get("type", "")
            
            if msg_type == "trade_request":
                symbol = data.get("symbol", "")
                action = data.get("action", "").lower()
                
                # CRITICAL FIX: Fetch fresh regime data on every trade request
                # This ensures we're making decisions based on current market conditions
                try:
                    tf_name = self.timeframe_combo.currentText()
                    timeframe = self.timeframe_map.get(tf_name, mt5.TIMEFRAME_M5)
                    df = fetch_market_data(symbol, timeframe, DEFAULT_BARS)
                    result = predict_regime(df)
                    
                    # Update current regime with fresh data
                    self.current_regime = result['regime_id']
                    self.current_confidence = result['confidence']
                    self.current_probabilities = result["probabilities"]
                    
                    print(f"[TRADE REQUEST] Fresh regime calculated: Regime {self.current_regime} (Display: Regime {self.current_regime+1}), Confidence: {self.current_confidence:.1f}%")
                except Exception as e:
                    print(f"[TRADE REQUEST] Error fetching fresh regime: {e}")
                    # Fall through to use cached data if fresh fetch fails
                
                if self.current_regime is None:
                    response = {
                        "allow_trade": True,
                        "regime": -1,
                        "confidence": 0.0,
                        "reason": "No regime data available"
                    }
                else:
                    allow_trade = REGIME_FILTER_CONFIG.get(self.current_regime, True)
                    block_reason = ""
                    
                    print(f"[DEBUG] Checking trade: Action={action}, Regime={self.current_regime} (Display: R{self.current_regime+1}), FilterConfig={REGIME_FILTER_CONFIG.get(self.current_regime, True)}")
                    
                    if not allow_trade:
                        block_reason = f"Regime {self.current_regime+1} is disabled in filter config"
                    
                    # Check directional filter
                    if allow_trade and USE_DIRECTIONAL_FILTER and DIRECTIONAL_FILTER_MODE != "disabled":
                        regime_direction = REGIME_DIRECTION.get(self.current_regime, "neutral")
                        
                        print(f"[DEBUG] Directional Filter: Regime={self.current_regime} (R{self.current_regime+1}), Direction={regime_direction}, Action={action}, Mode={DIRECTIONAL_FILTER_MODE}")
                        
                        if DIRECTIONAL_FILTER_MODE == "strict":
                            if regime_direction == "bullish" and action == "sell":
                                allow_trade = False
                                block_reason = f"Regime {self.current_regime+1} is BULLISH, SELL blocked (counter-trend)"
                            elif regime_direction == "bearish" and action == "buy":
                                allow_trade = False
                                block_reason = f"Regime {self.current_regime+1} is BEARISH, BUY blocked (counter-trend)"
                            elif regime_direction == "neutral":
                                allow_trade = False
                                block_reason = f"Regime {self.current_regime+1} is NEUTRAL (no clear direction in strict mode)"
                        
                        elif DIRECTIONAL_FILTER_MODE == "allow_neutral":
                            if regime_direction == "bullish" and action == "sell":
                                allow_trade = False
                                block_reason = f"Regime {self.current_regime+1} is BULLISH, SELL blocked (counter-trend)"
                            elif regime_direction == "bearish" and action == "buy":
                                allow_trade = False
                                block_reason = f"Regime {self.current_regime+1} is BEARISH, BUY blocked (counter-trend)"
                    
                    if allow_trade:
                        reason = f"Regime {self.current_regime+1} ({REGIME_DIRECTION.get(self.current_regime, 'unknown')}): {action.upper()} ALLOWED"
                    else:
                        reason = block_reason
                    
                    response = {
                        "allow_trade": allow_trade,
                        "regime": int(self.current_regime),
                        "confidence": float(self.current_confidence),
                        "reason": reason
                    }
                    
                    print(f"[TRADE] {action.upper()} on {symbol} -> "
                          f"Regime {self.current_regime} (Display: R{self.current_regime+1}, {REGIME_DIRECTION.get(self.current_regime, 'unknown')}, {self.current_confidence:.1f}%) -> "
                          f"{'ALLOWED ✓' if allow_trade else 'BLOCKED ✗'}")
                    if not allow_trade:
                        print(f"  Reason: {block_reason}")
                
                response_json = json.dumps(response) + "\n"
                client_socket.sendall(response_json.encode('utf-8'))
            
            elif msg_type == "handshake":
                terminal = data.get("terminal", "Unknown")
                print(f"[HANDSHAKE] EA connected: {terminal}")
                
                response = {"status": "connected", "message": "Dashboard ready"}
                response_json = json.dumps(response) + "\n"
                client_socket.sendall(response_json.encode('utf-8'))
        
        except json.JSONDecodeError:
            print(f"[SERVER] Invalid JSON: {message}")
        except Exception as e:
            print(f"[SERVER] Error processing request: {e}")
    
    def closeEvent(self, event):
        """Handle window close event."""
        self.running = False
        self.timer.stop()
        if self.socket_server:
            self.socket_server.close()
        event.accept()

# =============================================================
# MAIN
# =============================================================

def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(DARK_STYLESHEET)
    
    window = RegimeDashboard()
    window.show()
    
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
