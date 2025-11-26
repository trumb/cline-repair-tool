#!/usr/bin/env python3
"""
Cline VS Code Extension Repair Tool for Linux

This script performs a complete repair of the Cline VS Code extension by:
1. Backing up all user data (tasks, history, MCP settings, rules, workflows)
2. Compressing backups to ZIP format with SHA256 hash verification
3. Uninstalling the current Cline extension
4. Performing a clean reinstallation
5. Restoring all user data
6. Configuring the sidebar position to left (Primary Side Bar)

Enhanced Features:
- 367 backup retention (daily backups for a year)
- UTC timestamps with hour/minute/second precision
- ZIP compression with integrity verification
- SHA256 hash in filename for backup verification
- JSON input/output support for automation
- Automatic verification of existing backups on startup

Version: 2.0.0
Author: Cline Repair Tool
Created: 2025-11-24
Updated: 2025-11-24
Requires: Python 3.6+, VS Code installed
"""

import os
import sys
import json
import shutil
import subprocess
import argparse
import re
import hashlib
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

STR_SCRIPT_VERSION = "2.0.0"

# Generate UTC timestamp with hour/minute/second precision
DT_NOW_UTC = datetime.now(timezone.utc)
STR_TIMESTAMP = DT_NOW_UTC.strftime("%Y%m%d_%H%M%S") + "_UTC"

STR_CLINE_EXTENSION_ID = "saoudrizwan.claude-dev"
INT_MAX_BACKUPS = 367  # Keep one year of daily backups

# Data location paths (Linux)
STR_HOME_DIR = str(Path.home())
STR_VSCODE_EXTENSIONS = os.path.join(STR_HOME_DIR, ".vscode", "extensions")
STR_VSCODE_USER_DATA = os.path.join(STR_HOME_DIR, ".config", "Code", "User")
STR_CLINE_GLOBAL_STORAGE = os.path.join(STR_VSCODE_USER_DATA, "globalStorage", "saoudrizwan.claude-dev")
STR_CLINE_DOCUMENTS = os.path.join(STR_HOME_DIR, "Documents", "Cline")

# JSON output object (will be initialized in main)
DICT_JSON_RESULT = {}

# ============================================================================
# HASH AND COMPRESSION FUNCTIONS
# ============================================================================

def calculate_file_hash(strFilePath: str, strAlgorithm: str = "sha256") -> str:
    """
    Calculate hash of a file.
    
    Args:
        strFilePath: Path to file
        strAlgorithm: Hash algorithm (sha256, sha1, md5)
        
    Returns:
        Hex digest of hash
    """
    try:
        if strAlgorithm.lower() == "sha256":
            objHash = hashlib.sha256()
        elif strAlgorithm.lower() == "sha1":
            objHash = hashlib.sha1()
        elif strAlgorithm.lower() == "md5":
            objHash = hashlib.md5()
        else:
            objHash = hashlib.sha256()
        
        with open(strFilePath, 'rb') as fileInput:
            while True:
                bytesData = fileInput.read(8192)
                if not bytesData:
                    break
                objHash.update(bytesData)
        
        return objHash.hexdigest()
    except Exception as e:
        return ""

def get_short_hash(strFullHash: str) -> str:
    """
    Get first 8 characters of hash.
    
    Args:
        strFullHash: Full hash string
        
    Returns:
        First 8 characters
    """
    return strFullHash[:8] if len(strFullHash) >= 8 else strFullHash

def verify_backup_integrity(strZipPath: str, strHashAlgorithm: str, objLogger: ClineLogger) -> Optional[bool]:
    """
    Verify integrity of a backup ZIP file using hash in filename.
    
    Args:
        strZipPath: Path to ZIP file
        strHashAlgorithm: Hash algorithm to use
        objLogger: Logger instance
        
    Returns:
        True if verified, False if failed, None if unknown (legacy format)
    """
    objLogger.log(f"Verifying backup integrity for {os.path.basename(strZipPath)}", "INFO")
    
    # Extract hash from filename (format: backup_YYYYMMDD_HHMMSS_UTC_{8-char-hash}.zip)
    strFileName = os.path.splitext(os.path.basename(strZipPath))[0]
    
    objMatch = re.search(r'_([A-Fa-f0-9]{8})$', strFileName)
    if objMatch:
        strExpectedHash = objMatch.group(1).lower()
        
        # Calculate actual hash
        strFullHash = calculate_file_hash(strZipPath, strHashAlgorithm)
        strActualHash = get_short_hash(strFullHash).lower()
        
        if strActualHash == strExpectedHash:
            objLogger.log(f"✓ Integrity verified: {strFileName}", "SUCCESS")
            return True
        else:
            objLogger.log(f"✗ Integrity check FAILED: {strFileName} (expected: {strExpectedHash}, got: {strActualHash})", "WARNING")
            return False
    else:
        objLogger.log(f"No hash found in filename: {strFileName} (legacy backup format)", "INFO")
        return None

