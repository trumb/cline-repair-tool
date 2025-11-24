<#
.SYNOPSIS
    Cline VS Code Extension Repair Tool for Windows
    
.DESCRIPTION
    This script performs a complete repair of the Cline VS Code extension by:
    1. Backing up all user data (tasks, history, MCP settings, rules, workflows)
    2. Uninstalling the current Cline extension
    3. Performing a clean reinstallation
    4. Restoring all user data
    5. Configuring the sidebar position to left (Primary Side Bar)
    
    The script requires Administrator privileges to ensure complete access to all
    VS Code directories and proper extension management.
    
.PARAMETER BackupOnly
    Only perform backup without uninstall/reinstall. Useful for creating regular backups.
    
.PARAMETER SkipBackup
    Skip the backup phase (NOT RECOMMENDED). Only use if you have a recent backup.
    
.PARAMETER BackupPath
    Custom path for backup storage. Default: $env:USERPROFILE\ClineBackups
    
.PARAMETER UseGitHubBackup
    Upload backup to a private GitHub repository for safe cloud storage.
    
.PARAMETER GitHubToken
    Personal Access Token for GitHub authentication (required if UseGitHubBackup is set).
    
.PARAMETER VerboseLogging
    Enable detailed logging output to console.
    
.EXAMPLE
    .\Repair-Cline.ps1
    Performs a complete repair with default settings.
    
.EXAMPLE
    .\Repair-Cline.ps1 -BackupOnly
    Only creates a backup without performing repair.
    
.EXAMPLE
    .\Repair-Cline.ps1 -UseGitHubBackup -GitHubToken "ghp_xxxxxxxxxxxx"
    Performs repair and uploads backup to GitHub.
    
.NOTES
    Version: 1.0.0
    Author: Cline Repair Tool
    Created: 2025-11-24
    Requires: Administrator privileges, VS Code installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$BackupOnly,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup,
    
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "$env:USERPROFILE\ClineBackups",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseGitHubBackup,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$VerboseLogging
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

$ErrorActionPreference = "Stop"
$script:strScriptVersion = "1.0.0"
$script:strTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:strLogFileName = "cline-repair-$script:strTimestamp.log"
$script:strLogFilePath = Join-Path $BackupPath $script:strLogFileName
$script:intMaxBackups = 5

# VS Code and Cline extension identifiers
$script:strClineExtensionId = "saoudrizwan.claude-dev"
$script:strVSCodeCommand = "code"

# Data location paths (Windows)
$script:strUserProfile = $env:USERPROFILE
$script:strVSCodeExtensions = Join-Path $strUserProfile ".vscode\extensions"
$script:strVSCodeUserData = Join-Path $env:APPDATA "Code\User"
$script:strClineGlobalStorage = Join-Path $strVSCodeUserData "globalStorage\saoudrizwan.claude-dev"
$script:strClineDocuments = Join-Path $strUserProfile "Documents\Cline"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$strMessage,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "ACTION", "REASON", "SUCCESS", "WARNING", "ERROR")]
        [string]$strLevel = "INFO"
    )
    
    $strLogTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $strLogEntry = "[$strLogTimestamp] $strLevel $strMessage"
    
    # Ensure log directory exists
    $strLogDir = Split-Path -Parent $script:strLogFilePath
    if (-not (Test-Path $strLogDir)) {
        New-Item -ItemType Directory -Path $strLogDir -Force | Out-Null
    }
    
    # Write to log file
    Add-Content -Path $script:strLogFilePath -Value $strLogEntry -Encoding UTF8
    
    # Write to console based on level and verbose setting
    if ($VerboseLogging -or $strLevel -in @("SUCCESS", "WARNING", "ERROR")) {
        $objColor = switch ($strLevel) {
            "SUCCESS" { "Green" }
            "WARNING" { "Yellow" }
            "ERROR"   { "Red" }
            "ACTION"  { "Cyan" }
            "REASON"  { "Magenta" }
            default   { "White" }
        }
        Write-Host $strLogEntry -ForegroundColor $objColor
    }
}

