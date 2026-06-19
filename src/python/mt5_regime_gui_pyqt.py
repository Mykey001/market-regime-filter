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
import winreg
from pathlib import Path
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QLabel, QPushButton, QComboBox, 
                             QLineEdit, QGroupBox, QCheckBox, QGridLayout,
                             QScrollArea, QTabWidget, QTableWidget, QTableWidgetItem,
                             QSplitter, QFrame, QRadioButton, QButtonGroup, QMessageBox,
                             QDialog, QDialogButtonBox, QListWidget, QListWidgetItem,
                             QTextEdit, QSpinBox, QDoubleSpinBox)
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

# Regime cache TTL (seconds) - avoid hammering MT5 for every trade request
REGIME_CACHE_TTL = 30


# Create a global reentrant lock for MT5 API access
_mt5_lock = threading.RLock()


# ============================================================
# MT5 CONNECTION HELPERS
# ============================================================

def _resolve_terminal_exe(terminal_path):
    """Resolve a terminal path to the actual terminal64.exe path.
    
    The terminal scanner sometimes stores the data folder path
    instead of the executable path. This helper finds terminal64.exe
    by reading origin.txt or searching the directories.
    
    Args:
        terminal_path: Path string (could be exe, folder, or data path)
    
    Returns:
        Path to terminal64.exe if found, or None
    """
    if not terminal_path:
        return None
    
    p = Path(terminal_path)
    
    # If it's already pointing to an exe, use it
    if p.suffix.lower() == '.exe' and p.exists():
        return str(p)
    
    # If it's a folder, check for origin.txt or check inside it
    if p.is_dir():
        # 1. Try resolving installation path from origin.txt (typical for MT5 data folders)
        origin_txt = p / "origin.txt"
        if origin_txt.exists():
            for encoding in ['utf-16-le', 'utf-8', 'ansi']:
                try:
                    with open(origin_txt, 'r', encoding=encoding) as f:
                        install_path_str = f.read().strip().replace('\ufeff', '').replace('\ufffe', '')
                        if install_path_str:
                            install_path = Path(install_path_str)
                            if install_path.exists():
                                for exe_name in ['terminal64.exe', 'terminal.exe']:
                                    exe_path = install_path / exe_name
                                    if exe_path.exists():
                                        print(f"[RESOLVER] Resolved executable via origin.txt: {exe_path}")
                                        return str(exe_path)
                except Exception:
                    pass

        # 2. Look directly inside folder p
        for exe_name in ['terminal64.exe', 'terminal.exe']:
            exe_path = p / exe_name
            if exe_path.exists():
                return str(exe_path)
        
        # 3. Check parent folders (if this is a data path and origin.txt wasn't found/resolved)
        for parent in [p.parent, p.parent.parent]:
            for exe_name in ['terminal64.exe', 'terminal.exe']:
                exe_path = parent / exe_name
                if exe_path.exists():
                    return str(exe_path)
    
    return None


def _init_mt5(terminal_path=None):
    """Initialize MT5 connection, optionally to a specific terminal.
    
    Args:
        terminal_path: Path to terminal executable or folder.
                      If None, connects to any running MT5 instance.
    
    Returns:
        True if successfully initialized
    
    Raises:
        Exception if initialization fails
    """
    with _mt5_lock:
        # Try to resolve to an actual exe path
        exe_path = _resolve_terminal_exe(terminal_path) if terminal_path else None
        
        if exe_path:
            print(f"[MT5] Initializing with terminal: {exe_path}")
            if not mt5.initialize(path=exe_path):
                error = mt5.last_error()
                raise Exception(f"MT5 initialize failed for {exe_path}: {error}")
        else:
            if terminal_path:
                print(f"[MT5] Could not resolve exe from '{terminal_path}', trying default...")
            print(f"[MT5] Initializing default connection...")
            if not mt5.initialize():
                error = mt5.last_error()
                raise Exception(f"MT5 initialize failed: {error}")
        
        # Log which terminal we actually connected to
        term_info = mt5.terminal_info()
        if term_info:
            print(f"[MT5] Connected to: {term_info.company} at {term_info.path}")
        
        return True

# ============================================================
# TERMINAL SCANNER - Windows Registry Scanner
# ============================================================

class TerminalScanner:
    """Scan Windows registry for installed MT4/MT5 terminals."""
    
    @staticmethod
    def scan_installed_terminals():
        """
        Scan Windows for MetaTrader installations.
        Returns list of dicts with terminal info.
        """
        terminals = []
        
        # Method 1: Check if MT5 is already running and can be connected to
        try:
            with _mt5_lock:
                if mt5.initialize():
                    terminal_info = mt5.terminal_info()
                    account_info = mt5.account_info()
                    
                    if terminal_info and account_info:
                        terminal_data = {
                            "name": f"{account_info.company} - Account {account_info.login} (MT5 - Connected)",
                            "path": terminal_info.path,
                            "data_path": terminal_info.data_path,
                            "version": "MT5",
                            "broker": account_info.company,
                            "account": str(account_info.login),
                            "connected": True
                        }
                        terminals.append(terminal_data)
                        print(f"[SCANNER] Found running MT5: {terminal_data['name']}")
                    
                    mt5.shutdown()
        except Exception as e:
            print(f"[SCANNER] MT5 connection check failed: {e}")
        
        # Method 2: Scan AppData for terminal configurations
        try:
            appdata_roaming = Path(os.environ.get('APPDATA', ''))
            metaquotes_path = appdata_roaming / "MetaQuotes"
            
            if metaquotes_path.exists():
                # Look for Terminal folders
                terminal_folders = list(metaquotes_path.glob("Terminal/*"))
                
                for term_folder in terminal_folders:
                    # Check if it has MQL5 or MQL4
                    if (term_folder / "MQL5").exists():
                        version = "MT5"
                        mql_folder = term_folder / "MQL5"
                    elif (term_folder / "MQL4").exists():
                        version = "MT4"
                        mql_folder = term_folder / "MQL4"
                    else:
                        continue
                    
                    # Try to read origin.txt to get broker info
                    origin_file = term_folder / "origin.txt"
                    broker = "Unknown Broker"
                    if origin_file.exists():
                        try:
                            with open(origin_file, 'r', encoding='utf-16-le') as f:
                                broker = f.read().strip()
                        except:
                            pass
                    
                    terminal_info = {
                        "name": f"{broker} ({version}) - {term_folder.name[:8]}",
                        "path": str(term_folder),
                        "data_path": str(term_folder),
                        "version": version,
                        "broker": broker,
                        "connected": False
                    }
                    
                    # Avoid duplicates
                    if not any(t["path"] == str(term_folder) for t in terminals):
                        terminals.append(terminal_info)
                        print(f"[SCANNER] Found terminal data: {terminal_info['name']}")
        
        except Exception as e:
            print(f"[SCANNER] AppData scan failed: {e}")
        
        # Method 3: Registry paths to scan
        registry_paths = [
            (winreg.HKEY_CURRENT_USER, r"Software\MetaQuotes\Terminal"),
        ]
        
        for hkey, reg_path in registry_paths:
            try:
                key = winreg.OpenKey(hkey, reg_path)
                i = 0
                while True:
                    try:
                        subkey_name = winreg.EnumKey(key, i)
                        subkey = winreg.OpenKey(key, subkey_name)
                        
                        try:
                            # Get paths
                            data_path = None
                            try:
                                data_path, _ = winreg.QueryValueEx(subkey, "DataPath")
                            except WindowsError:
                                pass
                            
                            if data_path and Path(data_path).exists():
                                # Check version
                                version = "MT5" if (Path(data_path) / "MQL5").exists() else "MT4"
                                
                                terminal_info = {
                                    "name": f"Terminal {subkey_name[:8]} ({version})",
                                    "path": data_path,
                                    "data_path": data_path,
                                    "version": version,
                                    "broker": "Registry Entry",
                                    "connected": False
                                }
                                
                                # Avoid duplicates
                                if not any(t["path"] == data_path for t in terminals):
                                    terminals.append(terminal_info)
                                    print(f"[SCANNER] Found registry entry: {terminal_info['name']}")
                        
                        except WindowsError:
                            pass
                        
                        winreg.CloseKey(subkey)
                        i += 1
                    except WindowsError:
                        break
                
                winreg.CloseKey(key)
            except WindowsError:
                continue
        
        # Method 4: Common installation paths
        common_paths = [
            Path(r"C:\Program Files\MetaTrader 5"),
            Path(r"C:\Program Files (x86)\MetaTrader 5"),
            Path(r"C:\Program Files\MetaTrader 4"),
            Path(r"C:\Program Files (x86)\MetaTrader 4"),
        ]
        
        for path in common_paths:
            if path.exists():
                version = "MT5" if "5" in path.name else "MT4"
                exe_name = "terminal64.exe" if version == "MT5" else "terminal.exe"
                
                if (path / exe_name).exists():
                    terminal_info = {
                        "name": f"{path.name} (Installation)",
                        "path": str(path),
                        "data_path": str(path),
                        "version": version,
                        "broker": "Program Files",
                        "connected": False
                    }
                    
                    if not any(t["path"] == str(path) for t in terminals):
                        terminals.append(terminal_info)
                        print(f"[SCANNER] Found installation: {terminal_info['name']}")
        
        return terminals


