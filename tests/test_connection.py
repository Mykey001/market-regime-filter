"""
Connection Test Script
======================
Tests if the server can start and accept connections.
"""

import socket
import sys

print("=" * 60)
print("Testing Socket Server Connection")
print("=" * 60)
print()

# Test 1: Check if port is available
print("Test 1: Checking if port 9090 is available...")
try:
    test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    test_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    test_socket.bind(("127.0.0.1", 9090))
    test_socket.close()
    print("✓ Port 9090 is available")
except OSError as e:
    print(f"✗ Port 9090 is NOT available: {e}")
    print("  Solution: Close any program using port 9090")
    print("  Or change port in GUI and EA")
    sys.exit(1)

print()

# Test 2: Start a test server
print("Test 2: Starting test server...")
try:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 9090))
    server.listen(1)
    server.settimeout(2.0)
    print("✓ Test server started successfully")
    print(f"  Listening on 127.0.0.1:9090")
except Exception as e:
    print(f"✗ Failed to start server: {e}")
    sys.exit(1)

print()

# Test 3: Try to connect as a client (simulating MT5)
print("Test 3: Testing client connection (simulating MT5)...")
try:
    import threading
    
    def try_connect():
        try:
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.settimeout(2.0)
            client.connect(("127.0.0.1", 9090))
            client.send(b'{"type":"test"}\n')
            client.close()
        except Exception as e:
            print(f"  Client error: {e}")
    
    # Start client in separate thread
    client_thread = threading.Thread(target=try_connect)
    client_thread.start()
    
    # Accept connection on server
    conn, addr = server.accept()
    print(f"✓ Client connected from {addr}")
    
    data = conn.recv(1024)
    print(f"✓ Received data: {data.decode('utf-8').strip()}")
    
    conn.close()
    client_thread.join()
    
except socket.timeout:
    print("✗ Connection timeout - no client connected")
except Exception as e:
    print(f"✗ Connection test failed: {e}")

print()

# Cleanup
server.close()

print("=" * 60)
print("CONNECTION TEST COMPLETED")
print("=" * 60)
print()
print("If all tests passed, the socket server works correctly.")
print()
print("Next steps:")
print("1. Start the GUI: python regime_trading_gui.py")
print("2. Click 'Start Server' button")
print("3. Wait for 'Listening on 127.0.0.1:9090' message")
print("4. THEN attach EA to MT5 chart")
print()
print("If EA still shows error 4014:")
print("- Check Windows Firewall is not blocking Python")
print("- Try running GUI as Administrator")
print("- Check antivirus is not blocking connections")
print()