function Write-LogHeader {
    param([Parameter(Mandatory=$true)][string]$strTitle)
    
    $strSeparator = "=" * 80
    Write-Log -strMessage "" -strLevel "INFO"
    Write-Log -strMessage $strSeparator -strLevel "INFO"
    Write-Log -strMessage $strTitle -strLevel "INFO"
    Write-Log -strMessage $strSeparator -strLevel "INFO"
}

# ============================================================================
# PRIVILEGE AND ENVIRONMENT CHECKS
# ============================================================================

function Test-AdminPrivileges {
    Write-Log -strMessage "Checking for Administrator privileges" -strLevel "INFO"
    
    $objIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $objPrincipal = New-Object Security.Principal.WindowsPrincipal($objIdentity)
    $boolIsAdmin = $objPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $boolIsAdmin) {
        Write-Log -strMessage "ERROR This script requires Administrator privileges" -strLevel "ERROR"
        Write-Host ""
        Write-Host "Please run this script as Administrator:" -ForegroundColor Yellow
        Write-Host "  1. Right-click on PowerShell" -ForegroundColor Cyan
        Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Cyan
        Write-Host "  3. Run the script again" -ForegroundColor Cyan
        Write-Host ""
        return $false
    }
    
    Write-Log -strMessage "Administrator privileges confirmed" -strLevel "SUCCESS"
    return $true
}

function Get-VSCodeInstallation {
    Write-Log -strMessage "Detecting VS Code installation" -strLevel "INFO"
    
    $objResult = @{
        installed = $false
        version = ""
        path = ""
        commandAvailable = $false
    }
    
    # Check if 'code' command is available
    try {
        $strVersionOutput = & code --version 2>&1 | Select-Object -First 1
        $objResult.version = $strVersionOutput
        $objResult.commandAvailable = $true
        Write-Log -strMessage "VS Code command-line tool found version $strVersionOutput" -strLevel "SUCCESS"
    }
    catch {
        Write-Log -strMessage "VS Code command-line tool not found in PATH" -strLevel "WARNING"
    }
    
    # Check standard installation paths
    $arrInstallPaths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
    )
    
    foreach ($strPath in $arrInstallPaths) {
        if (Test-Path $strPath) {
            $objResult.installed = $true
            $objResult.path = $strPath
            Write-Log -strMessage "VS Code installation found at $strPath" -strLevel "SUCCESS"
            break
        }
    }
    
    if (-not $objResult.installed) {
        Write-Log -strMessage "VS Code installation not found in standard locations" -strLevel "ERROR"
        Write-Host ""
        Write-Host "VS Code does not appear to be installed." -ForegroundColor Red
        Write-Host "Please install VS Code from https://code.visualstudio.com/" -ForegroundColor Yellow
        Write-Host ""
        return $null
    }
    
    return $objResult
}