class TerminalSelectorDialog(QDialog):
    """Dialog for selecting terminal to connect to."""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Select MetaTrader Terminal")
        self.setModal(True)
        self.setMinimumWidth(600)
        self.setMinimumHeight(400)
        
        self.selected_terminal = None
        self.init_ui()
    
    def init_ui(self):
        layout = QVBoxLayout()
        
        # Instructions
        info_label = QLabel("Select a MetaTrader terminal to connect for market data:")
        info_label.setWordWrap(True)
        info_label.setStyleSheet("color: #4da6ff; font-weight: bold;")
        layout.addWidget(info_label)
        
        # Connection method tabs
        tab_widget = QTabWidget()
        
        # Auto-detect tab
        auto_tab = QWidget()
        auto_layout = QVBoxLayout()
        
        # Scan button
        scan_btn = QPushButton("Scan for Terminals")
        scan_btn.clicked.connect(self.scan_terminals)
        auto_layout.addWidget(scan_btn)
        
        # Terminal list
        self.terminal_list = QListWidget()
        self.terminal_list.itemDoubleClicked.connect(self.on_terminal_selected)
        auto_layout.addWidget(self.terminal_list)
        
        auto_tab.setLayout(auto_layout)
        tab_widget.addTab(auto_tab, "Auto-Detect")
        
        # Manual connection tab
        manual_tab = QWidget()
        manual_layout = QVBoxLayout()
        
        manual_info = QLabel(
            "If auto-detect doesn't work, ensure MetaTrader 5 is running and logged in, "
            "then click 'Connect to Running MT5' below."
        )
        manual_info.setWordWrap(True)
        manual_layout.addWidget(manual_info)
        
        connect_btn = QPushButton("Connect to Running MT5")
        connect_btn.clicked.connect(self.connect_to_running_mt5)
        manual_layout.addWidget(connect_btn)
        
        self.manual_status = QLabel("")
        manual_layout.addWidget(self.manual_status)
        
        manual_layout.addStretch()
        manual_tab.setLayout(manual_layout)
        tab_widget.addTab(manual_tab, "Connect to Running MT5")
        
        layout.addWidget(tab_widget)
        
        # Status label
        self.status_label = QLabel("Click 'Scan for Terminals' to find installed terminals")
        self.status_label.setStyleSheet("color: #ffa500;")
        layout.addWidget(self.status_label)
        
        # Buttons
        button_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)
        
        self.setLayout(layout)
        
        # Auto-scan on open
        self.scan_terminals()
    
    def connect_to_running_mt5(self):
        """Connect to currently running MT5 instance."""
        self.manual_status.setText("Attempting to connect...")
        self.manual_status.setStyleSheet("color: #ffa500;")
        
        try:
            with _mt5_lock:
                if not mt5.initialize():
                    error = mt5.last_error()
                    self.manual_status.setText(f"Failed to connect: {error}\n\nMake sure MT5 is running and you are logged into an account.")
                    self.manual_status.setStyleSheet("color: #ff0000;")
                    return
                
                terminal_info = mt5.terminal_info()
                account_info = mt5.account_info()
                
                if terminal_info and account_info:
                    # Use terminal executable path for connecting
                    terminal_exe_path = terminal_info.path
                    
                    self.selected_terminal = {
                        "name": f"{account_info.company} - Account {account_info.login} (Connected)",
                        "path": terminal_exe_path,  # Executable path for mt5.initialize(path=...)
                        "data_path": terminal_info.data_path,
                        "version": "MT5",
                        "broker": account_info.company,
                        "account": str(account_info.login),
                        "connected": True
                    }
                    
                    self.manual_status.setText(
                        f"✓ Connected!\n"
                        f"Broker: {account_info.company}\n"
                        f"Account: {account_info.login}\n"
                        f"Terminal: {terminal_exe_path}"
                    )
                    self.manual_status.setStyleSheet("color: #00ff00;")
                    
                    mt5.shutdown()
                    
                    # Auto-accept dialog
                    QMessageBox.information(
                        self,
                        "Connection Successful",
                        f"Connected to {account_info.company}\nAccount: {account_info.login}\n\nClick OK to use this terminal."
                    )
                    self.accept()
                else:
                    self.manual_status.setText("Connected but couldn't get terminal info")
                    self.manual_status.setStyleSheet("color: #ff0000;")
                    mt5.shutdown()
        
        except Exception as e:
            self.manual_status.setText(f"Connection error: {str(e)}")
            self.manual_status.setStyleSheet("color: #ff0000;")
    
    def scan_terminals(self):
        """Scan for installed terminals."""
        self.terminal_list.clear()
        self.status_label.setText("Scanning...")
        
        try:
            terminals = TerminalScanner.scan_installed_terminals()
            
            if not terminals:
                self.status_label.setText("No terminals found. Please install MetaTrader 4 or 5.")
                return
            
            for terminal in terminals:
                item_text = f"{terminal['name']} - {terminal['path']}"
                item = QListWidgetItem(item_text)
                item.setData(Qt.UserRole, terminal)
                self.terminal_list.addItem(item)
            
            self.status_label.setText(f"Found {len(terminals)} terminal(s). Double-click to select.")
            self.status_label.setStyleSheet("color: #00ff00;")
        
        except Exception as e:
            self.status_label.setText(f"Scan error: {str(e)}")
            self.status_label.setStyleSheet("color: #ff0000;")
    
    def on_terminal_selected(self, item):
        """Handle terminal selection."""
        self.selected_terminal = item.data(Qt.UserRole)
        self.accept()
    
    def accept(self):
        """Handle OK button."""
        current_item = self.terminal_list.currentItem()
        if current_item:
            self.selected_terminal = current_item.data(Qt.UserRole)
        super().accept()


# ============================================================
# EA CONFIGURATION MANAGER
# ============================================================

