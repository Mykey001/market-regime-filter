import json
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import tkinter as tk
from tkinter import ttk, messagebox
import matplotlib
matplotlib.use("TkAgg")

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
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
SOCKET_ENABLED = True  # Set to False to disable EA connection

# ============================================================
# LOAD SAVED MODEL AND SCALER
# ============================================================

script_dir = os.path.dirname(os.path.abspath(__file__))

MODEL_PATHS = [
    os.path.join(script_dir, "market_regime_model.pkl"),
    os.path.join(script_dir, "market_regime_gmm.pkl"),
]
SCALER_PATHS = [
    os.path.join(script_dir, "regime_scaler.pkl"),
    os.path.join(script_dir, "scaler.pkl"),
]
METADATA_PATH = os.path.join(script_dir, "regime_metadata.json")

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
    raise Exception(
        "Failed loading saved regime model or scaler. "
        "Ensure market_regime_model.pkl and regime_scaler.pkl exist."
    )

REGIME_MAP = metadata.get("regime_map", {})

# ============================================================
# REGIME LABELS
# ============================================================

REGIME_NAMES = {
    0: "Low Volatility Bullish",
    1: "Neutral Consolidation",
    2: "High Volatility Bearish",
    3: "Low Volatility Bearish"
}

REGIME_COLORS = {
    0: "green",
    1: "orange",
    2: "red",
    3: "purple"
}

# Regime filter configuration (which regimes allow trading)
# True = Allow trades, False = Block trades
REGIME_FILTER_CONFIG = {
    0: True,   # Low Volatility Bullish - ALLOW
    1: True,   # Neutral Consolidation - ALLOW
    2: False,  # High Volatility Bearish - BLOCK
    3: True,   # Low Volatility Bearish - ALLOW
    # Add more regimes as needed for your model
    4: False,  # Example: Block regime 4 if it exists
    5: False,  # Example: Block regime 5 if it exists
    6: True,
    7: True,
    8: True,
    9: False,
}

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

    raise ValueError("Loaded model does not support probability estimates")


def predict_regime(df):
    df_feat = compute_all_features(df)
    X, valid_df = get_feature_matrix(df_feat, drop_na=True)

    if len(valid_df) == 0:
        raise Exception(
            "Not enough historical bars to compute features. "
            "Increase the number of bars or switch to M5 timeframe."
        )

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
        "regime_map": REGIME_MAP,
        "model_path": model_path,
        "scaler_path": scaler_path,
    }

# ============================================================
# GUI APPLICATION
# ============================================================