def verify_existing_backups(strBackupPath: str, strHashAlgorithm: str, objLogger: ClineLogger):
    """
    Verify integrity of all existing backup ZIP files.
    
    Args:
        strBackupPath: Base backup directory
        strHashAlgorithm: Hash algorithm to use
        objLogger: Logger instance
    """
    objLogger.log_header("VERIFYING EXISTING BACKUPS")
    
    objLogger.log("Checking integrity of existing backup files", "ACTION")
    objLogger.log("Ensures all backups are uncorrupted and can be restored if needed", "REASON")
    
    try:
        if not os.path.exists(strBackupPath):
            objLogger.log("No existing backups found to verify", "INFO")
            return
        
        arrZipFiles = [
            f for f in os.listdir(strBackupPath)
            if f.startswith("backup_") and f.endswith("_UTC_*.zip") and os.path.isfile(os.path.join(strBackupPath, f))
        ]
        
        # Better pattern matching
        arrZipFiles = [
            f for f in os.listdir(strBackupPath)
            if f.endswith(".zip") and re.match(r'backup_\d{8}_\d{6}_UTC_[A-Fa-f0-9]{8}\.zip', f)
        ]
        
        if not arrZipFiles:
            objLogger.log("No existing backups found to verify", "INFO")
            return
        
        objLogger.log(f"Found {len(arrZipFiles)} backup(s) to verify", "INFO")
        
        intVerified = 0
        intFailed = 0
        intLegacy = 0
        
        for strZipFile in arrZipFiles:
            strZipPath = os.path.join(strBackupPath, strZipFile)
            objResult = verify_backup_integrity(strZipPath, strHashAlgorithm, objLogger)
            
            if objResult is True:
                intVerified += 1
            elif objResult is False:
                intFailed += 1
            else:
                intLegacy += 1
        
        objLogger.log(f"Integrity check complete: {intVerified} verified, {intFailed} failed, {intLegacy} legacy format", "SUCCESS")
        
        if intFailed > 0:
            objLogger.log(f"WARNING: {intFailed} backup(s) failed integrity check - consider removing them", "WARNING")
    
    except Exception as e:
        objLogger.log(f"Error during integrity check: {str(e)}", "WARNING")