class EAConfig:
    """Configuration for an individual EA."""
    
    def __init__(self, ea_name, symbol="", account="", terminal=""):
        self.ea_name = ea_name
        self.symbol = symbol
        self.account = account
        self.terminal = terminal
        self.allowed_regimes = list(range(8))  # All regimes allowed by default
        self.min_confidence = 50.0
        self.use_volatility_filter = False
        self.allowed_volatility = "any"  # "high", "low", "any"
        self.use_directional_filter = True
        self.directional_mode = "strict"  # "strict", "allow_neutral", "disabled"
        self.connected = False
        self.last_trade_time = None
        self.trade_count = 0
    
    def to_dict(self):
        """Convert to dictionary."""
        return {
            "ea_name": self.ea_name,
            "symbol": self.symbol,
            "account": self.account,
            "terminal": self.terminal,
            "allowed_regimes": self.allowed_regimes,
            "min_confidence": self.min_confidence,
            "use_volatility_filter": self.use_volatility_filter,
            "allowed_volatility": self.allowed_volatility,
            "use_directional_filter": self.use_directional_filter,
            "directional_mode": self.directional_mode,
            "connected": self.connected,
            "trade_count": self.trade_count
        }
    
    def allows_regime(self, regime_id):
        """Check if regime is allowed."""
        return regime_id in self.allowed_regimes
    
    def get_description(self):
        """Get human-readable description of filter config."""
        parts = []
        
        if len(self.allowed_regimes) == 8:
            parts.append("All regimes")
        else:
            regime_names = [f"R{r+1}" for r in self.allowed_regimes]
            parts.append(f"Regimes: {', '.join(regime_names)}")
        
        parts.append(f"Min confidence: {self.min_confidence}%")
        
        if self.use_directional_filter and self.directional_mode != "disabled":
            parts.append(f"Directional: {self.directional_mode}")
        
        if self.use_volatility_filter:
            parts.append(f"Volatility: {self.allowed_volatility}")
        
        return " | ".join(parts)


class EAConfigDialog(QDialog):
    """Dialog for configuring an EA's filter settings."""
    
    def __init__(self, ea_config, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"Configure EA: {ea_config.ea_name}")
        self.setModal(True)
        self.setMinimumWidth(600)
        self.setMinimumHeight(700)
        
        self.ea_config = ea_config
        self.regime_checkboxes = {}
        
        self.init_ui()
    
    def init_ui(self):
        layout = QVBoxLayout()
        
        # EA Info
        info_group = QGroupBox("EA Information")
        info_layout = QGridLayout()
        info_layout.addWidget(QLabel("EA Name:"), 0, 0)
        info_layout.addWidget(QLabel(self.ea_config.ea_name), 0, 1)
        info_layout.addWidget(QLabel("Symbol:"), 1, 0)
        info_layout.addWidget(QLabel(self.ea_config.symbol), 1, 1)
        info_layout.addWidget(QLabel("Account:"), 2, 0)
        info_layout.addWidget(QLabel(self.ea_config.account), 2, 1)
        info_group.setLayout(info_layout)
        layout.addWidget(info_group)
        
        # Regime Filter
        regime_group = QGroupBox("Allowed Regimes (Check to ALLOW)")
        regime_layout = QGridLayout()
        
        for regime_id in range(8):
            regime_name = REGIME_NAMES.get(regime_id, f"Regime {regime_id}")
            cb = QCheckBox(regime_name)
            cb.setChecked(regime_id in self.ea_config.allowed_regimes)
            self.regime_checkboxes[regime_id] = cb
            regime_layout.addWidget(cb, regime_id // 2, regime_id % 2)
        
        regime_group.setLayout(regime_layout)
        layout.addWidget(regime_group)
        
        # Confidence
        conf_group = QGroupBox("Minimum Confidence Threshold")
        conf_layout = QHBoxLayout()
        conf_layout.addWidget(QLabel("Min Confidence:"))
        self.conf_spinbox = QDoubleSpinBox()
        self.conf_spinbox.setRange(0, 100)
        self.conf_spinbox.setValue(self.ea_config.min_confidence)
        self.conf_spinbox.setSuffix("%")
        conf_layout.addWidget(self.conf_spinbox)
        conf_layout.addStretch()
        conf_group.setLayout(conf_layout)
        layout.addWidget(conf_group)
        
        # Directional Filter
        dir_group = QGroupBox("Directional Filter")
        dir_layout = QVBoxLayout()
        
        self.dir_enabled_cb = QCheckBox("Enable Directional Filter")
        self.dir_enabled_cb.setChecked(self.ea_config.use_directional_filter)
        dir_layout.addWidget(self.dir_enabled_cb)
        
        self.dir_mode_group = QButtonGroup()
        self.strict_rb = QRadioButton("Strict - Only with trend")
        self.neutral_rb = QRadioButton("Allow Neutral - Both ways in neutral")
        self.disabled_rb = QRadioButton("Disabled - Allow all")
        
        self.dir_mode_group.addButton(self.strict_rb, 0)
        self.dir_mode_group.addButton(self.neutral_rb, 1)
        self.dir_mode_group.addButton(self.disabled_rb, 2)
        
        if self.ea_config.directional_mode == "strict":
            self.strict_rb.setChecked(True)
        elif self.ea_config.directional_mode == "allow_neutral":
            self.neutral_rb.setChecked(True)
        else:
            self.disabled_rb.setChecked(True)
        
        dir_layout.addWidget(self.strict_rb)
        dir_layout.addWidget(self.neutral_rb)
        dir_layout.addWidget(self.disabled_rb)
        dir_group.setLayout(dir_layout)
        layout.addWidget(dir_group)
        
        # Volatility Filter
        vol_group = QGroupBox("Volatility Filter")
        vol_layout = QVBoxLayout()
        
        self.vol_enabled_cb = QCheckBox("Enable Volatility Filter")
        self.vol_enabled_cb.setChecked(self.ea_config.use_volatility_filter)
        vol_layout.addWidget(self.vol_enabled_cb)
        
        vol_combo_layout = QHBoxLayout()
        vol_combo_layout.addWidget(QLabel("Allowed Volatility:"))
        self.vol_combo = QComboBox()
        self.vol_combo.addItems(["any", "high", "low"])
        self.vol_combo.setCurrentText(self.ea_config.allowed_volatility)
        vol_combo_layout.addWidget(self.vol_combo)
        vol_combo_layout.addStretch()
        vol_layout.addLayout(vol_combo_layout)
        
        vol_group.setLayout(vol_layout)
        layout.addWidget(vol_group)
        
        # Buttons
        button_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)
        
        self.setLayout(layout)
    
    def accept(self):
        """Save configuration."""
        # Update allowed regimes
        self.ea_config.allowed_regimes = [
            regime_id for regime_id, cb in self.regime_checkboxes.items()
            if cb.isChecked()
        ]
        
        # Update confidence
        self.ea_config.min_confidence = self.conf_spinbox.value()
        
        # Update directional filter
        self.ea_config.use_directional_filter = self.dir_enabled_cb.isChecked()
        if self.strict_rb.isChecked():
            self.ea_config.directional_mode = "strict"
        elif self.neutral_rb.isChecked():
            self.ea_config.directional_mode = "allow_neutral"
        else:
            self.ea_config.directional_mode = "disabled"
        
        # Update volatility filter
        self.ea_config.use_volatility_filter = self.vol_enabled_cb.isChecked()
        self.ea_config.allowed_volatility = self.vol_combo.currentText()
        
        super().accept()


