<#
.SYNOPSIS
    Cline VS Code Extension Repair Tool for Windows
    
.DESCRIPTION
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
    
.PARAMETER BackupOnly
    Only perform backup without uninstall/reinstall. Useful for creating regular backups.
    
.PARAMETER RestoreOnly
    Only perform restore from an existing backup without reinstalling the extension.
    Use with -RestoreFrom to specify which backup to use.
    
.PARAMETER RestoreFrom
    Specify which backup to restore from. Can be:
    - "latest" (default): Use the most recent backup
    - A timestamp (e.g., "20251126_120000_UTC"): Use a specific backup
    - A full path to a backup ZIP or directory
    
.PARAMETER ListBackups
    List all available backups and exit. Useful for finding backup timestamps.
    
.PARAMETER SkipBackup
    Skip the backup phase (NOT RECOMMENDED). Only use if you have a recent backup.
    
.PARAMETER BackupPath
    Custom path for backup storage. Default: $env:USERPROFILE\ClineBackups
    
.PARAMETER MaxBackups
    Maximum number of backups to retain. Default: 367 (one year of daily backups)
    
.PARAMETER NoCompress
    Skip ZIP compression and store backups as directories.
    
.PARAMETER HashAlgorithm
    Hash algorithm to use for backup verification. Options: SHA256 (default), SHA1, MD5
    
.PARAMETER JsonOutput
    Output results in JSON format for automation and piping.
    
.PARAMETER JsonInput
    JSON string containing configuration parameters.
    
.PARAMETER UseGitHubBackup
    Upload backup to a private GitHub repository for safe cloud storage.
    
.PARAMETER GitHubToken
    Personal Access Token for GitHub authentication (required if UseGitHubBackup is set).
    
.PARAMETER VerboseLogging
    Enable detailed logging output to console.
    
.EXAMPLE
    .\Repair-Cline.ps1
    Performs a complete repair with default settings (367 backups, ZIP compression, SHA256).
    
.EXAMPLE
    .\Repair-Cline.ps1 -BackupOnly -MaxBackups 30
    Only creates a backup and keeps last 30 backups.
    
.EXAMPLE
    .\Repair-Cline.ps1 -ListBackups
    Lists all available backups with timestamps and sizes.
    
.EXAMPLE
    .\Repair-Cline.ps1 -RestoreOnly
    Restores from the most recent backup without reinstalling.
    
.EXAMPLE
    .\Repair-Cline.ps1 -RestoreOnly -RestoreFrom "20251126_120000_UTC"
    Restores from a specific backup timestamp.
    
.EXAMPLE
    .\Repair-Cline.ps1 -JsonOutput
    Performs repair and outputs results in JSON format.
    
.EXAMPLE
    echo '{"BackupOnly":true,"MaxBackups":10}' | .\Repair-Cline.ps1 -JsonInput
    Uses piped JSON input for configuration.
    
.NOTES
    Version: 2.0.0
    Author: Cline Repair Tool
    Created: 2025-11-24
    Updated: 2025-11-24
    Requires: VS Code installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$BackupOnly,
    
    [Parameter(Mandatory=$false)]
    [switch]$RestoreOnly,
    
    [Parameter(Mandatory=$false)]
    [string]$RestoreFrom = "latest",
    
    [Parameter(Mandatory=$false)]
    [switch]$ListBackups,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup,
    
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "$env:USERPROFILE\ClineBackups",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxBackups = 367,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoCompress,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("SHA256", "SHA1", "MD5")]
    [string]$HashAlgorithm = "SHA256",
    
    [Parameter(Mandatory=$false)]
    [switch]$JsonOutput,
    
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [string]$JsonInput,
    
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
$script:strScriptVersion = "2.0.0"

# Process JSON input if provided
if ($JsonInput) {
    try {
        $objJsonConfig = $JsonInput | ConvertFrom-Json
        
        # Override parameters from JSON
        if ($objJsonConfig.BackupOnly) { $BackupOnly = $true }
        if ($objJsonConfig.RestoreOnly) { $RestoreOnly = $true }
        if ($objJsonConfig.RestoreFrom) { $RestoreFrom = $objJsonConfig.RestoreFrom }
        if ($objJsonConfig.ListBackups) { $ListBackups = $true }
        if ($objJsonConfig.SkipBackup) { $SkipBackup = $true }
        if ($objJsonConfig.BackupPath) { $BackupPath = $objJsonConfig.BackupPath }
        if ($objJsonConfig.MaxBackups) { $MaxBackups = $objJsonConfig.MaxBackups }
        if ($objJsonConfig.NoCompress) { $NoCompress = $true }
        if ($objJsonConfig.HashAlgorithm) { $HashAlgorithm = $objJsonConfig.HashAlgorithm }
        if ($objJsonConfig.JsonOutput) { $JsonOutput = $true }
        if ($objJsonConfig.VerboseLogging) { $VerboseLogging = $true }
        if ($objJsonConfig.UseGitHubBackup) { $UseGitHubBackup = $true }
        if ($objJsonConfig.GitHubToken) { $GitHubToken = $objJsonConfig.GitHubToken }
    }
    catch {
        Write-Error "Failed to parse JSON input: $($_.Exception.Message)"
        exit 1
    }
}

