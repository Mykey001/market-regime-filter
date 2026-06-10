"""
Market Regime Trading GUI
=========================
Professional trading interface that:
- Connects to MetaTrader 4/5 via socket communication
- Tracks market regimes in real-time
- Filters EA trades based on regime configuration
- Displays live regime predictions and confidence

Author: Market Regime Detection System
Version: 1.0
Date: June 2026
"""

import sys
import os
import threading
import queue
import socket
import json
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import joblib
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QTableWidget, QTableWidgetItem, QGroupBox,
    QComboBox, QSpinBox, QCheckBox, QTextEdit, QTabWidget,
    QGridLayout, QLineEdit, QMessageBox, QStatusBar, QProgressBar
)
from PyQt5.QtCore import QTimer, Qt, pyqtSignal, QObject
from PyQt5.QtGui import QFont, QColor

# Import feature engine
from feature_engine import (
    compute_all_features, get_feature_matrix, FEATURE_NAMES,
    MIN_WARMUP
)


# ============================================================
# CONSTANTS
# ============================================================

REGIME_NAMES = {
    0: "High Vol Trending",
    1: "Normal/Calm",
    2: "Volatile Expansion",
    3: "Bullish Trending",
    4: "Extreme Vol Spike",
    5: "Crisis Mode",
    6: "High Vol Consolidation",
    7: "Bearish Trending",
    8: "Bullish Momentum",
    9: "Choppy/Erratic",
}

REGIME_COLORS = {
    0: "#FFA500",  # Orange
    1: "#90EE90",  # Light green
    2: "#FFD700",  # Gold
    3: "#32CD32",  # Lime green
    4: "#FF6347",  # Tomato
    5: "#DC143C",  # Crimson
    6: "#FF8C00",  # Dark orange
    7: "#FF4500",  # Orange red
    8: "#00FF00",  # Green
    9: "#8B4513",  # Saddle brown
}

DEFAULT_PORT = 9090
DEFAULT_HOST = "127.0.0.1"


# ============================================================
# MT4/MT5 SOCKET BRIDGE
# ============================================================

class MTBridge(QObject):
    """Handles socket communication with MetaTrader EA."""
    
    data_received = pyqtSignal(dict)
    connection_status = pyqtSignal(bool, str)
    terminal_connected = pyqtSignal(str, str)  # terminal_name, symbol
    
    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT):
        super().__init__()
        self.host = host
        self.port = port
        self.server_socket = None
        self.client_sockets = {}  # {terminal_id: socket}
        self.terminal_info = {}   # {terminal_id: {name, symbol, account}}
        self.is_running = False
        self.thread = None
        self.selected_terminal = None
        
    def start(self):
        """Start socket server in separate thread."""
        if self.is_running:
            return
        
        self.is_running = True
        self.thread = threading.Thread(target=self._run_server, daemon=True)
        self.thread.start()
    
    def stop(self):
        """Stop socket server."""
        self.is_running = False
        for terminal_id, sock in list(self.client_sockets.items()):
            try:
                sock.close()
            except:
                pass
        self.client_sockets.clear()
        self.terminal_info.clear()
        
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
    
    def _run_server(self):
        """Run socket server loop."""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(5)  # Allow multiple connections
            self.server_socket.settimeout(1.0)
            
            self.connection_status.emit(True, f"Listening on {self.host}:{self.port}")
            
            while self.is_running:
                try:
                    # Accept new connections
                    client_sock, addr = self.server_socket.accept()
                    client_sock.settimeout(0.1)
                    
                    # Create terminal ID from address
                    terminal_id = f"{addr[0]}:{addr[1]}"
                    self.client_sockets[terminal_id] = client_sock
                    
                    self.connection_status.emit(True, f"EA connected from {addr[0]}:{addr[1]}")
                    
                    # Handle this client in a separate method
                    threading.Thread(target=self._handle_client, 
                                   args=(terminal_id, client_sock), 
                                   daemon=True).start()
                    
                except socket.timeout:
                    continue
                except Exception as e:
                    if self.is_running:
                        print(f"Accept error: {e}")
        
        except Exception as e:
            self.connection_status.emit(False, f"Server error: {str(e)}")
    
    def _handle_client(self, terminal_id, client_sock):
        """Handle individual client connection."""
        try:
            buffer = ""
            while self.is_running and terminal_id in self.client_sockets:
                try:
                    data = client_sock.recv(4096)
                    if not data:
                        break
                    
                    buffer += data.decode('utf-8')
                    
                    # Process complete messages (ending with \n)
                    while '\n' in buffer:
                        message, buffer = buffer.split('\n', 1)
                        if message.strip():
                            try:
                                msg = json.loads(message)
                                msg['terminal_id'] = terminal_id
                                
                                # Handle handshake
                                if msg.get('type') == 'handshake':
                                    self.terminal_info[terminal_id] = {
                                        'name': msg.get('terminal', 'Unknown'),
                                        'symbol': msg.get('symbol', ''),
                                        'account': msg.get('account', '')
                                    }
                                    self.terminal_connected.emit(
                                        self.terminal_info[terminal_id]['name'],
                                        self.terminal_info[terminal_id]['symbol']
                                    )
                                
                                self.data_received.emit(msg)
                            except json.JSONDecodeError as e:
                                print(f"JSON decode error: {e}")
                
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"Receive error: {e}")
                    break
            
            # Cleanup
            client_sock.close()
            if terminal_id in self.client_sockets:
                del self.client_sockets[terminal_id]
            if terminal_id in self.terminal_info:
                del self.terminal_info[terminal_id]
            
            self.connection_status.emit(False, f"EA disconnected: {terminal_id}")
            
        except Exception as e:
            print(f"Client handler error: {e}")
    
    def send_trade_decision(self, allow_trade: bool, regime: int, confidence: float, terminal_id=None):
        """Send trade decision back to EA."""
        if not terminal_id:
            terminal_id = self.selected_terminal
        
        if not terminal_id or terminal_id not in self.client_sockets:
            return False
        
        try:
            response = {
                "allow_trade": allow_trade,
                "regime": int(regime),
                "confidence": float(confidence),
                "timestamp": datetime.now().isoformat()
            }
            message = json.dumps(response) + "\n"
            self.client_sockets[terminal_id].sendall(message.encode('utf-8'))
            return True
        except Exception as e:
            print(f"Send error: {e}")
            return False
    
    def get_connected_terminals(self):
        """Get list of connected terminals."""
        return [(tid, info) for tid, info in self.terminal_info.items()]