class SymbolBrowserDialog(QDialog):
    """Dialog for browsing available symbols in MT5."""
    
    def __init__(self, parent=None, terminal_path=None):
        super().__init__(parent)
        self.setWindowTitle("Browse Available Symbols")
        self.setModal(True)
        self.setMinimumWidth(500)
        self.setMinimumHeight(600)
        
        self.selected_symbol = None
        self.terminal_path = terminal_path
        self.init_ui()
    
    def init_ui(self):
        layout = QVBoxLayout()
        
        # Info
        info_label = QLabel("Available symbols in connected MT5 terminal:")
        info_label.setStyleSheet("color: #4da6ff; font-weight: bold;")
        layout.addWidget(info_label)
        
        # Terminal info
        if self.terminal_path:
            path_label = QLabel(f"Terminal: {self.terminal_path}")
            path_label.setStyleSheet("color: #808080; font-size: 9pt;")
            layout.addWidget(path_label)
        
        # Search box
        search_layout = QHBoxLayout()
        search_layout.addWidget(QLabel("Search:"))
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("Type to filter symbols...")
        self.search_input.textChanged.connect(self.filter_symbols)
        search_layout.addWidget(self.search_input)
        layout.addLayout(search_layout)
        
        # Symbol list
        self.symbol_list = QListWidget()
        self.symbol_list.itemDoubleClicked.connect(self.on_symbol_selected)
        layout.addWidget(self.symbol_list)
        
        # Status
        self.status_label = QLabel("Loading symbols...")
        self.status_label.setStyleSheet("color: #ffa500;")
        layout.addWidget(self.status_label)
        
        # Buttons
        button_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)
        
        self.setLayout(layout)
        
        # Load symbols
        self.load_symbols()
    
    def load_symbols(self):
        """Load symbols from MT5."""
        try:
            print(f"[SYMBOL BROWSER] Loading symbols from terminal: {self.terminal_path}")
            symbols = get_available_symbols(self.terminal_path)
            
            if not symbols:
                self.status_label.setText("No symbols found. Ensure MT5 terminal is logged in.")
                self.status_label.setStyleSheet("color: #ff0000;")
                return
            
            # Store all symbols
            self.all_symbols = sorted(symbols)
            
            # Populate list
            for symbol in self.all_symbols:
                self.symbol_list.addItem(symbol)
            
            self.status_label.setText(f"Found {len(symbols)} symbols. Double-click to select.")
            self.status_label.setStyleSheet("color: #00ff00;")
            
            print(f"[SYMBOL BROWSER] Loaded {len(symbols)} symbols")
        
        except Exception as e:
            self.status_label.setText(f"Error loading symbols: {str(e)}")
            self.status_label.setStyleSheet("color: #ff0000;")
            print(f"[SYMBOL BROWSER ERROR] {e}")
    
    def filter_symbols(self, text):
        """Filter symbol list based on search text."""
        if not hasattr(self, 'all_symbols'):
            return
        
        self.symbol_list.clear()
        
        search_text = text.upper()
        
        if not search_text:
            # Show all
            for symbol in self.all_symbols:
                self.symbol_list.addItem(symbol)
        else:
            # Filter
            matching = [s for s in self.all_symbols if search_text in s.upper()]
            for symbol in matching:
                self.symbol_list.addItem(symbol)
        
        count = self.symbol_list.count()
        self.status_label.setText(f"Showing {count} symbols")
    
    def on_symbol_selected(self, item):
        """Handle symbol double-click."""
        self.selected_symbol = item.text()
        self.accept()
    
    def accept(self):
        """Handle OK button."""
        current_item = self.symbol_list.currentItem()
        if current_item:
            self.selected_symbol = current_item.text()
        super().accept()


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
    8: "neutral",  # Fallback for invalid regime (should never happen)
}

USE_DIRECTIONAL_FILTER = True
DIRECTIONAL_FILTER_MODE = "strict"

# ============================================================
# MT5 FETCHER
# ============================================================

# ============================================================
# MT5 FETCHER WITH SYMBOL VALIDATION
# ============================================================

def get_available_symbols(terminal_path=None):
    """Get list of available symbols from MT5.
    
    Args:
        terminal_path: Path to specific MT5 terminal (can be exe or folder)
    """
    with _mt5_lock:
        # Connect to the specified terminal
        try:
            _init_mt5(terminal_path)
        except Exception as e:
            print(f"[SYMBOLS] Failed to connect to MT5: {e}")
            return []
        
        # Log account info
        acct = mt5.account_info()
        if acct:
            print(f"[SYMBOLS] Account: {acct.login}")
        
        # First try: Get visible symbols only
        symbols = mt5.symbols_get()
        print(f"[SYMBOLS] symbols_get() returned: {len(symbols) if symbols else 0} symbols")
        
        if symbols is None or len(symbols) == 0:
            print("[SYMBOLS] No visible symbols, trying to get all symbols with group='*'...")
            # Try getting all symbols (including hidden ones)
            symbols = mt5.symbols_get(group="*")
            print(f"[SYMBOLS] symbols_get(group='*') returned: {len(symbols) if symbols else 0} symbols")
        
        if symbols is None or len(symbols) == 0:
            print("[SYMBOLS] Still no symbols, trying common groups...")
            # Try common symbol groups
            for group in ["*Forex*", "*Metals*", "*Metal*", "*Crypto*", "*Indices*", "*Commodities*", "*CFD*"]:
                print(f"[SYMBOLS] Trying group='{group}'...")
                symbols = mt5.symbols_get(group=group)
                if symbols and len(symbols) > 0:
                    print(f"[SYMBOLS] Found {len(symbols)} symbols in group '{group}'")
                    break
        
        # If still nothing, try to show what we can access
        if symbols is None or len(symbols) == 0:
            print("[SYMBOLS] No symbols found with any method!")
            print("[SYMBOLS] Trying to get symbol_total()...")
            total = mt5.symbols_total()
            print(f"[SYMBOLS] symbols_total() = {total}")
        
        mt5.shutdown()
        
        if symbols is None or len(symbols) == 0:
            print("[SYMBOLS] WARNING: No symbols found at all!")
            return []
        
        symbol_names = [s.name for s in symbols]
        print(f"[SYMBOLS] Retrieved {len(symbol_names)} symbols")
        if len(symbol_names) > 0:
            print(f"[SYMBOLS] First 10 symbols: {symbol_names[:10]}")
        return symbol_names


def _normalize_and_find_symbol(requested_symbol, symbol_names):
    """Find a matching symbol in symbol_names, supporting aliases (e.g. GOLD -> XAUUSD) and suffixes.
    
    Args:
        requested_symbol: Symbol name as requested
        symbol_names: List of all valid symbol names from the terminal
        
    Returns:
        Actual matching symbol name or None
    """
    if not requested_symbol or not symbol_names:
        return None
    
    # 1. Helper to run standard searches (exact, case-insensitive, suffix, partial)
    def _search(target):
        target_upper = target.upper()
        # Exact match
        if target in symbol_names:
            return target
        # Case-insensitive match
        for sym in symbol_names:
            if sym.upper() == target_upper:
                return sym
        # Suffix match
        suffixes = ['m', '.m', '_m', 'i', '.i', '_i', 'c', '.c', '_c', '#', 'pro', '.pro', 'r', '.F']
        for suffix in suffixes:
            candidate1 = target_upper + suffix
            candidate2 = target_upper + suffix.upper()
            for sym in symbol_names:
                sym_upper = sym.upper()
                if sym_upper == candidate1 or sym_upper == candidate2:
                    return sym
        # Partial match
        for sym in symbol_names:
            if target_upper in sym.upper():
                return sym
        return None

    # Try original symbol first
    matched = _search(requested_symbol)
    if matched:
        return matched
    
    # Try common alias translations
    alias = requested_symbol.upper().strip()
    if alias == "GOLD":
        matched = _search("XAUUSD")
        if matched:
            return matched
    elif alias == "SILVER":
        matched = _search("XAGUSD")
        if matched:
            return matched
            
    # Try stripping suffix if it's a standard currency pair / commodity with trailing characters
    # e.g., "XAUUSDm" -> "XAUUSD" or "EURUSD.pro" -> "EURUSD"
    if len(alias) > 6:
        base = alias[:6]
        if any(base.startswith(p) for p in ['EUR', 'USD', 'GBP', 'JPY', 'AUD', 'CAD', 'CHF', 'NZD', 'XAU', 'XAG']):
            print(f"[SYMBOL] Stripping suffix from '{requested_symbol}' to '{base}' and retrying match...")
            matched = _search(base)
            if matched:
                return matched
                
    return matched


