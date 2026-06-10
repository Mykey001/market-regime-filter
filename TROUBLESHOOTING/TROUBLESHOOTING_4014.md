# Troubleshooting Error 4014 - Connection Refused

## 🔴 Error Message
```
Failed to connect socket: 4014
```

**Meaning**: MT5 cannot connect to Python GUI because:
1. Server is not running, OR
2. Server hasn't started listening yet, OR
3. Firewall is blocking the connection

---

## ✅ Solution (Step by Step)

### Step 1: Close Everything

1. **Close MT5 EA**: Remove EA from chart (drag off or close MT5)
2. **Close Python GUI**: If running, close the window
3. **Wait 5 seconds**

### Step 2: Test Connection

Run this test script:
```bash
cd "C:\Users\MYCkey98\Downloads\REGIME MOD"
python test_connection.py
```

**Expected output:**
```
✓ Port 9090 is available
✓ Test server started successfully
✓ Client connected from ('127.0.0.1', xxxxx)
✓ Received data: {"type":"test"}
```

**If test fails:**
- Port 9090 is in use → Change to different port (see below)
- Firewall blocking → Check Windows Firewall (see below)

### Step 3: Start GUI in Correct Order

**IMPORTANT: Follow this exact order!**

#### 3.1: Start Python GUI
```bash
python regime_trading_gui.py
```

Wait for window to open.

#### 3.2: Click "Start Server"

Click the **"Start Server"** button in the GUI.

#### 3.3: Wait for Confirmation

Look for status bar message:
```
Listening on 127.0.0.1:9090
```

Connection indicator should be **RED** ● (waiting for EA).

#### 3.4: Now Attach EA

Only NOW attach the EA to MT5 chart.

**Within 2-3 seconds:**
- GUI indicator turns **GREEN** ●
- Status shows: "EA connected from..."
- MT5 shows regime info on chart

---

## 🔧 Advanced Fixes

### Fix 1: Windows Firewall Blocking Python

#### Check if Blocked:
```bash
# Run in Command Prompt (as Administrator):
netsh advfirewall firewall show rule name=all | findstr Python
```

#### Add Firewall Exception:
```bash
# Run as Administrator:
netsh advfirewall firewall add rule name="Python Server" dir=in action=allow program="C:\Python\python.exe" enable=yes
```

Replace `C:\Python\python.exe` with your actual Python path.

**Or use GUI:**
1. Windows Settings → Update & Security → Windows Security
2. Firewall & network protection → Allow an app through firewall
3. Click "Change settings"
4. Click "Allow another app..."
5. Browse to `python.exe`
6. Check both "Private" and "Public"
7. Click "Add"

### Fix 2: Change Port (if 9090 is Busy)

#### In GUI:
1. Change **Port** field from `9090` to `9091` (or any 1024-65535)
2. Click "Start Server"

#### In MT5 EA:
1. Open EA properties
2. Change **PythonPort** from `9090` to `9091` (match GUI)
3. Click OK

### Fix 3: Run as Administrator

Right-click on `start_gui.bat` → **Run as Administrator**

Or run CMD as Admin:
```bash
cd "C:\Users\MYCkey98\Downloads\REGIME MOD"
python regime_trading_gui.py
```

### Fix 4: Antivirus Blocking

**Common antivirus programs that may block:**
- Windows Defender
- Avast
- AVG
- Kaspersky
- Norton

**Solution:**
1. Add Python to antivirus exceptions
2. Add the REGIME MOD folder to exceptions
3. Temporarily disable antivirus to test

### Fix 5: Check Python is Accessible

```bash
# Test Python networking:
python -c "import socket; print('Socket module OK')"
```

Should print: `Socket module OK`

If error, reinstall Python with networking support.

---

## 🔍 Diagnosis Checklist

Run through this checklist:

- [ ] Python GUI is running
- [ ] "Start Server" button was clicked
- [ ] Status shows "Listening on 127.0.0.1:9090"
- [ ] Port 9090 is not used by another program
- [ ] Windows Firewall allows Python
- [ ] Antivirus is not blocking
- [ ] EA has correct host (127.0.0.1) and port (9090)
- [ ] EA is on M5 timeframe
- [ ] MT5 build is 3000+

---

## 📊 Error Code Reference

| Code | Meaning | Solution |
|------|---------|----------|
| 4014 | Connection refused | Server not started or firewall blocking |
| 4001 | Timeout | Server taking too long to respond |
| 4000 | Generic socket error | Check MT5 build version (need 3000+) |

---

## 🎯 Quick Test Procedure

```bash
# Terminal 1 (Python)
python regime_trading_gui.py
# Click "Start Server"
# Wait for "Listening on..."

# Terminal 2 (Test)
python test_connection.py
# Should show all tests passed

# Now attach EA in MT5
```

---

## 🆘 Still Not Working?

### Create a Diagnostic Report

Run these commands and save output:

```bash
# 1. Test connection
python test_connection.py > diagnostic.txt 2>&1

# 2. Check port
netstat -an | findstr 9090 >> diagnostic.txt

# 3. Test Python
python --version >> diagnostic.txt

# 4. Test imports
python -c "import PyQt5, socket, json; print('All modules OK')" >> diagnostic.txt
```

Send `diagnostic.txt` for further help.

---

## 💡 Common Mistakes

### ❌ Mistake 1: Starting EA Before GUI
```
Wrong order:
1. Attach EA to MT5
2. Start GUI
Result: Error 4014
```

### ✅ Correct Order:
```
Right order:
1. Start GUI
2. Click "Start Server"
3. Wait for "Listening..."
4. Then attach EA
Result: Success ✓
```

### ❌ Mistake 2: Not Clicking "Start Server"
```
Wrong: Just opening GUI window
Right: Must click "Start Server" button
```

### ❌ Mistake 3: Wrong IP Address
```
Wrong: 0.0.0.0 or 192.168.x.x
Right: 127.0.0.1 (localhost)
```

### ❌ Mistake 4: Port Mismatch
```
Wrong: GUI uses 9090, EA uses 9091
Right: Both must use same port
```

---

## 🎓 Understanding the Connection

```
Step 1: GUI starts server
   Python creates socket
   Binds to 127.0.0.1:9090
   Listens for connections
   Status: "Listening..."

Step 2: EA tries to connect
   MT5 creates socket
   Tries to connect to 127.0.0.1:9090
   
Step 3: Connection established
   GUI accepts connection
   Status: "EA connected..."
   Indicator turns GREEN
```

**Error 4014 occurs at Step 2** when MT5 cannot reach Python server.

---

## 📞 Prevention Tips

1. **Always start GUI first**
2. **Always click "Start Server"**
3. **Always wait for "Listening..." message**
4. **Then attach EA**

5. **Don't close GUI while EA is running**
6. **Don't restart GUI without removing EA first**

---

## ✅ Success Indicators

**You know it's working when:**

### In Python GUI:
- Status: "Listening on 127.0.0.1:9090" (after Start Server)
- Status: "EA connected from 127.0.0.1:xxxxx" (after EA attaches)
- Indicator: **GREEN** ●
- Terminal dropdown: Shows your MT5 terminal
- Buffer: Starts filling with bars

### In MT5:
- Chart comment shows: "Regime: X | Confidence: XX%"
- Experts tab shows: "Connected to Python GUI..."
- No error messages
- EA smile icon in corner

---

**Follow this guide carefully and error 4014 should be resolved!**

**Most common solution**: Start GUI → Click "Start Server" → WAIT → Then attach EA

---

**Version**: 2.0  
**Last Updated**: June 9, 2026  
**For**: MT5_RegimeFilter.mq5 + regime_trading_gui.py