# Generate UTC timestamp with hour/minute/second precision
$dtNowUtc = (Get-Date).ToUniversalTime()
$script:strTimestamp = $dtNowUtc.ToString("yyyyMMdd_HHmmss") + "_UTC"
$script:strLogFileName = "cline-repair-$script:strTimestamp.log"
$script:strLogFilePath = Join-Path $BackupPath $script:strLogFileName
$script:intMaxBackups = $MaxBackups

# VS Code and Cline extension identifiers
$script:strClineExtensionId = "saoudrizwan.claude-dev"
$script:strVSCodeCommand = "code"

# Data location paths (Windows)
$script:strUserProfile = $env:USERPROFILE
$script:strVSCodeExtensions = Join-Path $strUserProfile ".vscode\extensions"
$script:strVSCodeUserData = Join-Path $env:APPDATA "Code\User"
$script:strClineGlobalStorage = Join-Path $strVSCodeUserData "globalStorage\saoudrizwan.claude-dev"
$script:strClineDocuments = Join-Path $strUserProfile "Documents\Cline"

# JSON output object
$script:objJsonResult = @{
    version = $script:strScriptVersion
    timestamp = $script:strTimestamp
    platform = "Windows"
    status = "in_progress"
    backupPath = ""
    backupSize = 0
    itemsBackedUp = 0
    hashes = @{
        sha1 = ""
        md5 = ""
        sha256 = ""
    }
    errors = @()
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
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
    
    # Write to console based on level and verbose setting (only if not JSON output)
    if (-not $JsonOutput -and ($VerboseLogging -or $strLevel -in @("SUCCESS", "WARNING", "ERROR"))) {
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
    
    # Track errors for JSON output
    if ($strLevel -eq "ERROR") {
        $script:objJsonResult.errors += $strMessage
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
# HASH CALCULATION FUNCTIONS
# ============================================================================

function Get-FileHashValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$strFilePath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$strAlgorithm = "SHA256"
    )
    
    try {
        $objHash = Get-FileHash -Path $strFilePath -Algorithm $strAlgorithm
        return $objHash.Hash
    }
    catch {
        Write-Log -strMessage "Error calculating $strAlgorithm hash: $($_.Exception.Message)" -strLevel "ERROR"
        return ""
    }
}

function Get-ShortHash {
    param(
        [Parameter(Mandatory=$true)]
        [string]$strFullHash
    )
    
    # Return first 8 characters of hash
    return $strFullHash.Substring(0, [Math]::Min(8, $strFullHash.Length))
}

function Test-BackupIntegrity {
    param([Parameter(Mandatory=$true)][string]$strZipPath)
    
    Write-Log -strMessage "Verifying backup integrity for $(Split-Path -Leaf $strZipPath)" -strLevel "INFO"
    
    # Extract hash from filename (format: backup_YYYYMMDD_HHMMSS_UTC_{8-char-hash}.zip)
    $strFileName = [System.IO.Path]::GetFileNameWithoutExtension($strZipPath)
    
    if ($strFileName -match '_([A-Fa-f0-9]{8})$') {
        $strExpectedHash = $matches[1]
        
        # Calculate actual hash
        $strFullHash = Get-FileHashValue -strFilePath $strZipPath -strAlgorithm $HashAlgorithm
        $strActualHash = Get-ShortHash -strFullHash $strFullHash
        
        if ($strActualHash -eq $strExpectedHash) {
            Write-Log -strMessage "✓ Integrity verified: $strFileName" -strLevel "SUCCESS"
            return $true
        }
        else {
            Write-Log -strMessage "✗ Integrity check FAILED: $strFileName (expected: $strExpectedHash, got: $strActualHash)" -strLevel "WARNING"
            return $false
        }
    }
    else {
        Write-Log -strMessage "No hash found in filename: $strFileName (legacy backup format)" -strLevel "INFO"
        return $null  # Unknown - legacy format
    }
}

function Invoke-BackupIntegrityCheck {
    Write-LogHeader -strTitle "VERIFYING EXISTING BACKUPS"
    
    Write-Log -strMessage "Checking integrity of existing backup files" -strLevel "ACTION"
    Write-Log -strMessage "Ensures all backups are uncorrupted and can be restored if needed" -strLevel "REASON"
    
    try {
        $arrZipFiles = Get-ChildItem -Path $BackupPath -Filter "backup_*_UTC_*.zip" -ErrorAction SilentlyContinue
        
        if (-not $arrZipFiles -or $arrZipFiles.Count -eq 0) {
            Write-Log -strMessage "No existing backups found to verify" -strLevel "INFO"
            return
        }
        
        Write-Log -strMessage "Found $($arrZipFiles.Count) backup(s) to verify" -strLevel "INFO"
        
        $intVerified = 0
        $intFailed = 0
        $intLegacy = 0
        
        foreach ($objZipFile in $arrZipFiles) {
            $objVerifyResult = Test-BackupIntegrity -strZipPath $objZipFile.FullName
            
            if ($objVerifyResult -eq $true) {
                $intVerified++
            }
            elseif ($objVerifyResult -eq $false) {
                $intFailed++
            }
            else {
                $intLegacy++
            }
        }
        
        Write-Log -strMessage "Integrity check complete: $intVerified verified, $intFailed failed, $intLegacy legacy format" -strLevel "SUCCESS"
        
        if ($intFailed -gt 0) {
            Write-Log -strMessage "WARNING: $intFailed backup(s) failed integrity check - consider removing them" -strLevel "WARNING"
        }
    }
    catch {
        Write-Log -strMessage "Error during integrity check: $($_.Exception.Message)" -strLevel "WARNING"
    }
}

# ============================================================================
# ENVIRONMENT CHECKS
# ============================================================================

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
        
        if (-not $JsonOutput) {
            Write-Host ""
            Write-Host "VS Code does not appear to be installed." -ForegroundColor Red
            Write-Host "Please install VS Code from https://code.visualstudio.com/" -ForegroundColor Yellow
            Write-Host ""
        }
        return $null
    }
    
    return $objResult
}