def find_matching_symbol(requested_symbol, terminal_path=None):
    """
    Find matching symbol in MT5, handling broker-specific suffixes.
    
    Args:
        requested_symbol: Symbol requested (e.g., "GOLD", "XAUUSD")
        terminal_path: Path to specific MT5 terminal (not used, for compatibility)
    
    Returns:
        Actual symbol name in MT5, or None if not found
    """
    with _mt5_lock:
        # Connect to the specified terminal
        try:
            _init_mt5(terminal_path)
        except Exception:
            return None
        
        # Get all available symbols (including hidden ones)
        symbols = mt5.symbols_get(group="*")
        if symbols is None or len(symbols) == 0:
            # Fallback to visible only
            symbols = mt5.symbols_get()
        
        if symbols is None or len(symbols) == 0:
            mt5.shutdown()
            print("[SYMBOL] ERROR: No symbols available at all!")
            return None
        
        symbol_names = [s.name for s in symbols]
        
        # Close connection
        mt5.shutdown()
    
    print(f"[SYMBOL SEARCH] Looking for '{requested_symbol}' in {len(symbol_names)} available symbols")
    
    actual_symbol = _normalize_and_find_symbol(requested_symbol, symbol_names)
    
    if actual_symbol:
        print(f"[SYMBOL] Matched: '{requested_symbol}' → '{actual_symbol}'")
    else:
        print(f"[SYMBOL] No match found for '{requested_symbol}'")
        print(f"[SYMBOL] Available symbols: {symbol_names[:20]}")
        
        # Try to suggest similar
        keywords = ['XAU', 'GOLD', requested_symbol[:3].upper() if len(requested_symbol) >= 3 else requested_symbol.upper()]
        similar = []
        for keyword in keywords:
            similar.extend([s for s in symbol_names if keyword in s.upper()])
        if similar:
            print(f"[SYMBOL] Similar symbols found: {similar[:10]}")
            
    return actual_symbol