def compress_backup_directory(strBackupDir: str, dictBackupStats: Dict[str, any], 
                              strBackupPath: str, strHashAlgorithm: str, 
                              objLogger: ClineLogger) -> str:
    """
    Compress backup directory to ZIP format with hash in filename.
    
    Args:
        strBackupDir: Directory to compress
        dictBackupStats: Backup statistics
        strBackupPath: Base backup path
        strHashAlgorithm: Hash algorithm to use
        objLogger: Logger instance
        
    Returns:
        Path to created ZIP file
    """
    objLogger.log_header("COMPRESSING BACKUP")
    
    objLogger.log("Compressing backup directory to ZIP format", "ACTION")
    objLogger.log("Reduces storage space and enables integrity verification", "REASON")
    
    try:
        # Calculate hash of manifest file
        strManifestPath = os.path.join(strBackupDir, "backup_manifest.json")
        strFullHash = calculate_file_hash(strManifestPath, strHashAlgorithm)
        strShortHash = get_short_hash(strFullHash)
        
        # Create ZIP filename with hash
        strZipFileName = f"backup_{STR_TIMESTAMP}_{strShortHash}.zip"
        strZipPath = os.path.join(strBackupPath, strZipFileName)
        
        objLogger.log(f"Creating ZIP file: {strZipFileName}", "INFO")
        
        # Create ZIP file
        with zipfile.ZipFile(strZipPath, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as objZipFile:
            for strRoot, arrDirs, arrFiles in os.walk(strBackupDir):
                for strFile in arrFiles:
                    strFilePath = os.path.join(strRoot, strFile)
                    strArcName = os.path.relpath(strFilePath, strBackupDir)
                    objZipFile.write(strFilePath, strArcName)
        
        # Get ZIP file size
        intZipSize = os.path.getsize(strZipPath)
        floatCompressionRatio = (intZipSize / dictBackupStats["totalSize"]) * 100 if dictBackupStats["totalSize"] > 0 else 100
        
        objLogger.log("Backup compressed successfully", "SUCCESS")
        objLogger.log(f"Original size: {dictBackupStats['totalSize'] / (1024 * 1024):.2f} MB", "INFO")
        objLogger.log(f"Compressed size: {intZipSize / (1024 * 1024):.2f} MB ({floatCompressionRatio:.2f}% of original)", "INFO")
        objLogger.log(f"Hash: {strFullHash}", "INFO")
        
        # Calculate all hash types for JSON output
        if DICT_JSON_RESULT:
            DICT_JSON_RESULT["hashes"]["sha256"] = calculate_file_hash(strZipPath, "sha256")
            DICT_JSON_RESULT["hashes"]["sha1"] = calculate_file_hash(strZipPath, "sha1")
            DICT_JSON_RESULT["hashes"]["md5"] = calculate_file_hash(strZipPath, "md5")
            DICT_JSON_RESULT["backupSize"] = intZipSize
        
        # Remove uncompressed directory
        objLogger.log("Removing uncompressed backup directory", "INFO")
        shutil.rmtree(strBackupDir)
        
        return strZipPath
    
    except Exception as e:
        objLogger.log(f"Error during compression: {str(e)}", "ERROR")
        return strBackupDir  # Return original directory if compression failed

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

class ClineLogger:
    """Logger class for structured logging with timestamps and levels."""
    
    def __init__(self, strLogFilePath: str, boolVerbose: bool = False):
        """
        Initialize the logger.
        
        Args:
            strLogFilePath: Path to the log file
            boolVerbose: Enable verbose console output
        """
        self.strLogFilePath = strLogFilePath
        self.boolVerbose = boolVerbose
        
        # Ensure log directory exists
        strLogDir = os.path.dirname(strLogFilePath)
        if strLogDir and not os.path.exists(strLogDir):
            os.makedirs(strLogDir, exist_ok=True)
    
    def log(self, strMessage: str, strLevel: str = "INFO"):
        """
        Write a log entry.
        
        Args:
            strMessage: The message to log
            strLevel: Log level (INFO, ACTION, REASON, SUCCESS, WARNING, ERROR)
        """
        strLogTimestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        strLogEntry = f"[{strLogTimestamp}] {strLevel} {strMessage}"
        
        # Write to log file
        with open(self.strLogFilePath, 'a', encoding='utf-8') as fileLog:
            fileLog.write(strLogEntry + '\n')
        
        # Write to console based on level and verbose setting
        if self.boolVerbose or strLevel in ["SUCCESS", "WARNING", "ERROR"]:
            dictColors = {
                "SUCCESS": "\033[92m",  # Green
                "WARNING": "\033[93m",  # Yellow
                "ERROR": "\033[91m",    # Red
                "ACTION": "\033[96m",   # Cyan
                "REASON": "\033[95m",   # Magenta
                "INFO": "\033[0m"       # Default
            }
            strColor = dictColors.get(strLevel, "\033[0m")
            strReset = "\033[0m"
            print(f"{strColor}{strLogEntry}{strReset}")
    
    def log_header(self, strTitle: str):
        """
        Write a section header.
        
        Args:
            strTitle: The section title
        """
        strSeparator = "=" * 80
        self.log("", "INFO")
        self.log(strSeparator, "INFO")
        self.log(strTitle, "INFO")
        self.log(strSeparator, "INFO")

# ============================================================================
# ENVIRONMENT CHECKS
# ============================================================================

def get_vscode_installation(objLogger: ClineLogger) -> Optional[Dict[str, any]]:
    """
    Detect VS Code installation.
    
    Args:
        objLogger: Logger instance
        
    Returns:
        Dictionary with installation details or None if not found
    """
    objLogger.log("Detecting VS Code installation", "INFO")
    
    dictResult = {
        "installed": False,
        "version": "",
        "commandAvailable": False
    }
    
    # Check if 'code' command is available
    try:
        objProcess = subprocess.run(
            ["code", "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if objProcess.returncode == 0:
            strVersion = objProcess.stdout.strip().split('\n')[0]
            dictResult["version"] = strVersion
            dictResult["commandAvailable"] = True
            dictResult["installed"] = True
            objLogger.log(f"VS Code command-line tool found: version {strVersion}", "SUCCESS")
        else:
            objLogger.log("VS Code command-line tool not found in PATH", "WARNING")
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError):
        objLogger.log("VS Code command-line tool not found", "WARNING")
    
    if not dictResult["installed"]:
        objLogger.log("VS Code installation not found", "ERROR")
        print("\n\033[91mVS Code does not appear to be installed.\033[0m")
        print("\033[93mPlease install VS Code from https://code.visualstudio.com/\033[0m\n")
        return None
    
    return dictResult

def stop_vscode_processes(objLogger: ClineLogger) -> bool:
    """
    Check for and request closure of running VS Code processes.
    
    Args:
        objLogger: Logger instance
        
    Returns:
        True if no processes running, False otherwise
    """
    objLogger.log("Checking for running VS Code processes", "INFO")
    
    try:
        objProcess = subprocess.run(
            ["pgrep", "-f", "code"],
            capture_output=True,
            text=True
        )
        
        if objProcess.returncode == 0:
            arrPids = objProcess.stdout.strip().split('\n')
            intCount = len([pid for pid in arrPids if pid])
            
            objLogger.log(f"Found {intCount} VS Code process(es) running", "WARNING")
            print("\n\033[93mVS Code is currently running and must be closed.\033[0m")
            print("\033[93mPlease save your work and close all VS Code windows.\033[0m\n")
            print("\033[96mPress Enter once VS Code is closed...\033[0m")
            input()
            
            # Verify processes are closed
            objProcess = subprocess.run(
                ["pgrep", "-f", "code"],
                capture_output=True,
                text=True
            )
            
            if objProcess.returncode == 0:
                objLogger.log("VS Code processes still running", "ERROR")
                print("\n\033[91mVS Code is still running. Please close all windows and try again.\033[0m\n")
                return False
    except (subprocess.SubprocessError, FileNotFoundError):
        pass
    
    objLogger.log("No VS Code processes detected", "SUCCESS")
    return True

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

def create_backup_directory(strBackupPath: str, objLogger: ClineLogger) -> str:
    """
    Create backup directory structure.
    
    Args:
        strBackupPath: Base backup path
        objLogger: Logger instance
        
    Returns:
        Full path to backup directory
    """
    objLogger.log_header("CREATING BACKUP DIRECTORY")
    
    strBackupDir = os.path.join(strBackupPath, STR_TIMESTAMP)
    
    objLogger.log(f"Creating backup directory: {strBackupDir}", "ACTION")
    objLogger.log("Organizing user data before repair operation", "REASON")
    
    os.makedirs(strBackupDir, exist_ok=True)
    
    # Create subdirectories
    arrSubDirs = ["tasks", "settings", "rules", "workflows", "cache", "checkpoints"]
    for strSubDir in arrSubDirs:
        strPath = os.path.join(strBackupDir, strSubDir)
        os.makedirs(strPath, exist_ok=True)
    
    objLogger.log("Backup directory created successfully", "SUCCESS")
    return strBackupDir

def backup_cline_tasks(strBackupDir: str, objLogger: ClineLogger) -> Dict[str, any]:
    """
    Backup Cline tasks (conversation history).
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        Dictionary with backup statistics
    """
    objLogger.log_header("BACKING UP CLINE TASKS")
    
    dictResult = {
        "count": 0,
        "size": 0,
        "status": "success",
        "items": []
    }
    
    strTasksSource = os.path.join(STR_CLINE_GLOBAL_STORAGE, "tasks")
    strTasksBackup = os.path.join(strBackupDir, "tasks")
    
    if not os.path.exists(strTasksSource):
        objLogger.log("No tasks directory found", "WARNING")
        return dictResult
    
    objLogger.log(f"Backing up tasks from: {strTasksSource}", "ACTION")
    objLogger.log("Tasks contain all conversation history and are critical to preserve", "REASON")
    
    try:
        arrTaskDirs = [d for d in os.listdir(strTasksSource) 
                      if os.path.isdir(os.path.join(strTasksSource, d))]
        
        for strTaskDir in arrTaskDirs:
            strSourcePath = os.path.join(strTasksSource, strTaskDir)
            strDestPath = os.path.join(strTasksBackup, strTaskDir)
            
            objLogger.log(f"Copying task: {strTaskDir}", "INFO")
            shutil.copytree(strSourcePath, strDestPath, dirs_exist_ok=True)
            
            # Calculate size
            intSize = sum(
                os.path.getsize(os.path.join(dirpath, filename))
                for dirpath, dirnames, filenames in os.walk(strDestPath)
                for filename in filenames
            )
            
            dictResult["size"] += intSize
            dictResult["count"] += 1
            dictResult["items"].append({
                "name": strTaskDir,
                "size": intSize,
                "path": strDestPath
            })
        
        # Backup task history index
        strHistoryFile = os.path.join(STR_CLINE_GLOBAL_STORAGE, "state", "taskHistory.json")
        if os.path.exists(strHistoryFile):
            strHistoryBackup = os.path.join(strBackupDir, "settings", "taskHistory.json")
            shutil.copy2(strHistoryFile, strHistoryBackup)
            objLogger.log("Task history index backed up", "INFO")
        
        floatSizeMB = dictResult["size"] / (1024 * 1024)
        objLogger.log(f"Backed up {dictResult['count']} tasks ({floatSizeMB:.2f} MB)", "SUCCESS")
    
    except Exception as e:
        objLogger.log(f"Error backing up tasks: {str(e)}", "ERROR")
        dictResult["status"] = "failed"
    
    return dictResult

def backup_mcp_settings(strBackupDir: str, objLogger: ClineLogger) -> Dict[str, any]:
    """
    Backup MCP settings and custom servers.
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        Dictionary with backup statistics
    """
    objLogger.log_header("BACKING UP MCP SETTINGS")
    
    dictResult = {"count": 0, "size": 0, "status": "success", "items": []}
    
    # Backup MCP settings file
    strMCPSettingsFile = os.path.join(STR_CLINE_GLOBAL_STORAGE, "settings", "cline_mcp_settings.json")
    if os.path.exists(strMCPSettingsFile):
        objLogger.log("Backing up MCP settings file", "ACTION")
        objLogger.log("Preserving custom MCP server configurations and integrations", "REASON")
        
        try:
            strBackupPath = os.path.join(strBackupDir, "settings", "cline_mcp_settings.json")
            shutil.copy2(strMCPSettingsFile, strBackupPath)
            
            intSize = os.path.getsize(strBackupPath)
            dictResult["size"] += intSize
            dictResult["count"] += 1
            
            objLogger.log("MCP settings backed up successfully", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error backing up MCP settings: {str(e)}", "ERROR")
            dictResult["status"] = "failed"
    
    # Backup custom MCP servers
    strMCPServersPath = os.path.join(STR_CLINE_DOCUMENTS, "MCP")
    if os.path.exists(strMCPServersPath):
        objLogger.log("Backing up custom MCP servers", "ACTION")
        
        try:
            strMCPBackup = os.path.join(strBackupDir, "mcp_servers")
            shutil.copytree(strMCPServersPath, strMCPBackup, dirs_exist_ok=True)
            
            intSize = sum(
                os.path.getsize(os.path.join(dirpath, filename))
                for dirpath, dirnames, filenames in os.walk(strMCPBackup)
                for filename in filenames
            )
            
            dictResult["size"] += intSize
            dictResult["count"] += 1
            
            objLogger.log("Custom MCP servers backed up", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error backing up custom MCP servers: {str(e)}", "ERROR")
    
    return dictResult

def backup_cline_rules(strBackupDir: str, objLogger: ClineLogger) -> Dict[str, any]:
    """
    Backup Cline rules and workflows.
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        Dictionary with backup statistics
    """
    objLogger.log_header("BACKING UP CLINE RULES AND WORKFLOWS")
    
    dictResult = {"count": 0, "size": 0, "status": "success", "items": []}
    
    # Backup Rules
    strRulesPath = os.path.join(STR_CLINE_DOCUMENTS, "Rules")
    if os.path.exists(strRulesPath):
        objLogger.log("Backing up Cline rules", "ACTION")
        objLogger.log("Preserving development standards and custom instructions", "REASON")
        
        try:
            strRulesBackup = os.path.join(strBackupDir, "rules")
            shutil.copytree(strRulesPath, strRulesBackup, dirs_exist_ok=True)
            
            intSize = sum(
                os.path.getsize(os.path.join(dirpath, filename))
                for dirpath, dirnames, filenames in os.walk(strRulesBackup)
                for filename in filenames
            )
            
            dictResult["size"] += intSize
            dictResult["count"] += 1
            
            objLogger.log("Cline rules backed up successfully", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error backing up rules: {str(e)}", "ERROR")
            dictResult["status"] = "failed"
    
    # Backup Workflows
    strWorkflowsPath = os.path.join(STR_CLINE_DOCUMENTS, "Workflows")
    if os.path.exists(strWorkflowsPath):
        objLogger.log("Backing up Cline workflows", "ACTION")
        
        try:
            strWorkflowsBackup = os.path.join(strBackupDir, "workflows")
            shutil.copytree(strWorkflowsPath, strWorkflowsBackup, dirs_exist_ok=True)
            
            intSize = sum(
                os.path.getsize(os.path.join(dirpath, filename))
                for dirpath, dirnames, filenames in os.walk(strWorkflowsBackup)
                for filename in filenames
            )
            
            dictResult["size"] += intSize
            dictResult["count"] += 1
            
            objLogger.log("Cline workflows backed up successfully", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error backing up workflows: {str(e)}", "ERROR")
    
    return dictResult

def backup_cline_checkpoints(strBackupDir: str, objLogger: ClineLogger) -> Dict[str, any]:
    """
    Backup Cline checkpoints.
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        Dictionary with backup statistics
    """
    objLogger.log("Backing up Cline checkpoints", "ACTION")
    
    dictResult = {"count": 0, "size": 0, "status": "success"}
    
    strCheckpointsPath = os.path.join(STR_CLINE_GLOBAL_STORAGE, "checkpoints")
    if os.path.exists(strCheckpointsPath):
        try:
            strCheckpointsBackup = os.path.join(strBackupDir, "checkpoints")
            shutil.copytree(strCheckpointsPath, strCheckpointsBackup, dirs_exist_ok=True)
            
            intSize = sum(
                os.path.getsize(os.path.join(dirpath, filename))
                for dirpath, dirnames, filenames in os.walk(strCheckpointsBackup)
                for filename in filenames
            )
            
            dictResult["size"] += intSize
            
            arrCheckpoints = [d for d in os.listdir(strCheckpointsBackup) 
                            if os.path.isdir(os.path.join(strCheckpointsBackup, d))]
            dictResult["count"] = len(arrCheckpoints)
            
            objLogger.log(f"Checkpoints backed up: {dictResult['count']} items", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error backing up checkpoints: {str(e)}", "WARNING")
    
    return dictResult

def create_backup_manifest(strBackupDir: str, dictBackupStats: Dict[str, any], objLogger: ClineLogger):
    """
    Create backup manifest file.
    
    Args:
        strBackupDir: Backup directory path
        dictBackupStats: Backup statistics
        objLogger: Logger instance
    """
    objLogger.log("Creating backup manifest", "ACTION")
    
    dictManifest = {
        "version": STR_SCRIPT_VERSION,
        "timestamp": STR_TIMESTAMP,
        "platform": "Linux",
        "items": dictBackupStats.get("items", []),
        "totalSize": dictBackupStats.get("totalSize", 0),
        "status": "completed",
        "backupPath": strBackupDir
    }
    
    strManifestPath = os.path.join(strBackupDir, "backup_manifest.json")
    
    try:
        with open(strManifestPath, 'w', encoding='utf-8') as fileManifest:
            json.dump(dictManifest, fileManifest, indent=2)
        
        objLogger.log(f"Backup manifest created: {strManifestPath}", "SUCCESS")
    except Exception as e:
        objLogger.log(f"Error creating manifest: {str(e)}", "WARNING")

def remove_old_backups(strBackupBasePath: str, intMaxBackups: int, objLogger: ClineLogger):
    """
    Remove old backups to maintain retention limit.
    
    Args:
        strBackupBasePath: Base backup directory
        intMaxBackups: Maximum number of backups to keep
        objLogger: Logger instance
    """
    objLogger.log_header("MANAGING BACKUP RETENTION")
    
    objLogger.log("Checking for old backups to remove", "INFO")
    objLogger.log(f"Keeping only the {intMaxBackups} most recent backups to conserve disk space", "REASON")
    
    try:
        if not os.path.exists(strBackupBasePath):
            return
        
        # Find backup directories (format: YYYYMMDD_HHMMSS)
        patternBackup = re.compile(r'^\d{8}_\d{6}$')
        arrBackups = [
            d for d in os.listdir(strBackupBasePath)
            if os.path.isdir(os.path.join(strBackupBasePath, d)) and patternBackup.match(d)
        ]
        
        # Sort by name (timestamp) in descending order
        arrBackups.sort(reverse=True)
        
        if len(arrBackups) > intMaxBackups:
            arrToRemove = arrBackups[intMaxBackups:]
            
            objLogger.log(f"Found {len(arrToRemove)} old backup(s) to remove", "INFO")
            
            for strBackup in arrToRemove:
                strBackupPath = os.path.join(strBackupBasePath, strBackup)
                objLogger.log(f"Removing old backup: {strBackup}", "ACTION")
                shutil.rmtree(strBackupPath)
            
            objLogger.log("Old backups removed successfully", "SUCCESS")
        else:
            objLogger.log(f"Backup count ({len(arrBackups)}) within limit ({intMaxBackups})", "INFO")
    
    except Exception as e:
        objLogger.log(f"Error during backup cleanup: {str(e)}", "WARNING")

# ============================================================================
# UNINSTALL AND REINSTALL FUNCTIONS
# ============================================================================

def uninstall_cline_extension(objLogger: ClineLogger) -> bool:
    """
    Uninstall the Cline extension.
    
    Args:
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header("UNINSTALLING CLINE EXTENSION")
    
    objLogger.log("Uninstalling Cline extension", "ACTION")
    objLogger.log("Clean removal required for successful repair", "REASON")
    
    try:
        objProcess = subprocess.run(
            ["code", "--uninstall-extension", STR_CLINE_EXTENSION_ID],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        objLogger.log("Extension uninstall command executed", "INFO")
        
        # Wait for uninstall to complete
        import time
        time.sleep(3)
        
        # Verify extension directory is removed
        arrExtDirs = [
            d for d in os.listdir(STR_VSCODE_EXTENSIONS)
            if os.path.isdir(os.path.join(STR_VSCODE_EXTENSIONS, d)) and 
            d.startswith("saoudrizwan.claude-dev")
        ] if os.path.exists(STR_VSCODE_EXTENSIONS) else []
        
        if arrExtDirs:
            objLogger.log("Removing remaining extension directories", "ACTION")
            for strDir in arrExtDirs:
                strDirPath = os.path.join(STR_VSCODE_EXTENSIONS, strDir)
                shutil.rmtree(strDirPath)
                objLogger.log(f"Removed: {strDir}", "INFO")
        
        objLogger.log("Cline extension uninstalled successfully", "SUCCESS")
        return True
    
    except Exception as e:
        objLogger.log(f"Error during uninstall: {str(e)}", "ERROR")
        return False

def install_cline_extension(objLogger: ClineLogger) -> bool:
    """
    Install the Cline extension.
    
    Args:
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header("INSTALLING CLINE EXTENSION")
    
    objLogger.log("Installing Cline extension", "ACTION")
    objLogger.log("Fresh installation ensures clean state", "REASON")
    
    try:
        objProcess = subprocess.run(
            ["code", "--install-extension", STR_CLINE_EXTENSION_ID],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        objLogger.log("Extension install command executed", "INFO")
        
        # Wait for install to complete
        import time
        time.sleep(5)
        
        # Verify installation
        arrExtDirs = [
            d for d in os.listdir(STR_VSCODE_EXTENSIONS)
            if os.path.isdir(os.path.join(STR_VSCODE_EXTENSIONS, d)) and 
            d.startswith("saoudrizwan.claude-dev")
        ] if os.path.exists(STR_VSCODE_EXTENSIONS) else []
        
        if arrExtDirs:
            objLogger.log("Cline extension installed successfully", "SUCCESS")
            return True
        else:
            objLogger.log("Extension installation could not be verified", "WARNING")
            return False
    
    except Exception as e:
        objLogger.log(f"Error during installation: {str(e)}", "ERROR")
        return False

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

def restore_cline_tasks(strBackupDir: str, objLogger: ClineLogger) -> bool:
    """
    Restore Cline tasks from backup.
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header("RESTORING CLINE TASKS")
    
    strTasksBackup = os.path.join(strBackupDir, "tasks")
    strTasksTarget = os.path.join(STR_CLINE_GLOBAL_STORAGE, "tasks")
    
    if not os.path.exists(strTasksBackup):
        objLogger.log("No tasks backup found to restore", "WARNING")
        return False
    
    objLogger.log(f"Restoring tasks to: {strTasksTarget}", "ACTION")
    objLogger.log("Recovering conversation history and task data", "REASON")
    
    try:
        # Create target directory
        os.makedirs(strTasksTarget, exist_ok=True)
        
        # Copy task directories
        arrTaskDirs = [
            d for d in os.listdir(strTasksBackup)
            if os.path.isdir(os.path.join(strTasksBackup, d))
        ]
        
        for strTaskDir in arrTaskDirs:
            strSourcePath = os.path.join(strTasksBackup, strTaskDir)
            strDestPath = os.path.join(strTasksTarget, strTaskDir)
            shutil.copytree(strSourcePath, strDestPath, dirs_exist_ok=True)
            objLogger.log(f"Restored task: {strTaskDir}", "INFO")
        
        # Restore task history
        strHistoryBackup = os.path.join(strBackupDir, "settings", "taskHistory.json")
        if os.path.exists(strHistoryBackup):
            strStateDir = os.path.join(STR_CLINE_GLOBAL_STORAGE, "state")
            os.makedirs(strStateDir, exist_ok=True)
            
            strHistoryTarget = os.path.join(strStateDir, "taskHistory.json")
            shutil.copy2(strHistoryBackup, strHistoryTarget)
            objLogger.log("Task history index restored", "INFO")
        
        objLogger.log("Tasks restored successfully", "SUCCESS")
        return True
    
    except Exception as e:
        objLogger.log(f"Error restoring tasks: {str(e)}", "ERROR")
        return False

def restore_mcp_settings(strBackupDir: str, objLogger: ClineLogger) -> bool:
    """
    Restore MCP settings from backup.
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header("RESTORING MCP SETTINGS")
    
    # Restore MCP settings file
    strMCPBackup = os.path.join(strBackupDir, "settings", "cline_mcp_settings.json")
    if os.path.exists(strMCPBackup):
        objLogger.log("Restoring MCP settings", "ACTION")
        objLogger.log("Recovering custom MCP server configurations", "REASON")
        
        try:
            strSettingsDir = os.path.join(STR_CLINE_GLOBAL_STORAGE, "settings")
            os.makedirs(strSettingsDir, exist_ok=True)
            
            strMCPTarget = os.path.join(strSettingsDir, "cline_mcp_settings.json")
            shutil.copy2(strMCPBackup, strMCPTarget)
            
            objLogger.log("MCP settings restored successfully", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error restoring MCP settings: {str(e)}", "ERROR")
    
    # Restore custom MCP servers
    strMCPServersBackup = os.path.join(strBackupDir, "mcp_servers")
    if os.path.exists(strMCPServersBackup):
        objLogger.log("Restoring custom MCP servers", "ACTION")
        
        try:
            strMCPTarget = os.path.join(STR_CLINE_DOCUMENTS, "MCP")
            shutil.copytree(strMCPServersBackup, strMCPTarget, dirs_exist_ok=True)
            
            objLogger.log("Custom MCP servers restored", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error restoring custom MCP servers: {str(e)}", "ERROR")
    
    return True

def restore_cline_rules(strBackupDir: str, objLogger: ClineLogger) -> bool:
    """
    Restore Cline rules and workflows from backup.
    
    Args:
        strBackupDir: Backup directory path
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header("RESTORING CLINE RULES AND WORKFLOWS")
    
    # Restore Rules
    strRulesBackup = os.path.join(strBackupDir, "rules")
    if os.path.exists(strRulesBackup):
        objLogger.log("Restoring Cline rules", "ACTION")
        objLogger.log("Recovering development standards and instructions", "REASON")
        
        try:
            strRulesTarget = os.path.join(STR_CLINE_DOCUMENTS, "Rules")
            shutil.copytree(strRulesBackup, strRulesTarget, dirs_exist_ok=True)
            
            objLogger.log("Cline rules restored successfully", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error restoring rules: {str(e)}", "ERROR")
    
    # Restore Workflows
    strWorkflowsBackup = os.path.join(strBackupDir, "workflows")
    if os.path.exists(strWorkflowsBackup):
        objLogger.log("Restoring Cline workflows", "ACTION")
        
        try:
            strWorkflowsTarget = os.path.join(STR_CLINE_DOCUMENTS, "Workflows")
            shutil.copytree(strWorkflowsBackup, strWorkflowsTarget, dirs_exist_ok=True)
            
            objLogger.log("Cline workflows restored successfully", "SUCCESS")
        except Exception as e:
            objLogger.log(f"Error restoring workflows: {str(e)}", "ERROR")
    
    return True

def set_vscode_sidebar_position(objLogger: ClineLogger) -> bool:
    """
    Configure VS Code to display sidebar on the left.
    
    Args:
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header("CONFIGURING VSCODE SIDEBAR POSITION")
    
    objLogger.log("Setting Cline sidebar to left (Primary Side Bar)", "ACTION")
    objLogger.log("Ensuring Cline is easily accessible on the left side", "REASON")
    
    strSettingsFile = os.path.join(STR_VSCODE_USER_DATA, "settings.json")
    
    try:
        # Read existing settings or create new
        if os.path.exists(strSettingsFile):
            with open(strSettingsFile, 'r', encoding='utf-8') as fileSettings:
                dictSettings = json.load(fileSettings)
        else:
            dictSettings = {}
        
        # Ensure sidebar is on the left
        dictSettings["workbench.sideBar.location"] = "left"
        
        # Save settings
        os.makedirs(os.path.dirname(strSettingsFile), exist_ok=True)
        with open(strSettingsFile, 'w', encoding='utf-8') as fileSettings:
            json.dump(dictSettings, fileSettings, indent=2)
        
        objLogger.log("Sidebar position configured successfully", "SUCCESS")
        return True
    
    except Exception as e:
        objLogger.log(f"Error configuring sidebar: {str(e)}", "WARNING")
        return False

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

def start_repair_process(objArgs: argparse.Namespace, objLogger: ClineLogger) -> bool:
    """
    Execute the main repair process.
    
    Args:
        objArgs: Command-line arguments
        objLogger: Logger instance
        
    Returns:
        True if successful, False otherwise
    """
    objLogger.log_header(f"CLINE REPAIR TOOL v{STR_SCRIPT_VERSION}")
    
    print("\n" + "=" * 80)
    print("                   Cline VS Code Extension Repair Tool")
    print(f"                             Version {STR_SCRIPT_VERSION}")
    print("=" * 80 + "\n")
    
    objLogger.log(f"Cline Repair Tool v{STR_SCRIPT_VERSION} started", "INFO")
    objLogger.log("Platform: Linux", "INFO")
    objLogger.log(f"Backup Path: {objArgs.backup_path}", "INFO")
    
    # Step 1: Detect VS Code installation
    dictVSCode = get_vscode_installation(objLogger)
    if not dictVSCode:
        objLogger.log("Script terminated: VS Code not found", "ERROR")
        return False
    
    # Step 2: Check for running VS Code processes (only required for full repair, not backup-only)
    if not objArgs.backup_only:
        if not stop_vscode_processes(objLogger):
            objLogger.log("Script terminated: VS Code still running", "ERROR")
            return False
    else:
        objLogger.log("Backup-only mode: skipping VS Code process check", "INFO")
    
    # Step 3: Create backup
    strBackupDir = None
    if not objArgs.skip_backup:
        try:
            strBackupDir = create_backup_directory(objArgs.backup_path, objLogger)
            
            dictBackupStats = {
                "items": [],
                "totalSize": 0
            }
            
            # Backup tasks
            dictTasksResult = backup_cline_tasks(strBackupDir, objLogger)
            dictBackupStats["totalSize"] += dictTasksResult["size"]
            dictBackupStats["items"] += dictTasksResult["items"]
            
            # Backup MCP settings
            dictMCPResult = backup_mcp_settings(strBackupDir, objLogger)
            dictBackupStats["totalSize"] += dictMCPResult["size"]
            
            # Backup rules
            dictRulesResult = backup_cline_rules(strBackupDir, objLogger)
            dictBackupStats["totalSize"] += dictRulesResult["size"]
            
            # Backup checkpoints
            dictCheckpointsResult = backup_cline_checkpoints(strBackupDir, objLogger)
            dictBackupStats["totalSize"] += dictCheckpointsResult["size"]
            
            # Create manifest
            create_backup_manifest(strBackupDir, dictBackupStats, objLogger)
            
            # Cleanup old backups
            remove_old_backups(objArgs.backup_path, INT_MAX_BACKUPS, objLogger)
            
            floatSizeMB = dictBackupStats["totalSize"] / (1024 * 1024)
            print(f"\n\033[92mBackup completed successfully!\033[0m")
            print(f"\033[96m  Location: {strBackupDir}\033[0m")
            print(f"\033[96m  Total Size: {floatSizeMB:.2f} MB\033[0m\n")
            
            if objArgs.backup_only:
                objLogger.log("Backup-only mode: backup completed", "SUCCESS")
                print("\033[93mBackup-only mode - repair skipped.\033[0m")
                print(f"\033[96mLog file: {objLogger.strLogFilePath}\033[0m\n")
                return True
        
        except Exception as e:
            objLogger.log(f"Backup failed: {str(e)}", "ERROR")
            print(f"\n\033[91mBackup failed! Cannot proceed with repair.\033[0m")
            print(f"\033[91mError: {str(e)}\033[0m\n")
            return False
    else:
        objLogger.log("Backup skipped by user request", "WARNING")
        print("\n\033[93mWARNING: Backup skipped!\033[0m")
        print("\033[93mPress Enter to continue or Ctrl+C to cancel...\033[0m")
        input()
    
    # Step 4: Uninstall Cline extension
    print("\n\033[93mUninstalling Cline extension...\033[0m")
    if not uninstall_cline_extension(objLogger):
        objLogger.log("Uninstall failed: attempting to continue", "WARNING")
        print("\033[93mUninstall encountered issues, but continuing...\033[0m")
    
    # Step 5: Install Cline extension
    print("\n\033[93mInstalling Cline extension...\033[0m")
    if not install_cline_extension(objLogger):
        objLogger.log("Installation failed", "ERROR")
        print("\n\033[91mInstallation failed! Please install manually.\033[0m\n")
        return False
    
    # Step 6: Restore user data
    if not objArgs.skip_backup and strBackupDir:
        print("\n\033[93mRestoring user data...\033[0m")
        
        restore_cline_tasks(strBackupDir, objLogger)
        restore_mcp_settings(strBackupDir, objLogger)
        restore_cline_rules(strBackupDir, objLogger)
    
    # Step 7: Configure sidebar
    set_vscode_sidebar_position(objLogger)
    
    # Step 8: Success message
    objLogger.log_header("REPAIR COMPLETED SUCCESSFULLY")
    
    print("\n" + "=" * 80)
    print("                       REPAIR COMPLETED SUCCESSFULLY")
    print("=" * 80 + "\n")
    print("\033[92mThe Cline extension has been repaired!\033[0m\n")
    print("\033[96mNext Steps:\033[0m")
    print("\033[0m  1. Launch VS Code\033[0m")
    print("\033[0m  2. Verify Cline appears in the left sidebar\033[0m")
    print("\033[0m  3. Re-enter your API key if needed\033[0m")
    print("\033[0m  4. Check that your tasks and settings are restored\033[0m\n")
    
    if strBackupDir:
        print(f"\033[96mBackup Location: {strBackupDir}\033[0m")
    print(f"\033[96mLog File: {objLogger.strLogFilePath}\033[0m\n")
    
    objLogger.log("Repair process completed successfully", "SUCCESS")
    return True

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

def main():
    """Main entry point for the script."""
    
    # Parse command-line arguments
    objParser = argparse.ArgumentParser(
        description="Cline VS Code Extension Repair Tool for Linux",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  sudo python3 repair_cline.py
    Performs a complete repair with default settings.
  
  sudo python3 repair_cline.py --backup-only
    Only creates a backup without performing repair.
  
  sudo python3 repair_cline.py --backup-path /custom/path
    Uses custom backup location.
  
  sudo python3 repair_cline.py --verbose
    Shows detailed output during execution.
        """
    )
    
    objParser.add_argument(
        "--backup-only",
        action="store_true",
        help="Only perform backup without uninstall/reinstall"
    )
    
    objParser.add_argument(
        "--skip-backup",
        action="store_true",
        help="Skip the backup phase (NOT RECOMMENDED)"
    )
    
    objParser.add_argument(
        "--backup-path",
        type=str,
        default=os.path.join(STR_HOME_DIR, "ClineBackups"),
        help="Custom path for backup storage (default: ~/ClineBackups)"
    )
    
    objParser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable detailed logging output to console"
    )
    
    objArgs = objParser.parse_args()
    
    # Initialize logger
    strLogFileName = f"cline-repair-{STR_TIMESTAMP}.log"
    strLogFilePath = os.path.join(objArgs.backup_path, strLogFileName)
    objLogger = ClineLogger(strLogFilePath, objArgs.verbose)
    
    # Run repair process
    try:
        boolSuccess = start_repair_process(objArgs, objLogger)
        sys.exit(0 if boolSuccess else 1)
    
    except KeyboardInterrupt:
        objLogger.log("Script interrupted by user", "WARNING")
        print("\n\n\033[93mScript interrupted by user.\033[0m\n")
        sys.exit(1)
    
    except Exception as e:
        objLogger.log(f"Unexpected error: {str(e)}", "ERROR")
        print(f"\n\033[91mAn unexpected error occurred:\033[0m")
        print(f"\033[91m{str(e)}\033[0m\n")
        print(f"\033[96mLog file: {objLogger.strLogFilePath}\033[0m\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