# ============================================================
# REGIME PREDICTOR
# ============================================================

class RegimePredictor:
    """Real-time regime prediction engine."""
    
    def __init__(self, model_path="market_regime_gmm.pkl", scaler_path="scaler.pkl"):
        self.model = joblib.load(model_path)
        self.scaler = joblib.load(scaler_path)
        self.data_buffer = []
        self.current_regime = None
        self.regime_confidence = 0.0
        self.regime_probabilities = None
        
        # CACHE: Store last prediction to avoid unnecessary recalculation
        self._last_buffer_size = 0
        self._cached_regime = None
        self._cached_confidence = 0.0
        self._cached_probs = None
        
    def add_bar(self, bar_data: dict):
        """Add new M5 bar to buffer.
        
        Args:
            bar_data: Dict with keys: time, open, high, low, close, tickvol, spread
        """
        self.data_buffer.append(bar_data)
        
        # Keep only necessary history (warmup + some extra)
        if len(self.data_buffer) > MIN_WARMUP + 500:
            self.data_buffer = self.data_buffer[-(MIN_WARMUP + 500):]
    
    def predict(self, force_recalculate=False) -> tuple:
        """Predict current regime.
        
        Args:
            force_recalculate: If True, recalculate even if buffer unchanged
        
        Returns:
            Tuple of (regime_id, confidence, all_probabilities)
            Returns (None, 0.0, None) if insufficient data.
        """
        # OPTIMIZATION: Return cached prediction if buffer hasn't changed
        # This prevents regime flipping when auto-refresh calls predict() 
        # on the same data every 10 seconds
        if not force_recalculate and len(self.data_buffer) == self._last_buffer_size:
            if self._cached_regime is not None:
                print(f"[CACHE] Using cached prediction: Regime {self._cached_regime}")
                return self._cached_regime, self._cached_confidence, self._cached_probs
        
        if len(self.data_buffer) < MIN_WARMUP:
            return None, 0.0, None
        
        try:
            # Convert buffer to DataFrame
            df = pd.DataFrame(self.data_buffer)
            
            # Compute features
            df_features = compute_all_features(df)
            
            # Extract last valid row
            X, valid_df = get_feature_matrix(df_features, drop_na=True)
            
            if len(X) == 0:
                return None, 0.0, None
            
            # Get last row (current state)
            X_current = X[-1:, :]
            
            # Scale and predict
            X_scaled = self.scaler.transform(X_current)
            regime = self.model.predict(X_scaled)[0]
            probs = self.model.predict_proba(X_scaled)[0]
            confidence = probs[regime]
            
            # Update state
            self.current_regime = regime
            self.regime_confidence = confidence
            self.regime_probabilities = probs
            
            # CACHE the prediction
            self._last_buffer_size = len(self.data_buffer)
            self._cached_regime = regime
            self._cached_confidence = confidence
            self._cached_probs = probs
            
            print(f"[PREDICT] Recalculated: Regime {regime}, Confidence {confidence:.1%}, Buffer: {len(self.data_buffer)} bars")
            
            return regime, confidence, probs
        
        except Exception as e:
            print(f"Prediction error: {e}")
            return None, 0.0, None
    
    def get_regime_history(self, window=100) -> list:
        """Get regime predictions for recent history."""
        if len(self.data_buffer) < MIN_WARMUP:
            return []
        
        try:
            df = pd.DataFrame(self.data_buffer)
            df_features = compute_all_features(df)
            X, valid_df = get_feature_matrix(df_features, drop_na=True)
            
            if len(X) == 0:
                return []
            
            # Get last N predictions
            X_window = X[-window:] if len(X) > window else X
            X_scaled = self.scaler.transform(X_window)
            regimes = self.model.predict(X_scaled)
            
            return regimes.tolist()
        
        except Exception as e:
            print(f"History error: {e}")
            return []