def fetch_market_data(symbol, timeframe, bars=DEFAULT_BARS, terminal_path=None):
    """
    Fetch market data from specific MT5 terminal.
    
    Args:
        symbol: Symbol name (will auto-correct if needed)
        timeframe: MT5 timeframe constant
        bars: Number of bars to fetch
        terminal_path: Path to MT5 terminal executable OR folder
    """
    with _mt5_lock:
        # Initialize MT5 connection to the specified terminal
        print(f"[MT5] Initializing connection (terminal: {terminal_path})...")
        _init_mt5(terminal_path)
        print(f"[MT5] Connected successfully")
        
        try:
            # Get all available symbols (DON'T close connection)
            print(f"[MT5] Getting available symbols...")
            symbols = mt5.symbols_get(group="*")
            if symbols is None or len(symbols) == 0:
                symbols = mt5.symbols_get()
            
            if symbols is None or len(symbols) == 0:
                raise Exception("No symbols available in MT5. Make sure you're logged in.")
            
            symbol_names = [s.name for s in symbols]
            print(f"[MT5] Found {len(symbol_names)} symbols")
            
            # Find matching symbol using normalized lookup helper
            print(f"[MT5] Looking for symbol: {symbol}")
            actual_symbol = _normalize_and_find_symbol(symbol, symbol_names)
            
            if actual_symbol is None:
                # Show available gold symbols
                gold_symbols = [s for s in symbol_names if 'XAU' in s.upper() or 'GOLD' in s.upper()]
                error_msg = f"Symbol '{symbol}' not found.\n\n"
                if gold_symbols:
                    error_msg += f"Available gold symbols:\n" + "\n".join(f"  • {s}" for s in gold_symbols[:10])
                else:
                    error_msg += f"First 20 symbols: {symbol_names[:20]}"
                raise Exception(error_msg)
            
            print(f"[MT5] Using symbol: {actual_symbol}")
            
            # Get and enable symbol
            symbol_info = mt5.symbol_info(actual_symbol)
            if symbol_info is None:
                # Try to select/enable the symbol first
                print(f"[MT5] Symbol info not available, attempting to enable symbol...")
                if mt5.symbol_select(actual_symbol, True):
                    print(f"[MT5] Symbol enabled, retrying symbol_info...")
                    import time
                    time.sleep(0.5)  # Give it a moment to enable
                    symbol_info = mt5.symbol_info(actual_symbol)
                
                if symbol_info is None:
                    raise Exception(f"Symbol {actual_symbol} info not available even after enabling. Symbol may not be supported by this broker.")
            
            print(f"[MT5] Symbol info retrieved: {symbol_info.description}")
            
            # Ensure symbol is visible
            if not symbol_info.visible:
                print(f"[MT5] Symbol not visible, enabling it...")
                if not mt5.symbol_select(actual_symbol, True):
                    raise Exception(f"Failed to enable symbol {actual_symbol}")
                # Refresh symbol info after enabling
                import time
                time.sleep(0.5)
                symbol_info = mt5.symbol_info(actual_symbol)
            
            # Fetch rates
            print(f"[MT5] Fetching {bars} bars...")
            rates = mt5.copy_rates_from_pos(actual_symbol, timeframe, 0, bars)
            
            if rates is None or len(rates) == 0:
                error = mt5.last_error()
                raise Exception(f"No rates received for {actual_symbol}. Error: {error}")
            
            print(f"[MT5] Successfully fetched {len(rates)} bars")
            
            df = pd.DataFrame(rates)
            df["time"] = pd.to_datetime(df["time"], unit="s")
            
            return df
            
        finally:
            # Always close connection
            mt5.shutdown()
            print(f"[MT5] Connection closed")

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
    
    # SAFETY CHECK: Model should only predict 0-7 (8 regimes)
    if regime_id < 0 or regime_id > 7:
        print(f"[ERROR] Model predicted invalid regime: {regime_id}. Clamping to valid range.")
        regime_id = np.clip(regime_id, 0, 7)
    
    probabilities = get_model_probabilities(model, X_scaled)[0]
    confidence = float(np.max(probabilities) * 100)
    
    regime_name = REGIME_MAP.get(str(regime_id), {}).get(
        "name", REGIME_NAMES.get(regime_id, f"Regime {regime_id}"))
    
    return {
        "regime_id": int(regime_id),  # Ensure it's a Python int, not numpy int
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
    # Thread-safe signals for socket thread -> GUI communication
    sig_server_status = pyqtSignal(str, str)      # (text, color)
    sig_ea_connected = pyqtSignal(str)             # (address_str)
    sig_ea_disconnected = pyqtSignal(str)          # (address_str)
    sig_ea_registered = pyqtSignal()               # triggers table refresh
    sig_ea_trade_processed = pyqtSignal()          # triggers table refresh
    
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
        
        # Terminal and EA Management
        self.selected_terminal = None
        self.connected_eas = {}  # {ea_key: EAConfig}
        self.ea_socket_map = {}  # {ea_key: socket}
        
        # Thread-safe dashboard cache variables
        self.dashboard_symbol_cache = DEFAULT_SYMBOL
        self.selected_timeframe_val = mt5.TIMEFRAME_M5
        
        # Per-EA regime cache: {symbol: {"regime_id", "confidence", "probabilities", "timestamp"}}
        self._regime_cache = {}
        self._regime_cache_lock = threading.Lock()
        
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
        
        # Connect thread-safe signals to GUI slots
        self.sig_server_status.connect(self._on_server_status)
        self.sig_ea_connected.connect(self._on_ea_connected)
        self.sig_ea_disconnected.connect(self._on_ea_disconnected)
        self.sig_ea_registered.connect(self._on_ea_registered)
        self.sig_ea_trade_processed.connect(self._on_ea_trade_processed)
        
        # Start auto-refresh timer
        self.timer = QTimer()
        self.timer.timeout.connect(self.auto_refresh)
        self.timer.start(REFRESH_SECONDS * 1000)
        
        # Start socket server
        if SOCKET_ENABLED:
            self.start_socket_server()
        
        # Don't fetch data on startup - wait for terminal selection
        # User must select a terminal first
        print("[STARTUP] Dashboard ready. Please select a terminal to begin.")
    
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
        right_tabs.addTab(self.create_ea_management_panel(), "EA Management")
        right_tabs.addTab(self.create_statistics_panel(), "Statistics")
        right_tabs.addTab(self.create_directional_filter_panel(), "Directional Filter")
        splitter.addWidget(right_tabs)
        
        splitter.setSizes([1000, 600])
        main_layout.addWidget(splitter)
    
    def create_control_panel(self):
        """Create top control panel with symbol, timeframe, and refresh."""
        group = QGroupBox("Market Controls")
        layout = QHBoxLayout()
        
        # Terminal selector button
        self.select_terminal_btn = QPushButton("Select Terminal")
        self.select_terminal_btn.clicked.connect(self.show_terminal_selector)
        layout.addWidget(self.select_terminal_btn)
        
        self.terminal_label = QLabel("No terminal selected")
        self.terminal_label.setStyleSheet("color: #ffa500;")
        layout.addWidget(self.terminal_label)
        
        layout.addWidget(QLabel("|"))
        
        layout.addWidget(QLabel("Symbol:"))
        self.symbol_input = QLineEdit(DEFAULT_SYMBOL)
        self.symbol_input.setMaximumWidth(150)
        layout.addWidget(self.symbol_input)
        
        # Browse symbols button
        browse_symbols_btn = QPushButton("Browse...")
        browse_symbols_btn.setMaximumWidth(80)
        browse_symbols_btn.clicked.connect(self.show_symbol_browser)
        layout.addWidget(browse_symbols_btn)
        
        layout.addWidget(QLabel("Timeframe:"))
        self.timeframe_combo = QComboBox()
        self.timeframe_combo.addItems(self.timeframe_map.keys())
        self.timeframe_combo.setCurrentText("M5")
        self.timeframe_combo.setMaximumWidth(100)
        layout.addWidget(self.timeframe_combo)
        
        # Connect text/index changed listeners to maintain thread-safe cache
        self.symbol_input.textChanged.connect(self.on_symbol_changed)
        self.timeframe_combo.currentIndexChanged.connect(self.on_timeframe_changed)
        
        self.refresh_btn = QPushButton("Refresh Now")
        self.refresh_btn.clicked.connect(self.manual_refresh)
        layout.addWidget(self.refresh_btn)
        
        layout.addStretch()
        
        self.server_status_label = QLabel("Server: STOPPED")
        self.server_status_label.setStyleSheet("color: #ffa500; font-weight: bold;")
        layout.addWidget(self.server_status_label)
        
        self.ea_count_label = QLabel("EAs: 0 connected")
        self.ea_count_label.setStyleSheet("color: #808080;")
        layout.addWidget(self.ea_count_label)
        
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
    
    def create_ea_management_panel(self):
        """Create EA management panel for managing multiple EAs."""
        widget = QWidget()
        layout = QVBoxLayout()
        
        # Header
        header_label = QLabel("Connected Expert Advisors")
        header_label.setFont(QFont("Arial", 12, QFont.Bold))
        header_label.setStyleSheet("color: #4da6ff;")
        layout.addWidget(header_label)
        
        # EA table — enhanced with Terminal, Regime, Status, Trade Count
        self.ea_table = QTableWidget()
        self.ea_table.setColumnCount(8)
        self.ea_table.setHorizontalHeaderLabels([
            "EA Name", "Symbol", "Account", "Terminal",
            "Current Regime", "Status", "Trades", "Actions"
        ])
        self.ea_table.horizontalHeader().setStretchLastSection(False)
        self.ea_table.setColumnWidth(0, 140)
        self.ea_table.setColumnWidth(1, 90)
        self.ea_table.setColumnWidth(2, 90)
        self.ea_table.setColumnWidth(3, 140)
        self.ea_table.setColumnWidth(4, 180)
        self.ea_table.setColumnWidth(5, 90)
        self.ea_table.setColumnWidth(6, 60)
        self.ea_table.setColumnWidth(7, 100)
        self.ea_table.setEditTriggers(QTableWidget.NoEditTriggers)
        layout.addWidget(self.ea_table)
        
        # Buttons
        button_layout = QHBoxLayout()
        
        refresh_ea_btn = QPushButton("Refresh EA List")
        refresh_ea_btn.clicked.connect(self.refresh_ea_table)
        button_layout.addWidget(refresh_ea_btn)
        
        button_layout.addStretch()
        layout.addLayout(button_layout)
        
        # Info
        info_text = QLabel(
            "Note: EAs automatically register when they connect to the dashboard. "
            "Configure each EA individually to set different filter rules.\n"
            "Each EA's regime is fetched for its specific symbol — different symbols get different regime predictions."
        )
        info_text.setWordWrap(True)
        info_text.setStyleSheet("color: #808080; font-size: 9pt;")
        layout.addWidget(info_text)
        
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
        # Check if terminal is selected
        if not self.selected_terminal:
            print("[UPDATE] No terminal selected. Please select a terminal first.")
            QMessageBox.warning(
                self,
                "No Terminal Selected",
                "Please select a MetaTrader terminal first using the 'Select Terminal' button."
            )
            return
        
        symbol = self.dashboard_symbol_cache
        timeframe = self.selected_timeframe_val
        
        # Get terminal path
        terminal_path = self.selected_terminal.get('path')
        
        self.refresh_btn.setEnabled(False)
        self.refresh_btn.setText("Updating...")
        
        try:
            print(f"[UPDATE] Fetching data for {symbol} from terminal: {terminal_path}")
            df = fetch_market_data(symbol, timeframe, DEFAULT_BARS, terminal_path)
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
    
    def on_symbol_changed(self):
        """Update dashboard symbol cache thread-safely."""
        self.dashboard_symbol_cache = self.symbol_input.text().strip()
        
    def on_timeframe_changed(self):
        """Update selected timeframe cache thread-safely."""
        tf_name = self.timeframe_combo.currentText()
        self.selected_timeframe_val = self.timeframe_map.get(tf_name, mt5.TIMEFRAME_M5)
        print(f"[TIMEFRAME] Changed to {tf_name} ({self.selected_timeframe_val})")
    
    # =============================================================
    # TERMINAL SELECTION
    # =============================================================
    
    def show_terminal_selector(self):
        """Show terminal selector dialog."""
        dialog = TerminalSelectorDialog(self)
        if dialog.exec_() == QDialog.Accepted and dialog.selected_terminal:
            self.selected_terminal = dialog.selected_terminal
            self.terminal_label.setText(f"{dialog.selected_terminal['name']}")
            self.terminal_label.setStyleSheet("color: #00ff00; font-weight: bold;")
            print(f"[TERMINAL] Selected: {dialog.selected_terminal['name']}")
            
            # Now that terminal is selected, do initial data fetch
            print("[TERMINAL] Fetching initial market data...")
            self.manual_refresh()
            
            # Show success message
            QMessageBox.information(
                self,
                "Terminal Connected",
                f"Using terminal: {dialog.selected_terminal['name']}\n\nFetching market data..."
            )
    
    def show_symbol_browser(self):
        """Show symbol browser dialog."""
        if not self.selected_terminal:
            QMessageBox.warning(
                self,
                "No Terminal Selected",
                "Please select a terminal first before browsing symbols."
            )
            return
        
        # Pass terminal path to dialog
        dialog = SymbolBrowserDialog(self, self.selected_terminal.get('path'))
        if dialog.exec_() == QDialog.Accepted and dialog.selected_symbol:
            self.symbol_input.setText(dialog.selected_symbol)
            print(f"[SYMBOL] Selected: {dialog.selected_symbol}")
    
    # =============================================================
    # EA MANAGEMENT
    # =============================================================
    
    def register_ea(self, ea_name, symbol, account, terminal, client_socket):
        """Register a new EA connection."""
        ea_key = f"{ea_name}_{symbol}_{account}"
        if ea_key not in self.connected_eas:
            ea_config = EAConfig(ea_name, symbol, account, terminal)
            self.connected_eas[ea_key] = ea_config
            self.ea_socket_map[ea_key] = client_socket
            print(f"[EA] Registered: {ea_name} ({symbol}, {account}) - Key: {ea_key}")
        else:
            # Update existing EA
            self.connected_eas[ea_key].connected = True
            self.connected_eas[ea_key].symbol = symbol
            self.connected_eas[ea_key].account = account
            self.connected_eas[ea_key].terminal = terminal
            self.ea_socket_map[ea_key] = client_socket
            print(f"[EA] Reconnected: {ea_name} ({symbol}, {account}) - Key: {ea_key}")
    
    def unregister_ea(self, ea_key):
        """Unregister an EA connection."""
        if ea_key in self.connected_eas:
            self.connected_eas[ea_key].connected = False
            if ea_key in self.ea_socket_map:
                del self.ea_socket_map[ea_key]
            print(f"[EA] Disconnected: {ea_key}")
    
    def update_ea_count(self):
        """Update EA count display and show active EA names."""
        connected_eas_list = [ea.ea_name for ea in self.connected_eas.values() if ea.connected]
        connected_count = len(connected_eas_list)
        
        if connected_count > 0:
            names_str = ", ".join(connected_eas_list)
            self.ea_count_label.setText(f"EAs: {connected_count} connected ({names_str})")
            self.ea_count_label.setStyleSheet("color: #00ff00; font-weight: bold;")
            self.ea_count_label.setToolTip(f"Connected EAs:\n" + "\n".join(f"• {name}" for name in connected_eas_list))
        else:
            self.ea_count_label.setText("EAs: 0 connected")
            self.ea_count_label.setStyleSheet("color: #808080;")
            self.ea_count_label.setToolTip("No EAs connected")
    
    def refresh_ea_table(self):
        """Refresh EA management table with enhanced columns."""
        self.ea_table.setRowCount(0)
        
        for ea_key, ea_config in self.connected_eas.items():
            row = self.ea_table.rowCount()
            self.ea_table.insertRow(row)
            
            # EA Name
            name_item = QTableWidgetItem(ea_config.ea_name)
            if ea_config.connected:
                name_item.setForeground(QColor("#00ff00"))
            else:
                name_item.setForeground(QColor("#808080"))
            self.ea_table.setItem(row, 0, name_item)
            
            # Symbol
            self.ea_table.setItem(row, 1, QTableWidgetItem(ea_config.symbol))
            
            # Account
            self.ea_table.setItem(row, 2, QTableWidgetItem(ea_config.account))
            
            # Terminal
            terminal_item = QTableWidgetItem(ea_config.terminal[:30] if ea_config.terminal else "N/A")
            terminal_item.setToolTip(ea_config.terminal or "N/A")
            self.ea_table.setItem(row, 3, terminal_item)
            
            # Current Regime — look up from cache
            regime_text = "--"
            regime_color = "#808080"
            with self._regime_cache_lock:
                cached = self._regime_cache.get(ea_config.symbol)
            if cached:
                rid = cached["regime_id"]
                regime_text = REGIME_NAMES.get(rid, f"Regime {rid}")
                regime_color = REGIME_COLORS.get(rid, "#ffffff")
            regime_item = QTableWidgetItem(regime_text)
            regime_item.setForeground(QColor(regime_color))
            self.ea_table.setItem(row, 4, regime_item)
            
            # Status
            if ea_config.connected:
                status_item = QTableWidgetItem("● Connected")
                status_item.setForeground(QColor("#00ff00"))
            else:
                status_item = QTableWidgetItem("○ Offline")
                status_item.setForeground(QColor("#808080"))
            self.ea_table.setItem(row, 5, status_item)
            
            # Trade Count
            trades_item = QTableWidgetItem(str(ea_config.trade_count))
            self.ea_table.setItem(row, 6, trades_item)
            
            # Configure button
            config_btn = QPushButton("Configure")
            config_btn.clicked.connect(lambda checked, key=ea_key: self.configure_ea(key))
            self.ea_table.setCellWidget(row, 7, config_btn)
    
    def configure_ea(self, ea_key):
        """Show configuration dialog for an EA."""
        if ea_key not in self.connected_eas:
            return
        
        ea_config = self.connected_eas[ea_key]
        dialog = EAConfigDialog(ea_config, self)
        
        if dialog.exec_() == QDialog.Accepted:
            print(f"[EA CONFIG] Updated configuration for {ea_config.ea_name}")
            print(f"  Allowed regimes: {ea_config.allowed_regimes}")
            print(f"  Min confidence: {ea_config.min_confidence}%")
            print(f"  Directional filter: {ea_config.directional_mode}")
            print(f"  Volatility filter: {'ON' if ea_config.use_volatility_filter else 'OFF'}")
            self.refresh_ea_table()
    
    def get_ea_config(self, ea_name, symbol="", account=""):
        """Get EA configuration by name, symbol, and account."""
        ea_key = f"{ea_name}_{symbol}_{account}"
        if ea_key in self.connected_eas:
            return self.connected_eas[ea_key]
            
        # Fallback to name/symbol match
        for config in self.connected_eas.values():
            if config.ea_name == ea_name:
                if symbol and config.symbol.upper() == symbol.upper():
                    return config
                    
        # Fallback to name-only match
        for config in self.connected_eas.values():
            if config.ea_name == ea_name:
                return config
                
        return None
    
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
        """Socket server main loop. Runs in a background thread."""
        try:
            self.socket_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.socket_server.bind((SOCKET_HOST, SOCKET_PORT))
            self.socket_server.listen(5)
            self.socket_server.settimeout(1.0)
            
            self.server_running = True
            # Thread-safe GUI update via signal
            self.sig_server_status.emit(f"Server: RUNNING on {SOCKET_PORT}", "#00ff00")
            
            while self.running and self.server_running:
                try:
                    client_socket, address = self.socket_server.accept()
                    print(f"[SERVER] EA connected from {address}")
                    # Thread-safe GUI update via signal
                    self.sig_ea_connected.emit(f"{address[0]}:{address[1]}")
                    
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
            # Thread-safe GUI update via signal
            self.sig_server_status.emit("Server: ERROR", "#ff0000")
        
        finally:
            if self.socket_server:
                self.socket_server.close()
            self.server_running = False
    
    def handle_client(self, client_socket, address):
        """Handle EA client connection. Runs in a background thread."""
        ea_key_for_cleanup = None
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
                            result_ea_key = self.process_ea_request(client_socket, line.strip())
                            if result_ea_key:
                                ea_key_for_cleanup = result_ea_key
                
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"[SERVER] Client error: {e}")
                    break
        
        finally:
            client_socket.close()
            # Unregister EA if we know its key
            if ea_key_for_cleanup:
                self.unregister_ea(ea_key_for_cleanup)
            # Thread-safe GUI update via signal
            self.sig_ea_disconnected.emit(f"{address[0]}:{address[1]}")
            print(f"[SERVER] EA disconnected from {address}")
    
    # =============================================================
    # THREAD-SAFE SIGNAL SLOTS (run on main GUI thread)
    # =============================================================
    
    def _on_server_status(self, text, color):
        """Handle server status update from socket thread."""
        self.server_status_label.setText(text)
        self.server_status_label.setStyleSheet(f"color: {color}; font-weight: bold;")
    
    def _on_ea_connected(self, address_str):
        """Handle EA connection event from socket thread."""
        self.update_ea_count()
    
    def _on_ea_disconnected(self, address_str):
        """Handle EA disconnection event from socket thread."""
        self.update_ea_count()
        self.refresh_ea_table()
    
    def _on_ea_registered(self):
        """Handle EA registration event from socket thread."""
        self.refresh_ea_table()
        self.update_ea_count()
    
    def _on_ea_trade_processed(self):
        """Handle EA trade processed event from socket thread."""
        self.refresh_ea_table()
    
    def _get_regime_for_symbol(self, symbol, terminal_path=None):
        """Get regime prediction for a specific symbol, using cache with TTL.
        
        This enables per-EA regime filtering: each EA trading a different
        symbol gets the correct regime for that symbol.
        
        Args:
            symbol: The symbol to get regime for
            terminal_path: Path to the MT5 terminal (uses selected terminal if None)
        
        Returns:
            dict with regime_id, confidence, probabilities or None on error
        """
        now = time.time()
        
        # Check cache
        with self._regime_cache_lock:
            cached = self._regime_cache.get(symbol)
            if cached and (now - cached["timestamp"]) < REGIME_CACHE_TTL:
                return cached
        
        # Fetch fresh data
        if terminal_path is None and self.selected_terminal:
            terminal_path = self.selected_terminal.get('path')
        
        try:
            timeframe = self.selected_timeframe_val
            df = fetch_market_data(symbol, timeframe, DEFAULT_BARS, terminal_path)
            result = predict_regime(df)
            
            cache_entry = {
                "regime_id": result['regime_id'],
                "confidence": result['confidence'],
                "probabilities": result['probabilities'],
                "timestamp": now
            }
            
            # Store in cache
            with self._regime_cache_lock:
                self._regime_cache[symbol] = cache_entry
            
            print(f"[REGIME CACHE] {symbol}: Regime {result['regime_id']} "
                  f"(R{result['regime_id']+1}), Confidence {result['confidence']:.1f}%")
            
            return cache_entry
            
        except Exception as e:
            print(f"[REGIME CACHE] Error fetching regime for {symbol}: {e}")
            # Return stale cache if available
            with self._regime_cache_lock:
                return self._regime_cache.get(symbol)
    
    def process_ea_request(self, client_socket, message):
        """Process trade request from EA. Runs in socket thread.
        
        Returns:
            ea_key if this was a handshake (for cleanup on disconnect), else None
        """
        try:
            data = json.loads(message)
            msg_type = data.get("type", "")
            
            if msg_type == "trade_request":
                symbol = data.get("symbol", "")
                action = data.get("action", "").lower()
                ea_name = data.get("ea_name", "UnknownEA")
                account = str(data.get("account", ""))
                
                # Get EA-specific configuration
                ea_config = self.get_ea_config(ea_name, symbol, account)
                
                # Fetch regime for the EA's SPECIFIC symbol (not the dashboard symbol)
                regime_data = self._get_regime_for_symbol(symbol)
                
                if regime_data is None:
                    # FIXED: Block trades when no regime data is available (EA needs to warm up first)
                    response = {
                        "allow_trade": False,
                        "regime": -1,
                        "confidence": 0.0,
                        "reason": f"No regime data available for {symbol} - waiting for warmup to complete"
                    }
                else:
                    current_regime = regime_data["regime_id"]
                    current_confidence = regime_data["confidence"]
                    
                    # Also update the dashboard display if this is the dashboard symbol
                    dashboard_symbol = self.dashboard_symbol_cache
                    if symbol.upper() == dashboard_symbol.upper():
                        self.current_regime = current_regime
                        self.current_confidence = current_confidence
                        self.current_probabilities = regime_data["probabilities"]
                    
                    # Use EA-specific configuration if available, otherwise use global config
                    if ea_config:
                        allow_trade = ea_config.allows_regime(current_regime)
                        use_dir_filter = ea_config.use_directional_filter
                        dir_mode = ea_config.directional_mode
                        min_conf = ea_config.min_confidence
                        
                        # Update EA trade count
                        ea_config.trade_count += 1
                        ea_config.last_trade_time = time.time()
                    else:
                        # Fallback to global config
                        allow_trade = REGIME_FILTER_CONFIG.get(current_regime, True)
                        use_dir_filter = USE_DIRECTIONAL_FILTER
                        dir_mode = DIRECTIONAL_FILTER_MODE
                        min_conf = 50.0
                    
                    block_reason = ""
                    
                    print(f"[DEBUG] Checking trade for EA '{ea_name}': Symbol={symbol}, Action={action}, Regime={current_regime} (Display: R{current_regime+1}), FilterConfig={allow_trade}")
                    
                    if not allow_trade:
                        block_reason = f"Regime {current_regime+1} is disabled in EA filter config"
                    
                    # Check confidence threshold
                    if allow_trade and current_confidence < min_conf:
                        allow_trade = False
                        block_reason = f"Confidence {current_confidence:.1f}% below minimum {min_conf}%"
                    
                    # Check directional filter
                    if allow_trade and use_dir_filter and dir_mode != "disabled":
                        regime_direction = REGIME_DIRECTION.get(current_regime, "neutral")
                        
                        print(f"[DEBUG] Directional Filter: Regime={current_regime} (R{current_regime+1}), Direction={regime_direction}, Action={action}, Mode={dir_mode}")
                        
                        if dir_mode == "strict":
                            if regime_direction == "bullish" and action == "sell":
                                allow_trade = False
                                block_reason = f"Regime {current_regime+1} is BULLISH, SELL blocked (counter-trend)"
                            elif regime_direction == "bearish" and action == "buy":
                                allow_trade = False
                                block_reason = f"Regime {current_regime+1} is BEARISH, BUY blocked (counter-trend)"
                            elif regime_direction == "neutral":
                                allow_trade = False
                                block_reason = f"Regime {current_regime+1} is NEUTRAL (no clear direction in strict mode)"
                        
                        elif dir_mode == "allow_neutral":
                            if regime_direction == "bullish" and action == "sell":
                                allow_trade = False
                                block_reason = f"Regime {current_regime+1} is BULLISH, SELL blocked (counter-trend)"
                            elif regime_direction == "bearish" and action == "buy":
                                allow_trade = False
                                block_reason = f"Regime {current_regime+1} is BEARISH, BUY blocked (counter-trend)"
                    
                    if allow_trade:
                        reason = f"EA '{ea_name}': {symbol} Regime {current_regime+1} ({REGIME_DIRECTION.get(current_regime, 'unknown')}): {action.upper()} ALLOWED"
                    else:
                        reason = f"EA '{ea_name}': {block_reason}"
                    
                    response = {
                        "allow_trade": allow_trade,
                        "regime": int(current_regime),
                        "confidence": float(current_confidence),
                        "reason": reason
                    }
                    
                    print(f"[TRADE] EA '{ea_name}': {action.upper()} on {symbol} -> "
                          f"Regime {current_regime} (Display: R{current_regime+1}, {REGIME_DIRECTION.get(current_regime, 'unknown')}, {current_confidence:.1f}%) -> "
                          f"{'ALLOWED ✓' if allow_trade else 'BLOCKED ✗'}")
                    if not allow_trade:
                        print(f"  Reason: {block_reason}")
                
                response_json = json.dumps(response) + "\n"
                client_socket.sendall(response_json.encode('utf-8'))
                
                # Signal GUI to update EA table (thread-safe)
                self.sig_ea_trade_processed.emit()
                return None
            
            elif msg_type == "handshake":
                terminal = data.get("terminal", "Unknown")
                ea_name = data.get("ea_name", "UnknownEA")
                symbol = data.get("symbol", "")
                account = str(data.get("account", ""))
                
                print(f"[HANDSHAKE] EA connected: {ea_name} on {terminal} (symbol={symbol}, account={account})")
                
                # Register EA
                self.register_ea(ea_name, symbol, account, terminal, client_socket)
                
                # Signal GUI to update EA table (thread-safe)
                self.sig_ea_registered.emit()
                
                response = {
                    "status": "connected",
                    "message": f"Dashboard ready. EA '{ea_name}' registered."
                }
                response_json = json.dumps(response) + "\n"
                client_socket.sendall(response_json.encode('utf-8'))
                return f"{ea_name}_{symbol}_{account}"
        
        except json.JSONDecodeError:
            print(f"[SERVER] Invalid JSON: {message}")
        except Exception as e:
            print(f"[SERVER] Error processing request: {e}")
        
        return None
    
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