class RegimeDashboard:

    def __init__(self, root):

        self.root = root

        self.root.title("Live Market Regime Dashboard + EA Filter")
        self.root.geometry("1200x850")

        self.running = True

        self.symbol_var = tk.StringVar(value=DEFAULT_SYMBOL)

        self.timeframe_var = tk.StringVar(value="M5")

        self.timeframe_map = {
            "M1": mt5.TIMEFRAME_M1,
            "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15,
            "M30": mt5.TIMEFRAME_M30,
            "H1": mt5.TIMEFRAME_H1,
            "H4": mt5.TIMEFRAME_H4,
            "D1": mt5.TIMEFRAME_D1
        }

        # Current regime data (for EA requests)
        self.current_regime = None
        self.current_confidence = 0.0
        self.current_probabilities = None
        self.last_update_time = None
        
        # Socket server
        self.socket_server = None
        self.socket_thread = None
        self.server_running = False
        self.server_status_var = tk.StringVar(value="Server: STOPPED")
        self.ea_connection_var = tk.StringVar(value="EA: Not Connected")

        self.build_gui()

        self.start_live_updates()
        
        if SOCKET_ENABLED:
            self.start_socket_server()

    # ========================================================
    # GUI
    # ========================================================

    def build_gui(self):

        top_frame = ttk.Frame(self.root)
        top_frame.pack(fill="x", padx=10, pady=10)

        ttk.Label(top_frame, text="Symbol:").pack(side="left")

        self.symbol_entry = ttk.Entry(
            top_frame,
            textvariable=self.symbol_var,
            width=15
        )
        self.symbol_entry.pack(side="left", padx=5)

        ttk.Label(top_frame, text="Timeframe:").pack(side="left")

        timeframe_combo = ttk.Combobox(
            top_frame,
            textvariable=self.timeframe_var,
            values=list(self.timeframe_map.keys()),
            width=10,
            state="readonly"
        )
        timeframe_combo.pack(side="left", padx=5)

        refresh_btn = ttk.Button(
            top_frame,
            text="Refresh Now",
            command=self.manual_refresh
        )
        refresh_btn.pack(side="left", padx=10)
        
        # Server status labels
        ttk.Label(top_frame, textvariable=self.server_status_var, 
                 foreground="blue").pack(side="left", padx=10)
        ttk.Label(top_frame, textvariable=self.ea_connection_var,
                 foreground="green").pack(side="left", padx=5)

        # ====================================================
        # LIVE DATA PANEL
        # ====================================================

        info_frame = ttk.LabelFrame(self.root, text="Live Market Analysis")
        info_frame.pack(fill="x", padx=10, pady=10)

        self.price_var = tk.StringVar(value="--")
        self.regime_var = tk.StringVar(value="--")
        self.confidence_var = tk.StringVar(value="--")
        self.status_var = tk.StringVar(value="Initializing...")
        self.trade_status_var = tk.StringVar(value="--")

        ttk.Label(info_frame, text="Price:").grid(row=0, column=0, sticky="w", padx=5, pady=2)
        ttk.Label(info_frame, textvariable=self.price_var).grid(row=0, column=1, sticky="w", padx=5, pady=2)

        ttk.Label(info_frame, text="Regime:").grid(row=1, column=0, sticky="w", padx=5, pady=2)

        self.regime_label = ttk.Label(
            info_frame,
            textvariable=self.regime_var,
            font=("Arial", 14, "bold")
        )
        self.regime_label.grid(row=1, column=1, sticky="w", padx=5, pady=2)

        ttk.Label(info_frame, text="Confidence:").grid(row=2, column=0, sticky="w", padx=5, pady=2)
        ttk.Label(info_frame, textvariable=self.confidence_var).grid(row=2, column=1, sticky="w", padx=5, pady=2)

        ttk.Label(info_frame, text="Trade Status:").grid(row=3, column=0, sticky="w", padx=5, pady=2)
        self.trade_status_label = ttk.Label(info_frame, textvariable=self.trade_status_var, 
                                           font=("Arial", 10, "bold"))
        self.trade_status_label.grid(row=3, column=1, sticky="w", padx=5, pady=2)

        ttk.Label(info_frame, text="Status:").grid(row=4, column=0, sticky="w", padx=5, pady=2)
        ttk.Label(info_frame, textvariable=self.status_var).grid(row=4, column=1, sticky="w", padx=5, pady=2)

        ttk.Label(info_frame, text="Model:").grid(row=5, column=0, sticky="w", padx=5, pady=2)
        self.model_var = tk.StringVar(value=os.path.basename(model_path) if model_path else "Unknown")
        ttk.Label(info_frame, textvariable=self.model_var).grid(row=5, column=1, sticky="w", padx=5, pady=2)

        # ====================================================
        # PROBABILITY PANEL
        # ====================================================

        self.prob_frame = ttk.LabelFrame(self.root, text="Regime Probabilities")
        self.prob_frame.pack(fill="x", padx=10, pady=10)

        self.prob_labels = []
        self.update_probability_labels([])

        # ====================================================
        # CHART AREA
        # ====================================================

        chart_frame = ttk.Frame(self.root)
        chart_frame.pack(fill="both", expand=True, padx=10, pady=10)

        self.figure = Figure(figsize=(10, 6), dpi=100)

        self.ax_price = self.figure.add_subplot(211)
        self.ax_regime = self.figure.add_subplot(212)

        self.canvas = FigureCanvasTkAgg(self.figure, master=chart_frame)
        self.canvas.draw()
        self.canvas.get_tk_widget().pack(fill="both", expand=True)

    # ========================================================
    # UPDATE LOOP
    # ========================================================

    def start_live_updates(self):

        thread = threading.Thread(target=self.update_loop)
        thread.daemon = True
        thread.start()

    def update_loop(self):

        while self.running:

            try:
                self.fetch_and_update()
            except Exception as e:
                self.status_var.set(str(e))

            time.sleep(REFRESH_SECONDS)

    def manual_refresh(self):

        thread = threading.Thread(target=self.fetch_and_update)
        thread.daemon = True
        thread.start()

    # ========================================================
    # FETCH + UPDATE
    # ========================================================

    def fetch_and_update(self):

        symbol = self.symbol_var.get().strip()

        tf_name = self.timeframe_var.get()
        
        timeframe = self.timeframe_map.get(tf_name, mt5.TIMEFRAME_H1)

        self.status_var.set("Fetching data...")

        try:
            df = fetch_market_data(symbol, timeframe, DEFAULT_BARS)
            
            result = predict_regime(df)
            
            # Store current regime for EA requests
            self.current_regime = result['regime_id']
            self.current_confidence = result['confidence']
            self.current_probabilities = result["probabilities"]
            self.last_update_time = time.time()
            
            # Update display
            self.price_var.set(f"{result['price']:.2f}")
            self.regime_var.set(f"Regime {result['regime_id']}")
            self.confidence_var.set(f"{result['confidence']:.1f}%")
            
            # Update trade status
            allow_trade = REGIME_FILTER_CONFIG.get(result['regime_id'], True)
            if allow_trade:
                self.trade_status_var.set("ALLOWED ✓")
                self.trade_status_label.config(foreground="green")
            else:
                self.trade_status_var.set("BLOCKED ✗")
                self.trade_status_label.config(foreground="red")
            
            regime_color = REGIME_COLORS.get(result['regime_id'], "black")
            self.regime_label.config(foreground=regime_color)
            self.update_probability_labels(result["probabilities"])
            self.update_charts(result['featured_df'], result['regime_id'])
            self.status_var.set(f"Updated at {time.strftime('%H:%M:%S')}")
            
            print(f"[UPDATE] Regime {result['regime_id']}, Confidence {result['confidence']:.1f}%, "
                  f"Trade: {'ALLOWED' if allow_trade else 'BLOCKED'}")
            
        except Exception as e:
            self.status_var.set(f"Error: {str(e)}")
            print(f"[ERROR] {e}")
            # Don't show messagebox on auto-refresh errors
            # messagebox.showerror("Error", str(e))

    # ========================================================
    # PROBABILITY LABELS
    # ========================================================

    def update_probability_labels(self, probabilities):
        for lbl in self.prob_labels:
            lbl.destroy()

        self.prob_labels = []
        for i, prob in enumerate(probabilities):
            regime_info = REGIME_MAP.get(str(i), {})
            regime_name = regime_info.get("name", REGIME_NAMES.get(i, f"Regime {i}"))
            lbl = ttk.Label(self.prob_frame, text=f"{regime_name}: {prob * 100:.1f}%")
            lbl.pack(anchor="w", padx=10, pady=2)
            self.prob_labels.append(lbl)

    # ========================================================
    # CHART UPDATE
    # ========================================================

    def update_charts(self, df, current_regime):
        
        self.ax_price.clear()
        self.ax_regime.clear()
        
        # Price chart
        self.ax_price.plot(df.index, df['close'], label='Close Price', color='blue', linewidth=1)
        self.ax_price.plot(df.index, df['price_position'] * df['close'].max(),
                           label='Price Position (scaled)', color='orange', linewidth=0.8, alpha=0.7)

        self.ax_price.set_title('Price Chart')
        self.ax_price.set_ylabel('Price')
        self.ax_price.legend(loc='upper left')
        self.ax_price.grid(True, alpha=0.3)

        # RSI chart
        self.ax_regime.plot(df.index, df['rsi_14'], label='RSI 14', color='purple', linewidth=1)
        self.ax_regime.axhline(y=70, color='r', linestyle='--', alpha=0.5, label='Overbought')
        self.ax_regime.axhline(y=30, color='g', linestyle='--', alpha=0.5, label='Oversold')

        self.ax_regime.set_title(f'RSI - Current Regime: {REGIME_MAP.get(str(current_regime), {}).get("name", REGIME_NAMES.get(current_regime, "Unknown"))}')
        self.ax_regime.set_ylabel('RSI')
        self.ax_regime.set_xlabel('Time')
        self.ax_regime.legend(loc='upper left')
        self.ax_regime.grid(True, alpha=0.3)
        
        self.figure.tight_layout()
        self.canvas.draw()

    # ========================================================
    # SOCKET SERVER FOR EA CONNECTION
    # ========================================================
    
    def start_socket_server(self):
        """Start socket server to listen for EA trade requests."""
        self.socket_thread = threading.Thread(target=self.run_socket_server)
        self.socket_thread.daemon = True
        self.socket_thread.start()
        print(f"[SERVER] Socket server thread started on {SOCKET_HOST}:{SOCKET_PORT}")
    
    def run_socket_server(self):
        """Socket server main loop."""
        try:
            self.socket_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.socket_server.bind((SOCKET_HOST, SOCKET_PORT))
            self.socket_server.listen(5)
            self.socket_server.settimeout(1.0)  # Timeout for accept()
            
            self.server_running = True
            self.server_status_var.set(f"Server: RUNNING on {SOCKET_PORT}")
            print(f"[SERVER] Listening on {SOCKET_HOST}:{SOCKET_PORT}")
            
            while self.running and self.server_running:
                try:
                    client_socket, address = self.socket_server.accept()
                    print(f"[SERVER] EA connected from {address}")
                    self.ea_connection_var.set(f"EA: Connected {address[0]}")
                    
                    # Handle client in separate thread
                    client_thread = threading.Thread(
                        target=self.handle_client,
                        args=(client_socket, address)
                    )
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
            self.server_status_var.set(f"Server: ERROR - {e}")
        finally:
            if self.socket_server:
                self.socket_server.close()
            self.server_running = False
            self.server_status_var.set("Server: STOPPED")
    
    def handle_client(self, client_socket, address):
        """Handle individual EA client connection."""
        try:
            client_socket.settimeout(30.0)
            buffer = ""
            
            while self.running:
                try:
                    data = client_socket.recv(4096).decode('utf-8')
                    if not data:
                        break
                    
                    buffer += data
                    
                    # Process complete JSON messages (terminated by newline)
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        if line.strip():
                            self.process_ea_request(client_socket, line.strip())
                            
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"[SERVER] Client {address} error: {e}")
                    break
                    
        finally:
            client_socket.close()
            self.ea_connection_var.set("EA: Disconnected")
            print(f"[SERVER] EA disconnected from {address}")
    
    def process_ea_request(self, client_socket, message):
        """Process trade request from EA."""
        try:
            data = json.loads(message)
            msg_type = data.get("type", "")
            
            if msg_type == "trade_request":
                # EA is asking if trade is allowed
                symbol = data.get("symbol", "")
                action = data.get("action", "")
                
                # Check if we have current regime
                if self.current_regime is None:
                    # No regime data yet
                    response = {
                        "allow_trade": True,  # Allow by default if no data
                        "regime": -1,
                        "confidence": 0.0,
                        "reason": "No regime data available yet"
                    }
                else:
                    # Check filter configuration
                    allow_trade = REGIME_FILTER_CONFIG.get(self.current_regime, True)
                    
                    response = {
                        "allow_trade": allow_trade,
                        "regime": int(self.current_regime),
                        "confidence": float(self.current_confidence),
                        "reason": f"Regime {self.current_regime}: {'ALLOWED' if allow_trade else 'BLOCKED'}"
                    }
                    
                    print(f"[TRADE REQUEST] {action.upper()} on {symbol} -> "
                          f"Regime {self.current_regime} ({self.current_confidence:.1f}%) -> "
                          f"{'ALLOWED' if allow_trade else 'BLOCKED'}")
                
                # Send response
                response_json = json.dumps(response) + "\n"
                client_socket.sendall(response_json.encode('utf-8'))
                
            elif msg_type == "handshake":
                # EA is connecting
                terminal = data.get("terminal", "Unknown")
                print(f"[HANDSHAKE] EA connected: {terminal}")
                
                response = {
                    "status": "connected",
                    "message": "Dashboard ready"
                }
                response_json = json.dumps(response) + "\n"
                client_socket.sendall(response_json.encode('utf-8'))
                
        except json.JSONDecodeError:
            print(f"[SERVER] Invalid JSON: {message}")
        except Exception as e:
            print(f"[SERVER] Error processing request: {e}")

    def on_close(self):
        self.running = False
        self.root.destroy()


# ============================================================
# MAIN
# ============================================================

def main():
    root = tk.Tk()
    app = RegimeDashboard(root)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()


if __name__ == "__main__":
    main()