# ============================================================
# MAIN GUI APPLICATION
# ============================================================

class RegimeTradingGUI(QMainWindow):
    """Main trading GUI window."""
    
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Market Regime Trading Control Center")
        self.setGeometry(100, 100, 1400, 900)
        
        # Initialize components
        self.bridge = MTBridge()
        self.predictor = None
        self.trade_log = []
        self.regime_filter_config = {i: True for i in range(10)}
        self.min_confidence = 0.5
        self.auto_mode = True
        self.terminal_predictors = {}  # {terminal_id: RegimePredictor}
        
        # Setup UI
        self.init_ui()
        
        # Connect signals
        self.bridge.data_received.connect(self.handle_mt_data)
        self.bridge.connection_status.connect(self.update_connection_status)
        self.bridge.terminal_connected.connect(self.on_terminal_connected)
        
        # Timer for UI updates (buffer status, etc)
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.update_displays)
        self.update_timer.start(1000)  # Update every second
        
        # Timer for regime monitor refresh (probabilities, etc)
        self.regime_refresh_timer = QTimer()
        self.regime_refresh_timer.timeout.connect(self.refresh_regime_monitor)
        self.regime_refresh_timer.start(10000)  # Refresh every 10 seconds
        
        # Try to load model
        self.load_model()
    
    def init_ui(self):
        """Initialize user interface."""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        # Main layout
        main_layout = QVBoxLayout(central_widget)
        
        # Top control bar
        control_bar = self.create_control_bar()
        main_layout.addWidget(control_bar)
        
        # Tab widget for different views
        tabs = QTabWidget()
        tabs.addTab(self.create_regime_monitor_tab(), "Regime Monitor")
        tabs.addTab(self.create_filter_config_tab(), "Filter Configuration")
        tabs.addTab(self.create_trade_log_tab(), "Trade Log")
        tabs.addTab(self.create_statistics_tab(), "Statistics")
        
        main_layout.addWidget(tabs)
        
        # Status bar
        self.statusBar = QStatusBar()
        self.setStatusBar(self.statusBar)
        self.statusBar.showMessage("Ready")
    
    def create_control_bar(self) -> QWidget:
        """Create top control bar."""
        group = QGroupBox("Connection & Control")
        layout = QHBoxLayout()
        
        # Connection controls
        self.host_input = QLineEdit(DEFAULT_HOST)
        self.host_input.setMaximumWidth(120)
        self.port_input = QSpinBox()
        self.port_input.setRange(1024, 65535)
        self.port_input.setValue(DEFAULT_PORT)
        self.port_input.setMaximumWidth(80)
        
        self.connect_btn = QPushButton("Start Server")
        self.connect_btn.clicked.connect(self.toggle_connection)
        
        self.connection_status_label = QLabel("●")
        self.connection_status_label.setStyleSheet("color: red; font-size: 20px;")
        
        layout.addWidget(QLabel("Host:"))
        layout.addWidget(self.host_input)
        layout.addWidget(QLabel("Port:"))
        layout.addWidget(self.port_input)
        layout.addWidget(self.connect_btn)
        layout.addWidget(self.connection_status_label)
        layout.addWidget(QLabel("|"))
        
        # Terminal selection
        layout.addWidget(QLabel("Terminal:"))
        self.terminal_combo = QComboBox()
        self.terminal_combo.setMinimumWidth(200)
        self.terminal_combo.addItem("No terminals connected", None)
        self.terminal_combo.currentIndexChanged.connect(self.on_terminal_selected)
        layout.addWidget(self.terminal_combo)
        layout.addWidget(QLabel("|"))
        
        # Auto/Manual mode
        self.auto_checkbox = QCheckBox("Auto Mode")
        self.auto_checkbox.setChecked(True)
        self.auto_checkbox.stateChanged.connect(self.toggle_auto_mode)
        layout.addWidget(self.auto_checkbox)
        
        layout.addStretch()
        
        # Model status
        self.model_status_label = QLabel("Model: Not Loaded")
        self.model_status_label.setStyleSheet("color: red;")
        layout.addWidget(self.model_status_label)
        
        group.setLayout(layout)
        return group
    
    def create_regime_monitor_tab(self) -> QWidget:
        """Create regime monitoring tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        
        # Current regime display
        regime_group = QGroupBox("Current Market Regime")
        regime_layout = QGridLayout()
        
        self.regime_label = QLabel("---")
        self.regime_label.setFont(QFont("Arial", 24, QFont.Bold))
        self.regime_label.setAlignment(Qt.AlignCenter)
        regime_layout.addWidget(QLabel("Regime:"), 0, 0)
        regime_layout.addWidget(self.regime_label, 0, 1)
        
        self.confidence_label = QLabel("---%")
        self.confidence_label.setFont(QFont("Arial", 20))
        self.confidence_label.setAlignment(Qt.AlignCenter)
        regime_layout.addWidget(QLabel("Confidence:"), 1, 0)
        regime_layout.addWidget(self.confidence_label, 1, 1)
        
        self.trade_status_label = QLabel("UNKNOWN")
        self.trade_status_label.setFont(QFont("Arial", 18, QFont.Bold))
        self.trade_status_label.setAlignment(Qt.AlignCenter)
        self.trade_status_label.setStyleSheet("color: gray;")
        regime_layout.addWidget(QLabel("Trade Status:"), 2, 0)
        regime_layout.addWidget(self.trade_status_label, 2, 1)
        
        regime_group.setLayout(regime_layout)
        layout.addWidget(regime_group)
        
        # Regime probabilities table
        probs_group = QGroupBox("Regime Probabilities")
        probs_layout = QVBoxLayout()
        
        self.probs_table = QTableWidget(10, 3)
        self.probs_table.setHorizontalHeaderLabels(["Regime", "Name", "Probability"])
        self.probs_table.setMaximumHeight(350)
        
        # Populate regime names
        for i in range(10):
            self.probs_table.setItem(i, 0, QTableWidgetItem(str(i)))
            self.probs_table.setItem(i, 1, QTableWidgetItem(REGIME_NAMES[i]))
        
        probs_layout.addWidget(self.probs_table)
        probs_group.setLayout(probs_layout)
        layout.addWidget(probs_group)
        
        # Data buffer status
        self.buffer_label = QLabel("Data Buffer: 0 bars (need 626 for warmup)")
        layout.addWidget(self.buffer_label)
        
        self.buffer_progress = QProgressBar()
        self.buffer_progress.setRange(0, MIN_WARMUP)
        self.buffer_progress.setValue(0)
        layout.addWidget(self.buffer_progress)
        
        layout.addStretch()
        return widget
    
    def create_filter_config_tab(self) -> QWidget:
        """Create filter configuration tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        
        # Instructions
        instructions = QLabel(
            "Configure which regimes are allowed to trade. "
            "When a regime is unchecked, all trade signals from the EA will be blocked."
        )
        instructions.setWordWrap(True)
        layout.addWidget(instructions)
        
        # Minimum confidence slider
        conf_group = QGroupBox("Minimum Confidence Threshold")
        conf_layout = QHBoxLayout()
        
        self.confidence_spinbox = QSpinBox()
        self.confidence_spinbox.setRange(0, 100)
        self.confidence_spinbox.setValue(50)
        self.confidence_spinbox.setSuffix("%")
        self.confidence_spinbox.valueChanged.connect(self.update_min_confidence)
        
        conf_layout.addWidget(QLabel("Minimum Confidence:"))
        conf_layout.addWidget(self.confidence_spinbox)
        conf_layout.addStretch()
        conf_group.setLayout(conf_layout)
        layout.addWidget(conf_group)
        
        # Regime checkboxes
        filter_group = QGroupBox("Allowed Regimes")
        filter_layout = QGridLayout()
        
        self.regime_checkboxes = {}
        for i in range(10):
            cb = QCheckBox(f"{i}: {REGIME_NAMES[i]}")
            cb.setChecked(True)
            cb.stateChanged.connect(lambda state, idx=i: self.update_regime_filter(idx, state))
            
            # Color indicator
            color_label = QLabel("●")
            color_label.setStyleSheet(f"color: {REGIME_COLORS[i]}; font-size: 16px;")
            
            row = i // 2
            col = (i % 2) * 2
            filter_layout.addWidget(color_label, row, col)
            filter_layout.addWidget(cb, row, col + 1)
            
            self.regime_checkboxes[i] = cb
        
        filter_group.setLayout(filter_layout)
        layout.addWidget(filter_group)
        
        # Preset buttons
        preset_group = QGroupBox("Quick Presets")
        preset_layout = QHBoxLayout()
        
        btn_all = QPushButton("Allow All")
        btn_all.clicked.connect(lambda: self.apply_preset("all"))
        
        btn_none = QPushButton("Block All")
        btn_none.clicked.connect(lambda: self.apply_preset("none"))
        
        btn_trending = QPushButton("Trending Only (3,7,8)")
        btn_trending.clicked.connect(lambda: self.apply_preset("trending"))
        
        btn_safe = QPushButton("Safe Only (1,3,8)")
        btn_safe.clicked.connect(lambda: self.apply_preset("safe"))
        
        preset_layout.addWidget(btn_all)
        preset_layout.addWidget(btn_none)
        preset_layout.addWidget(btn_trending)
        preset_layout.addWidget(btn_safe)
        preset_group.setLayout(preset_layout)
        layout.addWidget(preset_group)
        
        layout.addStretch()
        return widget
    
    def create_trade_log_tab(self) -> QWidget:
        """Create trade log tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        
        # Log table
        self.trade_log_table = QTableWidget(0, 7)
        self.trade_log_table.setHorizontalHeaderLabels([
            "Time", "Action", "Symbol", "Regime", "Confidence", "Decision", "Reason"
        ])
        layout.addWidget(self.trade_log_table)
        
        # Clear button
        clear_btn = QPushButton("Clear Log")
        clear_btn.clicked.connect(self.clear_trade_log)
        layout.addWidget(clear_btn)
        
        return widget
    
    def create_statistics_tab(self) -> QWidget:
        """Create statistics tab."""
        widget = QWidget()
        layout = QVBoxLayout(widget)
        
        # Statistics display
        self.stats_text = QTextEdit()
        self.stats_text.setReadOnly(True)
        self.stats_text.setFont(QFont("Courier", 10))
        layout.addWidget(self.stats_text)
        
        # Refresh button
        refresh_btn = QPushButton("Refresh Statistics")
        refresh_btn.clicked.connect(self.update_statistics)
        layout.addWidget(refresh_btn)
        
        return widget
    
    # ========================================================
    # Event Handlers
    # ========================================================
    
    def load_model(self):
        """Load GMM model and scaler."""
        try:
            script_dir = Path(__file__).parent
            model_path = script_dir / "market_regime_gmm.pkl"
            scaler_path = script_dir / "scaler.pkl"
            
            if not model_path.exists() or not scaler_path.exists():
                self.model_status_label.setText("Model: Files Not Found")
                self.model_status_label.setStyleSheet("color: red;")
                QMessageBox.warning(
                    self, "Model Error",
                    "Model files not found. Please ensure market_regime_gmm.pkl "
                    "and scaler.pkl are in the same directory."
                )
                return
            
            self.predictor = RegimePredictor(str(model_path), str(scaler_path))
            self.model_status_label.setText("Model: Loaded ✓")
            self.model_status_label.setStyleSheet("color: green;")
            self.statusBar.showMessage("Model loaded successfully", 3000)
            
        except Exception as e:
            self.model_status_label.setText("Model: Load Error")
            self.model_status_label.setStyleSheet("color: red;")
            QMessageBox.critical(self, "Model Error", f"Failed to load model:\n{str(e)}")
    
    def toggle_connection(self):
        """Start/stop MT bridge connection."""
        if not self.bridge.is_running:
            # Update connection parameters
            self.bridge.host = self.host_input.text()
            self.bridge.port = self.port_input.value()
            
            # Start server
            self.bridge.start()
            self.connect_btn.setText("Stop Server")
            self.host_input.setEnabled(False)
            self.port_input.setEnabled(False)
        else:
            # Stop server
            self.bridge.stop()
            self.connect_btn.setText("Start Server")
            self.host_input.setEnabled(True)
            self.port_input.setEnabled(True)
            self.connection_status_label.setText("●")
            self.connection_status_label.setStyleSheet("color: red; font-size: 20px;")
    
    def update_connection_status(self, connected: bool, message: str):
        """Update connection status display."""
        if connected:
            self.connection_status_label.setText("●")
            self.connection_status_label.setStyleSheet("color: green; font-size: 20px;")
        else:
            self.connection_status_label.setText("●")
            self.connection_status_label.setStyleSheet("color: red; font-size: 20px;")
        
        self.statusBar.showMessage(message, 5000)
    
    def toggle_auto_mode(self, state):
        """Toggle automatic trade filtering."""
        self.auto_mode = (state == Qt.Checked)
        if self.auto_mode:
            self.statusBar.showMessage("Auto mode enabled: Trades will be filtered automatically", 3000)
        else:
            self.statusBar.showMessage("Manual mode: All trades will be allowed", 3000)
    
    def on_terminal_connected(self, terminal_name: str, symbol: str):
        """Handle new terminal connection."""
        # Update terminal combo box
        self.update_terminal_list()
        self.statusBar.showMessage(f"Terminal connected: {terminal_name} ({symbol})", 5000)
    
    def on_terminal_selected(self, index):
        """Handle terminal selection change."""
        terminal_id = self.terminal_combo.currentData()
        if terminal_id:
            self.bridge.selected_terminal = terminal_id
            
            # Get or create predictor for this terminal
            if terminal_id not in self.terminal_predictors:
                script_dir = Path(__file__).parent
                model_path = script_dir / "market_regime_gmm.pkl"
                scaler_path = script_dir / "scaler.pkl"
                self.terminal_predictors[terminal_id] = RegimePredictor(str(model_path), str(scaler_path))
            
            self.predictor = self.terminal_predictors[terminal_id]
            self.statusBar.showMessage(f"Selected terminal: {self.terminal_combo.currentText()}", 3000)
    
    def update_terminal_list(self):
        """Update list of connected terminals."""
        current_selection = self.terminal_combo.currentData()
        self.terminal_combo.clear()
        
        terminals = self.bridge.get_connected_terminals()
        if not terminals:
            self.terminal_combo.addItem("No terminals connected", None)
        else:
            for terminal_id, info in terminals:
                display_name = f"{info['name']} - {info['symbol']} (Acc: {info['account']})"
                self.terminal_combo.addItem(display_name, terminal_id)
                
                # Select previously selected terminal if still connected
                if terminal_id == current_selection:
                    self.terminal_combo.setCurrentIndex(self.terminal_combo.count() - 1)
    
    def handle_mt_data(self, data: dict):
        """Handle incoming data from MetaTrader.
        
        Expected data format:
        {
            "type": "bar" | "trade_request" | "handshake",
            "terminal_id": "...",
            "time": "2026-06-09 10:30:00",
            "open": 1.0850,
            "high": 1.0855,
            "low": 1.0848,
            "close": 1.0852,
            "tickvol": 150,
            "spread": 2,
            "symbol": "EURUSD",
            "action": "buy" | "sell" | "close"
        }
        """
        terminal_id = data.get("terminal_id")
        
        # Get predictor for this terminal
        if terminal_id and terminal_id not in self.terminal_predictors:
            script_dir = Path(__file__).parent
            model_path = script_dir / "market_regime_gmm.pkl"
            scaler_path = script_dir / "scaler.pkl"
            self.terminal_predictors[terminal_id] = RegimePredictor(str(model_path), str(scaler_path))
        
        predictor = self.terminal_predictors.get(terminal_id)
        if not predictor:
            return
        
        data_type = data.get("type", "bar")
        
        if data_type == "handshake":
            # Update terminal list
            self.update_terminal_list()
            return
        
        elif data_type == "bar":
            # Add bar to predictor
            bar_data = {
                "time": data.get("time"),
                "open": data.get("open"),
                "high": data.get("high"),
                "low": data.get("low"),
                "close": data.get("close"),
                "tickvol": data.get("tickvol", 100),
                "spread": data.get("spread", 2)
            }
            predictor.add_bar(bar_data)
            
            # Predict regime (force recalculation since we have a new bar)
            regime, confidence, probs = predictor.predict(force_recalculate=True)
            if regime is not None and terminal_id == self.bridge.selected_terminal:
                self.predictor = predictor  # Update current predictor
                self.update_regime_display(regime, confidence, probs)
            
            # IMPORTANT: Send regime update back to EA after every bar
            # This ensures EA always has current regime, not just during trade requests
            if regime is not None:
                allow_trade, reason = self.evaluate_trade_request(predictor)
                print(f"[WARMUP FIX] Sending regime to EA: Regime {regime}, Confidence {confidence:.1%}, Allowed: {allow_trade}")
                self.bridge.send_trade_decision(
                    allow_trade,
                    regime,
                    confidence,
                    terminal_id
                )
        
        elif data_type == "trade_request":
            # EA is asking permission to trade
            symbol = data.get("symbol", "UNKNOWN")
            action = data.get("action", "unknown")
            
            # Make decision
            allow_trade, reason = self.evaluate_trade_request(predictor)
            
            # Log the decision
            self.log_trade(symbol, action, allow_trade, reason)
            
            # Send response to EA
            if predictor.current_regime is not None:
                self.bridge.send_trade_decision(
                    allow_trade,
                    predictor.current_regime,
                    predictor.regime_confidence,
                    terminal_id
                )
    
    def evaluate_trade_request(self, predictor=None) -> tuple:
        """Evaluate if trade should be allowed.
        
        Returns:
            Tuple of (allow: bool, reason: str)
        """
        if not self.auto_mode:
            return True, "Manual mode"
        
        if self.predictor.current_regime is None:
            return False, "No regime prediction available"
        
        regime = self.predictor.current_regime
        confidence = self.predictor.regime_confidence
        
        # Check confidence threshold
        if confidence < self.min_confidence:
            return False, f"Low confidence ({confidence:.1%} < {self.min_confidence:.1%})"
        
        # Check regime filter
        if not self.regime_filter_config.get(regime, False):
            return False, f"Regime {regime} ({REGIME_NAMES[regime]}) blocked by filter"
        
        return True, f"Approved: Regime {regime} ({confidence:.1%})"
    
    def update_regime_display(self, regime: int, confidence: float, probs: np.ndarray):
        """Update regime display."""
        # Update main labels
        regime_name = REGIME_NAMES[regime]
        self.regime_label.setText(f"{regime}: {regime_name}")
        self.regime_label.setStyleSheet(f"color: {REGIME_COLORS[regime]};")
        
        self.confidence_label.setText(f"{confidence:.1%}")
        
        # Update trade status
        allowed, reason = self.evaluate_trade_request()
        if allowed:
            self.trade_status_label.setText("ALLOWED ✓")
            self.trade_status_label.setStyleSheet("color: green; font-weight: bold;")
        else:
            self.trade_status_label.setText("BLOCKED ✗")
            self.trade_status_label.setStyleSheet("color: red; font-weight: bold;")
        
        # Update probabilities table
        for i, prob in enumerate(probs):
            item = QTableWidgetItem(f"{prob:.1%}")
            if i == regime:
                item.setBackground(QColor(REGIME_COLORS[i]))
            self.probs_table.setItem(i, 2, item)
    
    def update_displays(self):
        """Periodic UI updates."""
        if self.predictor:
            buffer_size = len(self.predictor.data_buffer)
            self.buffer_label.setText(
                f"Data Buffer: {buffer_size} bars "
                f"({'Ready' if buffer_size >= MIN_WARMUP else f'need {MIN_WARMUP - buffer_size} more'})"
            )
            self.buffer_progress.setValue(min(buffer_size, MIN_WARMUP))
    
    def refresh_regime_monitor(self):
        """Refresh regime monitor display every 10 seconds.
        
        Uses cached prediction if no new bars have arrived.
        This prevents regime flipping due to repeated feature recalculation.
        """
        if self.predictor and self.predictor.current_regime is not None:
            # Re-predict with current data (will use cache if buffer unchanged)
            regime, confidence, probs = self.predictor.predict(force_recalculate=False)
            
            if regime is not None:
                # Update the display with prediction (cached or fresh)
                self.update_regime_display(regime, confidence, probs)
    
    def update_regime_filter(self, regime_id: int, state):
        """Update regime filter configuration."""
        self.regime_filter_config[regime_id] = (state == Qt.Checked)
        self.statusBar.showMessage(
            f"Regime {regime_id} ({'allowed' if state == Qt.Checked else 'blocked'})",
            2000
        )
    
    def update_min_confidence(self, value):
        """Update minimum confidence threshold."""
        self.min_confidence = value / 100.0
        self.statusBar.showMessage(f"Minimum confidence set to {value}%", 2000)
    
    def apply_preset(self, preset_name: str):
        """Apply regime filter preset."""
        if preset_name == "all":
            allowed = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        elif preset_name == "none":
            allowed = []
        elif preset_name == "trending":
            allowed = [3, 7, 8]  # Bullish trending, bearish trending, bullish momentum
        elif preset_name == "safe":
            allowed = [1, 3, 8]  # Normal, bullish trending, bullish momentum
        else:
            return
        
        for i in range(10):
            is_allowed = i in allowed
            self.regime_checkboxes[i].setChecked(is_allowed)
            self.regime_filter_config[i] = is_allowed
        
        self.statusBar.showMessage(f"Applied preset: {preset_name}", 2000)
    
    def log_trade(self, symbol: str, action: str, allowed: bool, reason: str):
        """Log trade decision."""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        regime = self.predictor.current_regime if self.predictor else "N/A"
        confidence = f"{self.predictor.regime_confidence:.1%}" if self.predictor else "N/A"
        decision = "ALLOWED" if allowed else "BLOCKED"
        
        # Add to log
        self.trade_log.append({
            "time": timestamp,
            "symbol": symbol,
            "action": action,
            "regime": regime,
            "confidence": confidence,
            "decision": decision,
            "reason": reason
        })
        
        # Update table (add to top)
        self.trade_log_table.insertRow(0)
        self.trade_log_table.setItem(0, 0, QTableWidgetItem(timestamp))
        self.trade_log_table.setItem(0, 1, QTableWidgetItem(action))
        self.trade_log_table.setItem(0, 2, QTableWidgetItem(symbol))
        self.trade_log_table.setItem(0, 3, QTableWidgetItem(str(regime)))
        self.trade_log_table.setItem(0, 4, QTableWidgetItem(confidence))
        
        decision_item = QTableWidgetItem(decision)
        decision_item.setBackground(QColor("lightgreen" if allowed else "lightcoral"))
        self.trade_log_table.setItem(0, 5, decision_item)
        
        self.trade_log_table.setItem(0, 6, QTableWidgetItem(reason))
        
        # Limit log size
        if self.trade_log_table.rowCount() > 1000:
            self.trade_log_table.removeRow(1000)
    
    def clear_trade_log(self):
        """Clear trade log."""
        self.trade_log = []
        self.trade_log_table.setRowCount(0)
        self.statusBar.showMessage("Trade log cleared", 2000)
    
    def update_statistics(self):
        """Update statistics display."""
        if not self.predictor or len(self.predictor.data_buffer) < MIN_WARMUP:
            self.stats_text.setText("Insufficient data for statistics")
            return
        
        # Get regime history
        regime_history = self.predictor.get_regime_history(window=200)
        
        if not regime_history:
            self.stats_text.setText("No regime history available")
            return
        
        # Calculate statistics
        regime_counts = {}
        for r in regime_history:
            regime_counts[r] = regime_counts.get(r, 0) + 1
        
        total = len(regime_history)
        
        # Trade log statistics
        total_trades = len(self.trade_log)
        allowed_trades = sum(1 for t in self.trade_log if t["decision"] == "ALLOWED")
        blocked_trades = total_trades - allowed_trades
        
        # Build statistics text
        stats = []
        stats.append("=" * 60)
        stats.append("REGIME STATISTICS (Last 200 bars)")
        stats.append("=" * 60)
        stats.append(f"Total bars analyzed: {total}")
        stats.append("")
        stats.append("Regime Distribution:")
        stats.append("-" * 60)
        
        for regime_id in range(10):
            count = regime_counts.get(regime_id, 0)
            pct = (count / total * 100) if total > 0 else 0
            name = REGIME_NAMES[regime_id]
            stats.append(f"  {regime_id}: {name:25s} {count:4d} bars ({pct:5.1f}%)")
        
        stats.append("")
        stats.append("=" * 60)
        stats.append("TRADE FILTER STATISTICS")
        stats.append("=" * 60)
        stats.append(f"Total trade requests: {total_trades}")
        stats.append(f"Allowed: {allowed_trades} ({allowed_trades/max(total_trades,1)*100:.1f}%)")
        stats.append(f"Blocked: {blocked_trades} ({blocked_trades/max(total_trades,1)*100:.1f}%)")
        stats.append("")
        
        # Current filter config
        stats.append("Current Filter Configuration:")
        stats.append("-" * 60)
        stats.append(f"Minimum Confidence: {self.min_confidence:.1%}")
        stats.append(f"Auto Mode: {'Enabled' if self.auto_mode else 'Disabled'}")
        stats.append("")
        stats.append("Allowed Regimes:")
        for i in range(10):
            if self.regime_filter_config[i]:
                stats.append(f"  ✓ {i}: {REGIME_NAMES[i]}")
        
        stats.append("")
        stats.append("Blocked Regimes:")
        for i in range(10):
            if not self.regime_filter_config[i]:
                stats.append(f"  ✗ {i}: {REGIME_NAMES[i]}")
        
        self.stats_text.setText("\n".join(stats))
    
    def closeEvent(self, event):
        """Handle window close."""
        self.bridge.stop()
        event.accept()


# ============================================================
# MAIN ENTRY POINT
# ============================================================

def main():
    app = QApplication(sys.argv)
    
    # Set application style
    app.setStyle("Fusion")
    
    # Create and show main window
    window = RegimeTradingGUI()
    window.show()
    
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