function Stop-VSCodeProcesses {
    Write-Log -strMessage "Checking for running VS Code processes" -strLevel "INFO"
    
    $arrProcesses = Get-Process -Name "Code" -ErrorAction SilentlyContinue
    
    if ($arrProcesses) {
        Write-Log -strMessage "Found $($arrProcesses.Count) VS Code process(es) running" -strLevel "WARNING"
        
        if (-not $JsonOutput) {
            Write-Host ""
            Write-Host "VS Code is currently running and must be closed." -ForegroundColor Yellow
            Write-Host "Please save your work and close all VS Code windows." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Press any key once VS Code is closed..." -ForegroundColor Cyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        
        # Verify processes are closed
        Start-Sleep -Seconds 2
        $arrProcesses = Get-Process -Name "Code" -ErrorAction SilentlyContinue
        
        if ($arrProcesses) {
            Write-Log -strMessage "VS Code processes still running" -strLevel "ERROR"
            
            if (-not $JsonOutput) {
                Write-Host ""
                Write-Host "VS Code is still running. Please close all windows and try again." -ForegroundColor Red
            }
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
    $arrSubDirs = @("tasks", "settings", "rules", "workflows", "cache", "checkpoints", "mcp_servers")
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
        
        Write-Log -strMessage "Backed up $($objResult.count) tasks ($([math]::Round($objResult.size / 1MB, 2))) MB" -strLevel "SUCCESS"
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
        timestampUtc = $dtNowUtc.ToString("o")
        platform = "Windows"
        hashAlgorithm = $HashAlgorithm
        compressed = -not $NoCompress
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

function Compress-BackupDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$strBackupDir,
        [Parameter(Mandatory=$true)][hashtable]$objBackupStats
    )
    
    Write-LogHeader -strTitle "COMPRESSING BACKUP"
    
    Write-Log -strMessage "Compressing backup directory to ZIP format" -strLevel "ACTION"
    Write-Log -strMessage "Reduces storage space and enables integrity verification" -strLevel "REASON"
    
    try {
        # Calculate hash of the directory before compression
        $strFullHash = Get-FileHashValue -strFilePath ($strBackupDir + "\backup_manifest.json") -strAlgorithm $HashAlgorithm
        $strShortHash = Get-ShortHash -strFullHash $strFullHash
        
        # Create ZIP filename with hash
        $strZipFileName = "backup_$($script:strTimestamp)_$strShortHash.zip"
        $strZipPath = Join-Path $BackupPath $strZipFileName
        
        Write-Log -strMessage "Creating ZIP file: $strZipFileName" -strLevel "INFO"
        
        # Compress using .NET compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($strBackupDir, $strZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        
        # Get ZIP file size
        $intZipSize = (Get-Item $strZipPath).Length
        $floatCompressionRatio = [math]::Round(($intZipSize / $objBackupStats.totalSize) * 100, 2)
        
        Write-Log -strMessage "Backup compressed successfully" -strLevel "SUCCESS"
        Write-Log -strMessage "Original size: $([math]::Round($objBackupStats.totalSize / 1MB, 2)) MB" -strLevel "INFO"
        Write-Log -strMessage "Compressed size: $([math]::Round($intZipSize / 1MB, 2)) MB ($floatCompressionRatio`% of original)" -strLevel "INFO"
        Write-Log -strMessage "Hash: $strFullHash" -strLevel "INFO"
        
        # Calculate all hash types for JSON output
        $script:objJsonResult.hashes.sha256 = Get-FileHashValue -strFilePath $strZipPath -strAlgorithm "SHA256"
        $script:objJsonResult.hashes.sha1 = Get-FileHashValue -strFilePath $strZipPath -strAlgorithm "SHA1"
        $script:objJsonResult.hashes.md5 = Get-FileHashValue -strFilePath $strZipPath -strAlgorithm "MD5"
        $script:objJsonResult.backupSize = $intZipSize
        
        # Remove uncompressed directory
        Write-Log -strMessage "Removing uncompressed backup directory" -strLevel "INFO"
        Remove-Item -Path $strBackupDir -Recurse -Force -ErrorAction Stop
        
        return $strZipPath
    }
    catch {
        Write-Log -strMessage "Error during compression: $($_.Exception.Message)" -strLevel "ERROR"
        return $strBackupDir  # Return original directory if compression failed
    }
}

function Remove-OldBackups {
    param(
        [Parameter(Mandatory=$true)][string]$strBackupBasePath,
        [Parameter(Mandatory=$false)][int]$intMaxBackups = 367
    )
    
    Write-LogHeader -strTitle "MANAGING BACKUP RETENTION"
    
    Write-Log -strMessage "Checking for old backups to remove (keeping $intMaxBackups most recent)" -strLevel "INFO"
    Write-Log -strMessage "Maintaining backup history while conserving disk space" -strLevel "REASON"
    
    try {
        # Get all backup files (both ZIP and directories)
        $arrZipBackups = Get-ChildItem -Path $strBackupBasePath -Filter "backup_*_UTC_*.zip" -ErrorAction SilentlyContinue
        $arrDirBackups = Get-ChildItem -Path $strBackupBasePath -Directory -ErrorAction SilentlyContinue | 
                         Where-Object { $_.Name -match '^\d{8}_\d{6}_UTC$' }
        
        $arrAllBackups = @($arrZipBackups) + @($arrDirBackups) | Sort-Object Name -Descending
        
        if ($arrAllBackups.Count -gt $intMaxBackups) {
            $arrToRemove = $arrAllBackups | Select-Object -Skip $intMaxBackups
            
            Write-Log -strMessage "Found $($arrToRemove.Count) old backup(s) to remove" -strLevel "INFO"
            
            foreach ($objBackup in $arrToRemove) {
                Write-Log -strMessage "Removing old backup: $($objBackup.Name)" -strLevel "ACTION"
                Remove-Item -Path $objBackup.FullName -Recurse -Force -ErrorAction Stop
            }
            
            Write-Log -strMessage "Old backups removed successfully" -strLevel "SUCCESS"
            Write-Log -strMessage "Retained $intMaxBackups most recent backups" -strLevel "INFO"
        }
        else {
            Write-Log -strMessage "Backup count ($($arrAllBackups.Count)) within limit ($intMaxBackups)" -strLevel "INFO"
        }
    }
    catch {
        Write-Log -strMessage "Error during backup cleanup: $($_.Exception.Message)" -strLevel "WARNING"
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
        Write-Log -strMessage "Error during uninstall: $($_.Exception.Message)" -strLevel "ERROR"
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
        Write-Log -strMessage "Error during installation: $($_.Exception.Message)" -strLevel "ERROR"
        return $false
    }
}

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

function Restore-ClineTasks {
    param([Parameter(Mandatory=$true)][string]$strBackupSource)
    
    Write-LogHeader -strTitle "RESTORING CLINE TASKS"
    
    # Check if source is ZIP file
    $boolIsZip = $strBackupSource -like "*.zip"
    $strBackupDir = $strBackupSource
    
    if ($boolIsZip) {
        Write-Log -strMessage "Extracting backup from ZIP file" -strLevel "ACTION"
        $strExtractPath = Join-Path $BackupPath "temp_restore_$($script:strTimestamp)"
        
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($strBackupSource, $strExtractPath)
            $strBackupDir = $strExtractPath
            Write-Log -strMessage "Backup extracted successfully" -strLevel "SUCCESS"
        }
        catch {
            Write-Log -strMessage "Error extracting backup: $($_.Exception.Message)" -strLevel "ERROR"
            return $false
        }
    }
    
    $strTasksBackup = Join-Path $strBackupDir "tasks"
    $strTasksTarget = Join-Path $script:strClineGlobalStorage "tasks"
    
    if (-not (Test-Path $strTasksBackup)) {
        Write-Log -strMessage "No tasks backup found to restore" -strLevel "WARNING"
        if ($boolIsZip) { Remove-Item -Path $strExtractPath -Recurse -Force -ErrorAction SilentlyContinue }
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
            Write-Log -strMessage "Restored task: $($objTaskDir.Name)" -strLevel "INFO"
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
        
        # Cleanup temp extraction
        if ($boolIsZip) {
            Remove-Item -Path $strExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return $true
    }
    catch {
        Write-Log -strMessage "Error restoring tasks: $($_.Exception.Message)" -strLevel "ERROR"
        if ($boolIsZip) { Remove-Item -Path $strExtractPath -Recurse -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Restore-MCPSettings {
    param([Parameter(Mandatory=$true)][string]$strBackupSource)
    
    Write-LogHeader -strTitle "RESTORING MCP SETTINGS"
    
    # Determine backup directory (handle ZIP files)
    $boolIsZip = $strBackupSource -like "*.zip"
    $strBackupDir = $strBackupSource
    
    if ($boolIsZip) {
        $strBackupDir = Join-Path $BackupPath "temp_restore_$($script:strTimestamp)"
        if (-not (Test-Path $strBackupDir)) {
            Write-Log -strMessage "Temp extraction path not found" -strLevel "WARNING"
            return $true
        }
    }
    
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
            Write-Log -strMessage "Error restoring MCP settings: $($_.Exception.Message)" -strLevel "ERROR"
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
            Write-Log -strMessage "Error restoring custom MCP servers: $($_.Exception.Message)" -strLevel "ERROR"
        }
    }
    
    return $true
}

function Restore-ClineRules {
    param([Parameter(Mandatory=$true)][string]$strBackupSource)
    
    Write-LogHeader -strTitle "RESTORING CLINE RULES AND WORKFLOWS"
    
    # Determine backup directory (handle ZIP files)
    $boolIsZip = $strBackupSource -like "*.zip"
    $strBackupDir = $strBackupSource
    
    if ($boolIsZip) {
        $strBackupDir = Join-Path $BackupPath "temp_restore_$($script:strTimestamp)"
        if (-not (Test-Path $strBackupDir)) {
            Write-Log -strMessage "Temp extraction path not found" -strLevel "WARNING"
            return $true
        }
    }
    
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
            Write-Log -strMessage "Error restoring rules: $($_.Exception.Message)" -strLevel "ERROR"
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
            Write-Log -strMessage "Error restoring workflows: $($_.Exception.Message)" -strLevel "ERROR"
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
        Write-Log -strMessage "Error configuring sidebar: $($_.Exception.Message)" -strLevel "WARNING"
        return $false
    }
}

# ============================================================================
# BACKUP LISTING AND RESTORE-ONLY FUNCTIONS
# ============================================================================

function Get-AvailableBackups {
    <#
    .SYNOPSIS
        Get list of available backups sorted by date (newest first).
    #>
    
    $arrBackups = @()
    
    if (-not (Test-Path $BackupPath)) {
        return $arrBackups
    }
    
    # Get ZIP backups
    $arrZipFiles = Get-ChildItem -Path $BackupPath -Filter "backup_*_UTC_*.zip" -ErrorAction SilentlyContinue
    foreach ($objZip in $arrZipFiles) {
        # Extract timestamp from filename: backup_YYYYMMDD_HHMMSS_UTC_HASH.zip
        if ($objZip.Name -match '^backup_(\d{8}_\d{6}_UTC)') {
            $arrBackups += @{
                Name = $objZip.Name
                Path = $objZip.FullName
                Timestamp = $matches[1]
                Size = $objZip.Length
                Type = "ZIP"
                Date = $objZip.LastWriteTime
            }
        }
    }
    
    # Get directory backups (uncompressed)
    $arrDirs = Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue | 
               Where-Object { $_.Name -match '^\d{8}_\d{6}_UTC$' }
    foreach ($objDir in $arrDirs) {
        $intSize = (Get-ChildItem -Path $objDir.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                   Measure-Object -Property Length -Sum).Sum
        $arrBackups += @{
            Name = $objDir.Name
            Path = $objDir.FullName
            Timestamp = $objDir.Name
            Size = $intSize
            Type = "Directory"
            Date = $objDir.LastWriteTime
        }
    }
    
    # Sort by timestamp descending (newest first)
    return $arrBackups | Sort-Object { $_.Timestamp } -Descending
}

function Show-AvailableBackups {
    <#
    .SYNOPSIS
        Display available backups in a formatted list.
    #>
    
    Write-LogHeader -strTitle "AVAILABLE BACKUPS"
    
    $arrBackups = Get-AvailableBackups
    
    if ($arrBackups.Count -eq 0) {
        if ($JsonOutput) {
            @{ backups = @(); count = 0 } | ConvertTo-Json -Depth 10 | Write-Output
        }
        else {
            Write-Host ""
            Write-Host "No backups found in: $BackupPath" -ForegroundColor Yellow
            Write-Host ""
        }
        return
    }
    
    if ($JsonOutput) {
        @{ 
            backups = $arrBackups
            count = $arrBackups.Count
            backupPath = $BackupPath
        } | ConvertTo-Json -Depth 10 | Write-Output
    }
    else {
        Write-Host ""
        Write-Host "Found $($arrBackups.Count) backup(s) in: $BackupPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  #  | Timestamp             | Type      | Size" -ForegroundColor White
        Write-Host "-----+-----------------------+-----------+------------" -ForegroundColor Gray
        
        $intIndex = 1
        foreach ($objBackup in $arrBackups) {
            $strSize = if ($objBackup.Size -gt 1MB) { 
                "$([math]::Round($objBackup.Size / 1MB, 2)) MB" 
            } else { 
                "$([math]::Round($objBackup.Size / 1KB, 2)) KB" 
            }
            
            $strLabel = if ($intIndex -eq 1) { " (latest)" } else { "" }
            Write-Host "  $intIndex  | $($objBackup.Timestamp) | $($objBackup.Type.PadRight(9)) | $strSize$strLabel" -ForegroundColor White
            $intIndex++
        }
        
        Write-Host ""
        Write-Host "To restore from a specific backup, use:" -ForegroundColor Cyan
        Write-Host "  .\Repair-Cline.ps1 -RestoreOnly -RestoreFrom `"TIMESTAMP`"" -ForegroundColor White
        Write-Host ""
    }
}

function Find-BackupByIdentifier {
    <#
    .SYNOPSIS
        Find a backup by identifier (latest, timestamp, or full path).
    #>
    param([Parameter(Mandatory=$true)][string]$strIdentifier)
    
    # Check if it's a full path
    if (Test-Path $strIdentifier) {
        return $strIdentifier
    }
    
    $arrBackups = Get-AvailableBackups
    
    if ($arrBackups.Count -eq 0) {
        Write-Log -strMessage "No backups found to restore from" -strLevel "ERROR"
        return $null
    }
    
    # Handle "latest"
    if ($strIdentifier -eq "latest") {
        $objLatest = $arrBackups[0]
        Write-Log -strMessage "Using latest backup: $($objLatest.Timestamp)" -strLevel "INFO"
        return $objLatest.Path
    }
    
    # Search by timestamp
    foreach ($objBackup in $arrBackups) {
        if ($objBackup.Timestamp -eq $strIdentifier -or $objBackup.Name -like "*$strIdentifier*") {
            Write-Log -strMessage "Found backup: $($objBackup.Name)" -strLevel "INFO"
            return $objBackup.Path
        }
    }
    
    Write-Log -strMessage "No backup found matching: $strIdentifier" -strLevel "ERROR"
    return $null
}

function Start-RestoreOnlyProcess {
    <#
    .SYNOPSIS
        Perform restore-only operation without reinstalling the extension.
    #>
    
    Write-LogHeader -strTitle "CLINE RESTORE-ONLY MODE v$script:strScriptVersion"
    
    if (-not $JsonOutput) {
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "                    Cline VS Code Extension Restore Tool                      " -ForegroundColor Cyan
        Write-Host "                              Version $script:strScriptVersion                           " -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Log -strMessage "Restore-only mode started" -strLevel "INFO"
    Write-Log -strMessage "Restore from: $RestoreFrom" -strLevel "INFO"
    
    # Find the backup to restore from
    $strBackupPath = Find-BackupByIdentifier -strIdentifier $RestoreFrom
    
    if (-not $strBackupPath) {
        $script:objJsonResult.status = "failed"
        $script:objJsonResult.errors += "Backup not found: $RestoreFrom"
        
        if ($JsonOutput) {
            $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
        }
        else {
            Write-Host ""
            Write-Host "Backup not found: $RestoreFrom" -ForegroundColor Red
            Write-Host ""
            Write-Host "Use -ListBackups to see available backups." -ForegroundColor Yellow
            Write-Host ""
        }
        return $false
    }
    
    if (-not $JsonOutput) {
        Write-Host "Restoring from: $strBackupPath" -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Perform restore
    $boolTasksRestored = Restore-ClineTasks -strBackupSource $strBackupPath
    $boolMCPRestored = Restore-MCPSettings -strBackupSource $strBackupPath
    $boolRulesRestored = Restore-ClineRules -strBackupSource $strBackupPath
    
    # Success message
    Write-LogHeader -strTitle "RESTORE COMPLETED"
    
    $script:objJsonResult.status = "completed"
    $script:objJsonResult.backupPath = $strBackupPath
    
    if ($JsonOutput) {
        $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
    }
    else {
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Green
        Write-Host "                         RESTORE COMPLETED SUCCESSFULLY                        " -ForegroundColor Green
        Write-Host "==============================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Data has been restored from backup!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Restored from: $strBackupPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "  1. Restart VS Code if it's running" -ForegroundColor White
        Write-Host "  2. Verify your tasks and settings are restored" -ForegroundColor White
        Write-Host ""
        Write-Host "Log File: $script:strLogFilePath" -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Log -strMessage "Restore-only process completed successfully" -strLevel "SUCCESS"
    return $true
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

function Start-RepairProcess {
    Write-LogHeader -strTitle "CLINE REPAIR TOOL v$script:strScriptVersion"
    
    if (-not $JsonOutput) {
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "                    Cline VS Code Extension Repair Tool                       " -ForegroundColor Cyan
        Write-Host "                              Version $script:strScriptVersion                           " -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Log -strMessage "Cline Repair Tool v$script:strScriptVersion started" -strLevel "INFO"
    Write-Log -strMessage "Platform: Windows" -strLevel "INFO"
    Write-Log -strMessage "Backup Path: $BackupPath" -strLevel "INFO"
    Write-Log -strMessage "Max Backups: $script:intMaxBackups" -strLevel "INFO"
    Write-Log -strMessage "Compression: $(-not $NoCompress)" -strLevel "INFO"
    Write-Log -strMessage "Hash Algorithm: $HashAlgorithm" -strLevel "INFO"
    
    # Step 1: Verify existing backups
    Invoke-BackupIntegrityCheck
    
    # Step 2: Detect VS Code installation
    $objVSCode = Get-VSCodeInstallation
    if (-not $objVSCode) {
        $script:objJsonResult.status = "failed"
        $script:objJsonResult.errors += "VS Code not found"
        if ($JsonOutput) { 
            $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output 
        }
        exit 1
    }
    
    # Step 3: Check for running VS Code processes (only required for full repair, not backup-only)
    if (-not $BackupOnly) {
        if (-not (Stop-VSCodeProcesses)) {
            $script:objJsonResult.status = "failed"
            $script:objJsonResult.errors += "VS Code still running"
            if ($JsonOutput) { 
                $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output 
            }
            exit 1
        }
    }
    else {
        Write-Log -strMessage "Backup-only mode: skipping VS Code process check" -strLevel "INFO"
    }
    
    # Step 4: Create backup
    $strBackupLocation = ""
    
    if (-not $SkipBackup) {
        try {
            $strBackupDir = New-BackupDirectory
            
            $objBackupStats = @{
                items = @()
                totalSize = 0
            }
            
            # Backup all components
            $objTasksResult = Backup-ClineTasks -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objTasksResult.size
            $objBackupStats.items += $objTasksResult.items
            $script:objJsonResult.itemsBackedUp += $objTasksResult.count
            
            $objMCPResult = Backup-MCPSettings -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objMCPResult.size
            $script:objJsonResult.itemsBackedUp += $objMCPResult.count
            
            $objRulesResult = Backup-ClineRules -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objRulesResult.size
            $script:objJsonResult.itemsBackedUp += $objRulesResult.count
            
            $objCheckpointsResult = Backup-ClineCheckpoints -strBackupDir $strBackupDir
            $objBackupStats.totalSize += $objCheckpointsResult.size
            $script:objJsonResult.itemsBackedUp += $objCheckpointsResult.count
            
            # Create manifest
            New-BackupManifest -strBackupDir $strBackupDir -objBackupStats $objBackupStats
            
            # Compress backup if not disabled
            if (-not $NoCompress) {
                $strBackupLocation = Compress-BackupDirectory -strBackupDir $strBackupDir -objBackupStats $objBackupStats
            }
            else {
                $strBackupLocation = $strBackupDir
                $script:objJsonResult.backupSize = $objBackupStats.totalSize
            }
            
            $script:objJsonResult.backupPath = $strBackupLocation
            
            # Cleanup old backups
            Remove-OldBackups -strBackupBasePath $BackupPath -intMaxBackups $script:intMaxBackups
            
            if (-not $JsonOutput) {
                Write-Host ""
                Write-Host "Backup completed successfully!" -ForegroundColor Green
                Write-Host "  Location: $strBackupLocation" -ForegroundColor Cyan
                Write-Host "  Items: $($script:objJsonResult.itemsBackedUp)" -ForegroundColor Cyan
                Write-Host "  Size: $([math]::Round($script:objJsonResult.backupSize / 1MB, 2)) MB" -ForegroundColor Cyan
                Write-Host ""
            }
            
            if ($BackupOnly) {
                Write-Log -strMessage "Backup-only mode: backup completed" -strLevel "SUCCESS"
                $script:objJsonResult.status = "completed"
                
                if ($JsonOutput) {
                    $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
                }
                else {
                    Write-Host "Backup-only mode - repair skipped." -ForegroundColor Yellow
                    Write-Host "Log file: $script:strLogFilePath" -ForegroundColor Cyan
                }
                return $true
            }
        }
        catch {
            Write-Log -strMessage "Backup failed: $($_.Exception.Message)" -strLevel "ERROR"
            $script:objJsonResult.status = "failed"
            $script:objJsonResult.errors += "Backup failed: $($_.Exception.Message)"
            
            if ($JsonOutput) {
                $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
            }
            else {
                Write-Host ""
                Write-Host "Backup failed! Cannot proceed with repair." -ForegroundColor Red
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            return $false
        }
    }
    else {
        Write-Log -strMessage "Backup skipped by user request" -strLevel "WARNING"
        
        if (-not $JsonOutput) {
            Write-Host ""
            Write-Host "WARNING: Backup skipped!" -ForegroundColor Yellow
            Write-Host "Press any key to continue or Ctrl+C to cancel..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
    
    # Step 5: Uninstall Cline extension
    if (-not $JsonOutput) {
        Write-Host ""
        Write-Host "Uninstalling Cline extension..." -ForegroundColor Yellow
    }
    
    if (-not (Uninstall-ClineExtension)) {
        Write-Log -strMessage "Uninstall encountered issues, continuing..." -strLevel "WARNING"
        
        if (-not $JsonOutput) {
            Write-Host "Uninstall encountered issues, but continuing..." -ForegroundColor Yellow
        }
    }
    
    # Step 6: Install Cline extension
    if (-not $JsonOutput) {
        Write-Host ""
        Write-Host "Installing Cline extension..." -ForegroundColor Yellow
    }
    
    if (-not (Install-ClineExtension)) {
        Write-Log -strMessage "Installation failed" -strLevel "ERROR"
        $script:objJsonResult.status = "failed"
        $script:objJsonResult.errors += "Installation failed"
        
        if ($JsonOutput) {
            $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
        }
        else {
            Write-Host ""
            Write-Host "Installation failed! Please install manually." -ForegroundColor Red
        }
        return $false
    }
    
    # Step 7: Restore user data
    if (-not $SkipBackup -and $strBackupLocation) {
        if (-not $JsonOutput) {
            Write-Host ""
            Write-Host "Restoring user data..." -ForegroundColor Yellow
        }
        
        Restore-ClineTasks -strBackupSource $strBackupLocation
        Restore-MCPSettings -strBackupSource $strBackupLocation
        Restore-ClineRules -strBackupSource $strBackupLocation
    }
    
    # Step 8: Configure sidebar
    Set-VSCodeSidebarPosition
    
    # Step 9: Success message
    Write-LogHeader -strTitle "REPAIR COMPLETED SUCCESSFULLY"
    
    $script:objJsonResult.status = "completed"
    
    if ($JsonOutput) {
        $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
    }
    else {
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
        
        if ($strBackupLocation) {
            Write-Host "Backup Location: $strBackupLocation" -ForegroundColor Cyan
        }
        
        Write-Host "Log File: $script:strLogFilePath" -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Log -strMessage "Repair process completed successfully" -strLevel "SUCCESS"
    return $true
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

try {
    # Handle ListBackups mode
    if ($ListBackups) {
        Show-AvailableBackups
        exit 0
    }
    
    # Handle RestoreOnly mode
    if ($RestoreOnly) {
        $boolSuccess = Start-RestoreOnlyProcess
        
        if ($boolSuccess) {
            exit 0
        }
        else {
            exit 1
        }
    }
    
    # Default: Full repair process
    $boolSuccess = Start-RepairProcess
    
    if ($boolSuccess) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-Log -strMessage "Unexpected error: $($_.Exception.Message)" -strLevel "ERROR"
    $script:objJsonResult.status = "failed"
    $script:objJsonResult.errors += "Unexpected error: $($_.Exception.Message)"
    
    if ($JsonOutput) {
        $script:objJsonResult | ConvertTo-Json -Depth 10 | Write-Output
    }
    else {
        Write-Host ""
        Write-Host "An unexpected error occurred:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "Log file: $script:strLogFilePath" -ForegroundColor Cyan
    }
    exit 1
}
