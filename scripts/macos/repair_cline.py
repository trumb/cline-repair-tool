#!/usr/bin/env python3
"""
Cline VS Code Extension Repair Tool for macOS

This script performs a complete repair of the Cline VS Code extension by:
1. Backing up all user data (tasks, history, MCP settings, rules, workflows)
2. Uninstalling the current Cline extension
3. Performing a clean reinstallation
4. Restoring all user data
5. Configuring the sidebar position to left (Primary Side Bar)

The script requires root/sudo privileges to ensure complete access to all
VS Code directories and proper extension management.

Version: 1.0.0
Author: Cline Repair Tool
Created: 2025-11-24
Requires: Python 3.6+, sudo privileges, VS Code installed
"""

import os
import sys
import json
import shutil
import subprocess
import argparse
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

STR_SCRIPT_VERSION = "1.0.0"
STR_TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
STR_CLINE_EXTENSION_ID = "saoudrizwan.claude-dev"
INT_MAX_BACKUPS = 5

# Data location paths (macOS)
STR_HOME_DIR = str(Path.home())
STR_VSCODE_EXTENSIONS = os.path.join(STR_HOME_DIR, ".vscode", "extensions")
STR_VSCODE_USER_DATA = os.path.join(STR_HOME_DIR, "Library", "Application Support", "Code", "User")
STR_CLINE_GLOBAL_STORAGE = os.path.join(STR_VSCODE_USER_DATA, "globalStorage", "saoudrizwan.claude-dev")
STR_CLINE_DOCUMENTS = os.path.join(STR_HOME_DIR, "Documents", "Cline")

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
# PRIVILEGE AND ENVIRONMENT CHECKS
# ============================================================================

def check_root_privileges(objLogger: ClineLogger) -> bool:
    """
    Check if script is running with root/sudo privileges.
    
    Args:
        objLogger: Logger instance
        
    Returns:
        True if running as root, False otherwise
    """
    objLogger.log("Checking for root/sudo privileges", "INFO")
    
    intUid = os.getuid()
    
    if intUid != 0:
        objLogger.log("ERROR: This script requires root/sudo privileges", "ERROR")
        print("\n\033[93mPlease run this script with sudo:\033[0m")
        print("\033[96m  sudo python3 repair_cline.py\033[0m\n")
        return False
    
    objLogger.log("Root privileges confirmed", "SUCCESS")
    return True

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
            ["pgrep", "-f", "Visual Studio Code"],
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
                ["pgrep", "-f", "Visual Studio Code"],
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
        "platform": "macOS",
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
    objLogger.log("Platform: macOS", "INFO")
    objLogger.log(f"Backup Path: {objArgs.backup_path}", "INFO")
    
    # Step 1: Check root privileges
    if not check_root_privileges(objLogger):
        objLogger.log("Script terminated due to insufficient privileges", "ERROR")
        return False
    
    # Step 2: Detect VS Code installation
    dictVSCode = get_vscode_installation(objLogger)
    if not dictVSCode:
        objLogger.log("Script terminated: VS Code not found", "ERROR")
        return False
    
    # Step 3: Check for running VS Code processes
    if not stop_vscode_processes(objLogger):
        objLogger.log("Script terminated: VS Code still running", "ERROR")
        return False
    
    # Step 4: Create backup
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
    
    # Step 5: Uninstall Cline extension
    print("\n\033[93mUninstalling Cline extension...\033[0m")
    if not uninstall_cline_extension(objLogger):
        objLogger.log("Uninstall failed: attempting to continue", "WARNING")
        print("\033[93mUninstall encountered issues, but continuing...\033[0m")
    
    # Step 6: Install Cline extension
    print("\n\033[93mInstalling Cline extension...\033[0m")
    if not install_cline_extension(objLogger):
        objLogger.log("Installation failed", "ERROR")
        print("\n\033[91mInstallation failed! Please install manually.\033[0m\n")
        return False
    
    # Step 7: Restore user data
    if not objArgs.skip_backup and strBackupDir:
        print("\n\033[93mRestoring user data...\033[0m")
        
        restore_cline_tasks(strBackupDir, objLogger)
        restore_mcp_settings(strBackupDir, objLogger)
        restore_cline_rules(strBackupDir, objLogger)
    
    # Step 8: Configure sidebar
    set_vscode_sidebar_position(objLogger)
    
    # Step 9: Success message
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
        description="Cline VS Code Extension Repair Tool for macOS",
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
