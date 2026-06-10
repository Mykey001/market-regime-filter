"""
File Organization Script
========================
Organizes files into production-ready structure.
"""

import os
import shutil
from pathlib import Path

print("=" * 60)
print("File Organization for Production")
print("=" * 60)
print()

# Get current directory
base_dir = Path(__file__).parent

# Define folder structure
folders = {
    "CORE_SYSTEM": [
        "regime_trading_gui.py",
        "feature_engine.py",
        "market_regime_gmm.pkl",
        "scaler.pkl",
        "requirements.txt",
        "start_gui.bat",
    ],
    "MT5_EA": [
        "MT5_RegimeFilter.mq5",
        "MT4_RegimeFilter.mq4",
        "INTEGRATION_EXAMPLES.mq5",
    ],
    "DOCUMENTATION": [
        "README.md",
        "QUICK_START.md",
        "TRADING_GUI_SETUP_GUIDE.md",
        "HOW_TO_INTEGRATE_YOUR_EA.md",
        "INTEGRATION_DIAGRAM.txt",
        "ANALYSIS_REPORT.md",
        "TECHNICAL_SUMMARY.md",
        "PROJECT_SUMMARY.md",
        "FIXES_AND_IMPROVEMENTS.md",
        "FILE_ORGANIZATION.md",
        "SYSTEM_ARCHITECTURE.txt",
    ],
    "UTILITIES": [
        "test_installation.py",
        "test_connection.py",
        "quick_warmup.py",
        "load_historical_data.py",
        "simple_test_server.py",
        "fix_firewall.bat",
        "organize_files.py",
    ],
    "TROUBLESHOOTING": [
        "TROUBLESHOOTING_4014.md",
        "DEPLOYMENT_CHECKLIST.md",
        "STARTUP_CHECKLIST.txt",
    ],
}

print("This will organize files into folders:")
print()
for folder in folders.keys():
    print(f"  📁 {folder}/")
print()
print("Files will be COPIED (not moved) - originals remain.")
print()

response = input("Continue? (y/n): ")
if response.lower() != 'y':
    print("Cancelled")
    exit()

print()
print("Organizing files...")
print()

# Create folders
for folder in folders.keys():
    folder_path = base_dir / folder
    folder_path.mkdir(exist_ok=True)
    print(f"✓ Created: {folder}/")

print()

# Copy files
copied_count = 0
for folder, files in folders.items():
    for filename in files:
        src = base_dir / filename
        dst = base_dir / folder / filename
        
        if src.exists() and src.is_file():
            try:
                shutil.copy2(src, dst)
                print(f"  ✓ {filename:40s} → {folder}/")
                copied_count += 1
            except Exception as e:
                print(f"  ✗ {filename:40s} Error: {e}")
        else:
            print(f"  - {filename:40s} (not found, skipped)")

print()
print("=" * 60)
print(f"Organization Complete! Copied {copied_count} files.")
print("=" * 60)
print()
print("Folder structure:")
print()
for folder in folders.keys():
    folder_path = base_dir / folder
    if folder_path.exists():
        file_count = len(list(folder_path.glob("*")))
        print(f"  📁 {folder:25s} ({file_count} files)")

print()
print("Next steps:")
print("1. Check each folder to verify files")
print("2. Original files remain in root (for backup)")
print("3. Use files from organized folders for deployment")
print()
print("To use the system:")
print("  cd CORE_SYSTEM")
print("  python regime_trading_gui.py")
print()
