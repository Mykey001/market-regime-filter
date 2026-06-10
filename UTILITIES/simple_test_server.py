"""
Simple Test Server - Minimal socket server to test MT5 connection
"""
import socket
import json

HOST = '127.0.0.1'
PORT = 9090

print("=" * 60)
print("SIMPLE TEST SERVER")
print("=" * 60)
print(f"Starting server on {HOST}:{PORT}...")

try:
    # Create socket
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(5)
    
    print(f"✓ Server listening on {HOST}:{PORT}")
    print("Waiting for MT5 connection...")
    print()
    
    while True:
        # Accept connection
        client, addr = server.accept()
        print(f"✓ Client connected from {addr}")
        
        try:
            client.settimeout(1.0)
            buffer = ""
            
            while True:
                try:
                    data = client.recv(4096)
                    if not data:
                        break
                    
                    buffer += data.decode('utf-8')
                    
                    # Process complete messages
                    while '\n' in buffer:
                        message, buffer = buffer.split('\n', 1)
                        if message.strip():
                            print(f"Received: {message[:100]}...")
                            
                            try:
                                msg = json.loads(message)
                                msg_type = msg.get('type', 'unknown')
                                
                                # Send response
                                response = {
                                    "allow_trade": True,
                                    "regime": 1,
                                    "confidence": 0.75,
                                    "timestamp": "2026-06-09T20:00:00"
                                }
                                response_str = json.dumps(response) + "\n"
                                client.sendall(response_str.encode('utf-8'))
                                print(f"Sent response: {response}")
                                
                            except json.JSONDecodeError:
                                print(f"Invalid JSON")
                
                except socket.timeout:
                    continue
                except Exception as e:
                    print(f"Error: {e}")
                    break
        
        finally:
            client.close()
            print(f"Client {addr} disconnected")
            print()

except KeyboardInterrupt:
    print("\nServer stopped by user")
except Exception as e:
    print(f"Server error: {e}")
finally:
    server.close()