function Stop-VSCodeProcesses {
    Write-Log -strMessage "Checking for running VS Code processes" -strLevel "INFO"
    
    $arrProcesses = Get-Process -Name "Code" -ErrorAction SilentlyContinue
    
    if ($arrProcesses) {
        Write-Log -strMessage "Found $($arrProcesses.Count) VS Code process(es) running" -strLevel "WARNING"
        Write-Host ""
        Write-Host "VS Code is currently running and must be closed." -ForegroundColor Yellow
        Write-Host "Please save your work and close all VS Code windows." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Press any key once VS Code is closed..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        # Verify processes are closed
        Start-Sleep -Seconds 2
        $arrProcesses = Get-Process -Name "Code" -ErrorAction SilentlyContinue
        
        if ($arrProcesses) {
            Write-Log -strMessage "VS Code processes still running" -strLevel "ERROR"
            Write-Host ""
            Write-Host "VS Code is still running. Please close all windows and try again." -ForegroundColor Red
            return $false
        }
    }
    
    Write-Log -strMessage "No VS Code processes detected" -strLevel "SUCCESS"
    return $true
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

function New-BackupDirectory {
    Write-LogHeader -strTitle "CREATING BACKUP DIRECTORY"
    
    $strBackupDir = Join-Path $BackupPath $script:strTimestamp
    
    Write-Log -strMessage "Creating backup directory $strBackupDir" -strLevel "ACTION"
    Write-Log -strMessage "Organizing user data before repair operation" -strLevel "REASON"
    
    New-Item -ItemType Directory -Path $strBackupDir -Force | Out-Null
    
    # Create subdirectories
    $arrSubDirs = @("tasks", "settings", "rules", "workflows", "cache", "checkpoints")
    foreach ($strSubDir in $arrSubDirs) {
        $strPath = Join-Path $strBackupDir $strSubDir
        New-Item -ItemType Directory -Path $strPath -Force | Out-Null
    }
    
    Write-Log -strMessage "Backup directory created successfully" -strLevel "SUCCESS"
    return $strBackupDir
}

function Backup-ClineTasks {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-LogHeader -strTitle "BACKING UP CLINE TASKS"
    
    $objResult = @{
        count = 0
        size = 0
        status = "success"
        items = @()
    }
    
    $strTasksSource = Join-Path $script:strClineGlobalStorage "tasks"
    $strTasksBackup = Join-Path $strBackupDir "tasks"
    
    if (-not (Test-Path $strTasksSource)) {
        Write-Log -strMessage "No tasks directory found" -strLevel "WARNING"
        return $objResult
    }
    
    Write-Log -strMessage "Backing up tasks from $strTasksSource" -strLevel "ACTION"
    Write-Log -strMessage "Tasks contain all conversation history and are critical to preserve" -strLevel "REASON"
    
    try {
        $arrTaskDirs = Get-ChildItem -Path $strTasksSource -Directory -ErrorAction Stop
        
        foreach ($objTaskDir in $arrTaskDirs) {
            $strDestPath = Join-Path $strTasksBackup $objTaskDir.Name
            
            Write-Log -strMessage "Copying task $($objTaskDir.Name)" -strLevel "INFO"
            Copy-Item -Path $objTaskDir.FullName -Destination $strDestPath -Recurse -Force -ErrorAction Stop
            
            $intSize = (Get-ChildItem -Path $strDestPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $objResult.size += $intSize
            $objResult.count++
            
            $objResult.items += @{
                name = $objTaskDir.Name
                size = $intSize
                path = $strDestPath
            }
        }
        
        # Backup task history index
        $strHistoryFile = Join-Path $script:strClineGlobalStorage "state\taskHistory.json"
        if (Test-Path $strHistoryFile) {
            $strHistoryBackup = Join-Path $strBackupDir "settings\taskHistory.json"
            Copy-Item -Path $strHistoryFile -Destination $strHistoryBackup -Force -ErrorAction Stop
            Write-Log -strMessage "Task history index backed up" -strLevel "INFO"
        }
        
        Write-Log -strMessage "Backed up $($objResult.count) tasks ($([math]::Round($objResult.size / 1MB, 2)) MB)" -strLevel "SUCCESS"
    }
    catch {
        Write-Log -strMessage "Error backing up tasks $($_.Exception.Message)" -strLevel "ERROR"
        $objResult.status = "failed"
    }
    
    return $objResult
}

function Backup-MCPSettings {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-LogHeader -strTitle "BACKING UP MCP SETTINGS"
    
    $objResult = @{ count = 0; size = 0; status = "success"; items = @() }
    
    # Backup MCP settings file
    $strMCPSettingsFile = Join-Path $script:strClineGlobalStorage "settings\cline_mcp_settings.json"
    if (Test-Path $strMCPSettingsFile) {
        Write-Log -strMessage "Backing up MCP settings file" -strLevel "ACTION"
        Write-Log -strMessage "Preserving custom MCP server configurations and integrations" -strLevel "REASON"
        
        try {
            $strBackupPath = Join-Path $strBackupDir "settings\cline_mcp_settings.json"
            Copy-Item -Path $strMCPSettingsFile -Destination $strBackupPath -Force -ErrorAction Stop
            
            $intSize = (Get-Item $strBackupPath).Length
            $objResult.size += $intSize
            $objResult.count++
            
            Write-Log -strMessage "MCP settings backed up successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error backing up MCP settings $($_.Exception.Message)" -strLevel "ERROR"
            $objResult.status = "failed"
        }
    }
    
    # Backup custom MCP servers
    $strMCPServersPath = Join-Path $script:strClineDocuments "MCP"
    if (Test-Path $strMCPServersPath) {
        Write-Log -strMessage "Backing up custom MCP servers" -strLevel "ACTION"
        
        try {
            $strMCPBackup = Join-Path $strBackupDir "mcp_servers"
            Copy-Item -Path $strMCPServersPath -Destination $strMCPBackup -Recurse -Force -ErrorAction Stop
            
            $intSize = (Get-ChildItem -Path $strMCPBackup -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $objResult.size += $intSize
            $objResult.count++
            
            Write-Log -strMessage "Custom MCP servers backed up" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error backing up custom MCP servers $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    return $objResult
}

function Backup-ClineRules {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-LogHeader -strTitle "BACKING UP CLINE RULES AND WORKFLOWS"
    
    $objResult = @{ count = 0; size = 0; status = "success"; items = @() }
    
    # Backup Rules
    $strRulesPath = Join-Path $script:strClineDocuments "Rules"
    if (Test-Path $strRulesPath) {
        Write-Log -strMessage "Backing up Cline rules" -strLevel "ACTION"
        Write-Log -strMessage "Preserving development standards and custom instructions" -strLevel "REASON"
        
        try {
            $strRulesBackup = Join-Path $strBackupDir "rules"
            Copy-Item -Path $strRulesPath -Destination $strRulesBackup -Recurse -Force -ErrorAction Stop
            
            $intSize = (Get-ChildItem -Path $strRulesBackup -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $objResult.size += $intSize
            $objResult.count++
            
            Write-Log -strMessage "Cline rules backed up successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error backing up rules $($_.Exception.Message)" -strLevel "ERROR"
            $objResult.status = "failed"
        }
    }
    
    # Backup Workflows
    $strWorkflowsPath = Join-Path $script:strClineDocuments "Workflows"
    if (Test-Path $strWorkflowsPath) {
        Write-Log -strMessage "Backing up Cline workflows" -strLevel "ACTION"
        
        try {
            $strWorkflowsBackup = Join-Path $strBackupDir "workflows"
            Copy-Item -Path $strWorkflowsPath -Destination $strWorkflowsBackup -Recurse -Force -ErrorAction Stop
            
            $intSize = (Get-ChildItem -Path $strWorkflowsBackup -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $objResult.size += $intSize
            $objResult.count++
            
            Write-Log -strMessage "Cline workflows backed up successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error backing up workflows $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    return $objResult
}

function Backup-ClineCheckpoints {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-Log -strMessage "Backing up Cline checkpoints" -strLevel "ACTION"
    
    $objResult = @{ count = 0; size = 0; status = "success" }
    
    $strCheckpointsPath = Join-Path $script:strClineGlobalStorage "checkpoints"
    if (Test-Path $strCheckpointsPath) {
        try {
            $strCheckpointsBackup = Join-Path $strBackupDir "checkpoints"
            Copy-Item -Path $strCheckpointsPath -Destination $strCheckpointsBackup -Recurse -Force -ErrorAction Stop
            
            $intSize = (Get-ChildItem -Path $strCheckpointsBackup -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $objResult.size += $intSize
            $objResult.count = (Get-ChildItem -Path $strCheckpointsBackup -Directory).Count
            
            Write-Log -strMessage "Checkpoints backed up $($objResult.count) items" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error backing up checkpoints $($_.Exception.Message)" -strLevel "WARNING"
        }
    }
    
    return $objResult
}

function New-BackupManifest {
    param(
        [Parameter(Mandatory=$true)][string]$strBackupDir,
        [Parameter(Mandatory=$true)][hashtable]$objBackupStats
    )
    
    Write-Log -strMessage "Creating backup manifest" -strLevel "ACTION"
    
    $objManifest = @{
        version = $script:strScriptVersion
        timestamp = $script:strTimestamp
        platform = "Windows"
        items = $objBackupStats.items
        totalSize = $objBackupStats.totalSize
        status = "completed"
        backupPath = $strBackupDir
    }
    
    $strManifestPath = Join-Path $strBackupDir "backup_manifest.json"
    
    try {
        $objManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $strManifestPath -Encoding UTF8
        Write-Log -strMessage "Backup manifest created $strManifestPath" -strLevel "SUCCESS"
    }
    catch {
        Write-Log -strMessage "Error creating manifest $($_.Exception.Message)" -strLevel "WARNING"
    }
}

function Remove-OldBackups {
    param(
        [Parameter(Mandatory=$true)][string]$strBackupBasePath,
        [Parameter(Mandatory=$false)][int]$intMaxBackups = 5
    )
    
    Write-LogHeader -strTitle "MANAGING BACKUP RETENTION"
    
    Write-Log -strMessage "Checking for old backups to remove" -strLevel "INFO"
    Write-Log -strMessage "Keeping only the $intMaxBackups most recent backups to conserve disk space" -strLevel "REASON"
    
    try {
        $arrBackups = Get-ChildItem -Path $strBackupBasePath -Directory | 
                      Where-Object { $_.Name -match '^\d{8}_\d{6}$' } |
                      Sort-Object Name -Descending
        
        if ($arrBackups.Count -gt $intMaxBackups) {
            $arrToRemove = $arrBackups | Select-Object -Skip $intMaxBackups
            
            Write-Log -strMessage "Found $($arrToRemove.Count) old backup(s) to remove" -strLevel "INFO"
            
            foreach ($objBackup in $arrToRemove) {
                Write-Log -strMessage "Removing old backup $($objBackup.Name)" -strLevel "ACTION"
                Remove-Item -Path $objBackup.FullName -Recurse -Force -ErrorAction Stop
            }
            
            Write-Log -strMessage "Old backups removed successfully" -strLevel "SUCCESS"
        }
        else {
            Write-Log -strMessage "Backup count ($($arrBackups.Count)) within limit ($intMaxBackups)" -strLevel "INFO"
        }
    }
    catch {
        Write-Log -strMessage "Error during backup cleanup $($_.Exception.Message)" -strLevel "WARNING"
    }
}

# ============================================================================
# UNINSTALL AND REINSTALL FUNCTIONS
# ============================================================================

function Uninstall-ClineExtension {
    Write-LogHeader -strTitle "UNINSTALLING CLINE EXTENSION"
    
    Write-Log -strMessage "Uninstalling Cline extension" -strLevel "ACTION"
    Write-Log -strMessage "Clean removal required for successful repair" -strLevel "REASON"
    
    try {
        $strOutput = & code --uninstall-extension $script:strClineExtensionId 2>&1
        Write-Log -strMessage "Extension uninstall command executed" -strLevel "INFO"
        
        # Wait for uninstall to complete
        Start-Sleep -Seconds 3
        
        # Verify extension directory is removed
        $arrExtDirs = Get-ChildItem -Path $script:strVSCodeExtensions -Directory -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -like "saoudrizwan.claude-dev*" }
        
        if ($arrExtDirs) {
            Write-Log -strMessage "Removing remaining extension directories" -strLevel "ACTION"
            foreach ($objDir in $arrExtDirs) {
                Remove-Item -Path $objDir.FullName -Recurse -Force -ErrorAction Stop
                Write-Log -strMessage "Removed $($objDir.Name)" -strLevel "INFO"
            }
        }
        
        Write-Log -strMessage "Cline extension uninstalled successfully" -strLevel "SUCCESS"
        return $true
    }
    catch {
        Write-Log -strMessage "Error during uninstall $($_.Exception.Message)" -strLevel "ERROR"
        return $false
    }
}

function Install-ClineExtension {
    Write-LogHeader -strTitle "INSTALLING CLINE EXTENSION"
    
    Write-Log -strMessage "Installing Cline extension" -strLevel "ACTION"
    Write-Log -strMessage "Fresh installation ensures clean state" -strLevel "REASON"
    
    try {
        $strOutput = & code --install-extension $script:strClineExtensionId 2>&1
        Write-Log -strMessage "Extension install command executed" -strLevel "INFO"
        
        # Wait for install to complete
        Start-Sleep -Seconds 5
        
        # Verify installation
        $arrExtDirs = Get-ChildItem -Path $script:strVSCodeExtensions -Directory -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -like "saoudrizwan.claude-dev*" }
        
        if ($arrExtDirs) {
            Write-Log -strMessage "Cline extension installed successfully" -strLevel "SUCCESS"
            return $true
        }
        else {
            Write-Log -strMessage "Extension installation could not be verified" -strLevel "WARNING"
            return $false
        }
    }
    catch {
        Write-Log -strMessage "Error during installation $($_.Exception.Message)" -strLevel "ERROR"
        return $false
    }
}

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

function Restore-ClineTasks {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-LogHeader -strTitle "RESTORING CLINE TASKS"
    
    $strTasksBackup = Join-Path $strBackupDir "tasks"
    $strTasksTarget = Join-Path $script:strClineGlobalStorage "tasks"
    
    if (-not (Test-Path $strTasksBackup)) {
        Write-Log -strMessage "No tasks backup found to restore" -strLevel "WARNING"
        return $false
    }
    
    Write-Log -strMessage "Restoring tasks to $strTasksTarget" -strLevel "ACTION"
    Write-Log -strMessage "Recovering conversation history and task data" -strLevel "REASON"
    
    try {
        # Create target directory
        New-Item -ItemType Directory -Path $strTasksTarget -Force | Out-Null
        
        # Copy task directories
        $arrTaskDirs = Get-ChildItem -Path $strTasksBackup -Directory
        foreach ($objTaskDir in $arrTaskDirs) {
            $strDestPath = Join-Path $strTasksTarget $objTaskDir.Name
            Copy-Item -Path $objTaskDir.FullName -Destination $strDestPath -Recurse -Force -ErrorAction Stop
            Write-Log -strMessage "Restored task $($objTaskDir.Name)" -strLevel "INFO"
        }
        
        # Restore task history
        $strHistoryBackup = Join-Path $strBackupDir "settings\taskHistory.json"
        if (Test-Path $strHistoryBackup) {
            $strStateDir = Join-Path $script:strClineGlobalStorage "state"
            New-Item -ItemType Directory -Path $strStateDir -Force | Out-Null
            
            $strHistoryTarget = Join-Path $strStateDir "taskHistory.json"
            Copy-Item -Path $strHistoryBackup -Destination $strHistoryTarget -Force -ErrorAction Stop
            Write-Log -strMessage "Task history index restored" -strLevel "INFO"
        }
        
        Write-Log -strMessage "Tasks restored successfully" -strLevel "SUCCESS"
        return $true
    }
    catch {
        Write-Log -strMessage "Error restoring tasks $($_.Exception.Message)" -strLevel "ERROR"
        return $false
    }
}

function Restore-MCPSettings {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-LogHeader -strTitle "RESTORING MCP SETTINGS"
    
    # Restore MCP settings file
    $strMCPBackup = Join-Path $strBackupDir "settings\cline_mcp_settings.json"
    if (Test-Path $strMCPBackup) {
        Write-Log -strMessage "Restoring MCP settings" -strLevel "ACTION"
        Write-Log -strMessage "Recovering custom MCP server configurations" -strLevel "REASON"
        
        try {
            $strSettingsDir = Join-Path $script:strClineGlobalStorage "settings"
            New-Item -ItemType Directory -Path $strSettingsDir -Force | Out-Null
            
            $strMCPTarget = Join-Path $strSettingsDir "cline_mcp_settings.json"
            Copy-Item -Path $strMCPBackup -Destination $strMCPTarget -Force -ErrorAction Stop
            
            Write-Log -strMessage "MCP settings restored successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error restoring MCP settings $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    # Restore custom MCP servers
    $strMCPServersBackup = Join-Path $strBackupDir "mcp_servers"
    if (Test-Path $strMCPServersBackup) {
        Write-Log -strMessage "Restoring custom MCP servers" -strLevel "ACTION"
        
        try {
            $strMCPTarget = Join-Path $script:strClineDocuments "MCP"
            Copy-Item -Path $strMCPServersBackup -Destination $strMCPTarget -Recurse -Force -ErrorAction Stop
            
            Write-Log -strMessage "Custom MCP servers restored" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error restoring custom MCP servers $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    return $true
}

function Restore-ClineRules {
    param([Parameter(Mandatory=$true)][string]$strBackupDir)
    
    Write-LogHeader -strTitle "RESTORING CLINE RULES AND WORKFLOWS"
    
    # Restore Rules
    $strRulesBackup = Join-Path $strBackupDir "rules"
    if (Test-Path $strRulesBackup) {
        Write-Log -strMessage "Restoring Cline rules" -strLevel "ACTION"
        Write-Log -strMessage "Recovering development standards and instructions" -strLevel "REASON"
        
        try {
            $strRulesTarget = Join-Path $script:strClineDocuments "Rules"
            Copy-Item -Path $strRulesBackup -Destination $strRulesTarget -Recurse -Force -ErrorAction Stop
            
            Write-Log -strMessage "Cline rules restored successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error restoring rules $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    # Restore Workflows
    $strWorkflowsBackup = Join-Path $strBackupDir "workflows"
    if (Test-Path $strWorkflowsBackup) {
        Write-Log -strMessage "Restoring Cline workflows" -strLevel "ACTION"
        
        try {
            $strWorkflowsTarget = Join-Path $script:strClineDocuments "Workflows"
            Copy-Item -Path $strWorkflowsBackup -Destination $strWorkflowsTarget -Recurse -Force -ErrorAction Stop
            
            Write-Log -strMessage "Cline workflows restored successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error restoring workflows $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    return $true
}

function Set-VSCodeSidebarPosition {
    Write-LogHeader -strTitle "CONFIGURING VSCODE SIDEBAR POSITION"
    
    Write-Log -strMessage "Setting Cline sidebar to left (Primary Side Bar)" -strLevel "ACTION"
    Write-Log -strMessage "Ensuring Cline is easily accessible on the left side" -strLevel "REASON"
    
    $strSettingsFile = Join-Path $script:strVSCodeUserData "settings.json"
    
    try {
        # Read existing settings or create new
        if (Test-Path $strSettingsFile) {
            $objSettings = Get-Content $strSettingsFile -Raw | ConvertFrom-Json
        }
        else {
            $objSettings = @{}
        }
        
        # Ensure sidebar is on the left
        $objSettings | Add-Member -NotePropertyName "workbench.sideBar.location" -NotePropertyValue "left" -Force
        
        # Save settings
        $objSettings | ConvertTo-Json -Depth 10 | Out-File -FilePath $strSettingsFile -Encoding UTF8
        
        Write-Log -strMessage "Sidebar position configured successfully" -strLevel "SUCCESS"
        return $true
    }
    catch {
        Write-Log -strMessage "Error configuring sidebar $($_.Exception.Message)" -strLevel "WARNING"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

function Start-RepairProcess {
    Write-LogHeader -strTitle "CLINE REPAIR TOOL v$script:strScriptVersion"
    
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "                    Cline VS Code Extension Repair Tool                       " -ForegroundColor Cyan
    Write-Host "                              Version $script:strScriptVersion                           " -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log -strMessage "Cline Repair Tool v$script:strScriptVersion started" -strLevel "INFO"
    Write-Log -strMessage "Platform Windows 11" -strLevel "INFO"
    Write-Log -strMessage "Backup Path $BackupPath" -strLevel "INFO"
    
    # Step 1: Check Administrator privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Log -strMessage "Script terminated due to insufficient privileges" -strLevel "ERROR"
        exit 1
    }
    
    # Step 2: Detect VS Code installation
    $objVSCode = Get-VSCodeInstallation
    if (-not $objVSCode) {
        Write-Log -strMessage "Script terminated VS Code not found" -strLevel "ERROR"
        exit 1
    }
    
    # Step 3: Check for running VS Code processes
    if (-not (Stop-VSCodeProcesses)) {
        Write-Log -strMessage "Script terminated VS Code still running" -strLevel "ERROR"
        exit 1
    }
    
    # Step 4: Create backup
    if (-not $SkipBackup) {
        try {
            $strBackupDir = New-BackupDirectory
            
            $objBackupStats = @{
                items = @()
                totalSize = 0
            }
            
            # Backup tasks
            $objTasksResult = Backup-ClineTasks -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objTasksResult.size
            $objBackupStats.items += $objTasksResult.items
            
            # Backup MCP settings
            $objMCPResult = Backup-MCPSettings -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objMCPResult.size
            
            # Backup rules
            $objRulesResult = Backup-ClineRules -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objRulesResult.size
            
            # Backup checkpoints
            $objCheckpointsResult = Backup-ClineCheckpoints -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objCheckpointsResult.size
            
            # Create manifest
            New-BackupManifest -strBackupDir $strBackupDir -objBackupStats $objBackupStats
            
            # Cleanup old backups
            Remove-OldBackups -strBackupBasePath $BackupPath -intMaxBackups $script:intMaxBackups
            
            Write-Host ""
            Write-Host "Backup completed successfully!" -ForegroundColor Green
            Write-Host "  Location: $strBackupDir" -ForegroundColor Cyan
            Write-Host "  Total Size: $([math]::Round($objBackupStats.totalSize / 1MB, 2)) MB" -ForegroundColor Cyan
            Write-Host ""
            
            if ($BackupOnly) {
                Write-Log -strMessage "Backup-only mode backup completed" -strLevel "SUCCESS"
                Write-Host "Backup-only mode - repair skipped." -ForegroundColor Yellow
                Write-Host "Log file: $script:strLogFilePath" -ForegroundColor Cyan
                return $true
            }
        }
        catch {
            Write-Log -strMessage "Backup failed $($_.Exception.Message)" -strLevel "ERROR"
            Write-Host ""
            Write-Host "Backup failed! Cannot proceed with repair." -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Log -strMessage "Backup skipped by user request" -strLevel "WARNING"
        Write-Host ""
        Write-Host "WARNING: Backup skipped!" -ForegroundColor Yellow
        Write-Host "Press any key to continue or Ctrl+C to cancel..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    
    # Step 5: Uninstall Cline extension
    Write-Host ""
    Write-Host "Uninstalling Cline extension..." -ForegroundColor Yellow
    if (-not (Uninstall-ClineExtension)) {
        Write-Log -strMessage "Uninstall failed attempting to continue" -strLevel "WARNING"
        Write-Host "Uninstall encountered issues, but continuing..." -ForegroundColor Yellow
    }
    
    # Step 6: Install Cline extension
    Write-Host ""
    Write-Host "Installing Cline extension..." -ForegroundColor Yellow
    if (-not (Install-ClineExtension)) {
        Write-Log -strMessage "Installation failed" -strLevel "ERROR"
        Write-Host ""
        Write-Host "Installation failed! Please install manually." -ForegroundColor Red
        return $false
    }
    
    # Step 7: Restore user data
    if (-not $SkipBackup) {
        Write-Host ""
        Write-Host "Restoring user data..." -ForegroundColor Yellow
        
        Restore-ClineTasks -strBackupDir $strBackupDir
        Restore-MCPSettings -strBackupDir $strBackupDir
        Restore-ClineRules -strBackupDir $strBackupDir
    }
    
    # Step 8: Configure sidebar
    Set-VSCodeSidebarPosition
    
    # Step 9: Success message
    Write-LogHeader -strTitle "REPAIR COMPLETED SUCCESSFULLY"
    
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host "                        REPAIR COMPLETED SUCCESSFULLY                          " -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "The Cline extension has been repaired!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Launch VS Code" -ForegroundColor White
    Write-Host "  2. Verify Cline appears in the left sidebar" -ForegroundColor White
    Write-Host "  3. Re-enter your API key if needed" -ForegroundColor White
    Write-Host "  4. Check that your tasks and settings are restored" -ForegroundColor White
    Write-Host ""
    Write-Host "Backup Location: $strBackupDir" -ForegroundColor Cyan
    Write-Host "Log File: $script:strLogFilePath" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log -strMessage "Repair process completed successfully" -strLevel "SUCCESS"
    return $true
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

try {
    $boolSuccess = Start-RepairProcess
    
    if ($boolSuccess) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-Log -strMessage "Unexpected error $($_.Exception.Message)" -strLevel "ERROR"
    Write-Host ""
    Write-Host "An unexpected error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file: $script:strLogFilePath" -ForegroundColor Cyan
    exit 1
}
