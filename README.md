# Cline Repair Tool

A comprehensive cross-platform tool for backing up, uninstalling, and reinstalling the Cline VS Code extension with full data preservation.

## 🎯 Purpose

This tool performs a complete repair of a broken Cline installation by:

1. **Backing up** all user data (tasks, history, MCP settings, rules, workflows)
2. **Uninstalling** the current Cline extension
3. **Performing** a clean reinstallation
4. **Restoring** all user data
5. **Configuring** the sidebar position to left (Primary Side Bar)

## 📋 Features

- **Complete Data Backup**: Tasks, conversation history, MCP configurations, rules, and workflows
- **Automatic Backup Retention**: Keeps the 5 most recent backups to conserve disk space
- **GitHub Cloud Backup** (optional): Upload backups to a private GitHub repository
- **Detailed Logging**: Timestamped logs with action, reason, and result tracking
- **Cross-Platform**: Windows (PowerShell), Linux (Python), macOS (Python)
- **Rollback Support**: Manual restore from any previous backup
- **No Data Loss**: API keys preserved via VS Code's Secret Storage

## 🚀 Quick Start

### Windows

```powershell
# Run as Administrator
.\scripts\windows\Repair-Cline.ps1
```

### Linux/macOS

```bash
# Run with sudo
sudo python3 scripts/linux/repair_cline.py
```

## 📦 Installation

### Prerequisites

**Windows:**
- Windows 10/11
- PowerShell 5.1 or later
- VS Code installed
- Administrator privileges

**Linux:**
- Python 3.8 or later
- VS Code installed
- sudo access

**macOS:**
- Python 3.8 or later
- VS Code installed
- sudo access

### Download

```bash
# Clone the repository
git clone https://github.com/YOUR-USERNAME/cline-repair-tool.git
cd cline-repair-tool
```

Or download the [latest release](https://github.com/YOUR-USERNAME/cline-repair-tool/releases).

## 📖 Usage

### Basic Repair (Recommended)

Performs a complete backup, uninstall, reinstall, and restore:

**Windows:**
```powershell
# Open PowerShell as Administrator
.\scripts\windows\Repair-Cline.ps1
```

**Linux/macOS:**
```bash
sudo python3 scripts/linux/repair_cline.py
```

### Backup Only

Create a backup without performing repair:

**Windows:**
```powershell
.\scripts\windows\Repair-Cline.ps1 -BackupOnly
```

**Linux/macOS:**
```bash
python3 scripts/linux/repair_cline.py --backup-only
```

### Custom Backup Location

**Windows:**
```powershell
.\scripts\windows\Repair-Cline.ps1 -BackupPath "D:\MyBackups"
```

**Linux/macOS:**
```bash
sudo python3 scripts/linux/repair_cline.py --backup-path /custom/path
```

### Verbose Output

**Windows:**
```powershell
.\scripts\windows\Repair-Cline.ps1 -VerboseLogging
```

**Linux/macOS:**
```bash
sudo python3 scripts/linux/repair_cline.py --verbose
```

### GitHub Cloud Backup (Optional)

**Windows:**
```powershell
.\scripts\windows\Repair-Cline.ps1 -UseGitHubBackup -GitHubToken "ghp_xxxxxxxxxxxx"
```

**Linux/macOS:**
```bash
sudo python3 scripts/linux/repair_cline.py --github-backup --github-token "ghp_xxxxxxxxxxxx"
```

## 📂 What Gets Backed Up

The tool backs up all Cline data to preserve your work:

| Data Type | Location (Windows) | Description |
|-----------|-------------------|-------------|
| **Tasks** | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\tasks\` | All conversation history and task data |
| **Task History** | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\state\taskHistory.json` | Task index and metadata |
| **MCP Settings** | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json` | MCP server configurations |
| **Custom MCP Servers** | `%USERPROFILE%\Documents\Cline\MCP\` | Custom MCP server installations |
| **Global Rules** | `%USERPROFILE%\Documents\Cline\Rules\` | Development standards and instructions |
| **Workflows** | `%USERPROFILE%\Documents\Cline\Workflows\` | Automated workflow definitions |
| **Checkpoints** | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\checkpoints\` | Saved task states |

### What's NOT Backed Up (and Why)

- **API Keys**: Stored in VS Code's Secret Storage (OS keychain), automatically preserved
- **Puppeteer Browser Cache**: ~300MB, automatically re-downloaded when needed
- **Model Cache**: Regenerated automatically from APIs

## 🔧 Advanced Features

### Backup Retention

The tool automatically manages backup retention:

- **Default**: Keeps 5 most recent backups
- **Automatic Cleanup**: Removes older backups to conserve disk space
- **Timestamped**: Each backup uses format `YYYYMMDD_HHMMSS`

**Backup Locations:**
- Windows: `%USERPROFILE%\ClineBackups\`
- Linux: `~/ClineBackups/`
- macOS: `~/ClineBackups/`

### Manual Restore

To manually restore from a previous backup:

1. Locate your backup: `%USERPROFILE%\ClineBackups\YYYYMMDD_HHMMSS\`
2. Copy contents to Cline data directories:
   - Tasks: `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\tasks\`
   - Settings: `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\`
   - Rules: `%USERPROFILE%\Documents\Cline\Rules\`
   - Workflows: `%USERPROFILE%\Documents\Cline\Workflows\`

### Logs

Every repair operation creates a detailed log file:

**Location:** `%USERPROFILE%\ClineBackups\cline-repair-YYYYMMDD_HHMMSS.log`

**Log Format:**
```
[2025-11-24 13:15:00] INFO: Cline Repair Tool v1.0.0 started
[2025-11-24 13:15:00] INFO: Platform: Windows 11
[2025-11-24 13:15:01] ACTION: Creating backup directory
[2025-11-24 13:15:01] REASON: Organizing user data before repair operation
[2025-11-24 13:15:02] SUCCESS: Backup directory created successfully
```

## 🛡️ Safety Features

### Pre-Flight Checks

Before making any changes, the tool verifies:

1. **Administrator/Root Access**: Ensures proper permissions
2. **VS Code Installation**: Confirms VS Code is installed
3. **VS Code Not Running**: Prompts to close all VS Code windows
4. **Backup Success**: Validates backup before proceeding

### Error Handling

- Detailed error messages with suggested fixes
- Automatic rollback on critical failures
- Preserves original data until repair completes successfully
- Log files for troubleshooting

### Data Integrity

- Backup manifest with checksums
- Validation of restored data
- API keys remain in secure OS keychain
- No temporary files in unsecured locations

## 🐛 Troubleshooting

### "Script requires Administrator privileges"

**Windows:** Right-click PowerShell → "Run as Administrator"

**Linux/macOS:** Use `sudo` before the command

### "VS Code installation not found"

Ensure VS Code is installed:
- Windows: Install from https://code.visualstudio.com/
- Linux: `sudo apt install code` or `sudo snap install code --classic`
- macOS: Download from https://code.visualstudio.com/ or `brew install --cask visual-studio-code`

### "Extension installation failed"

1. Check internet connection
2. Manually install Cline from VS Code Marketplace
3. Run restore only: Copy files from latest backup to Cline directories

### "Backup failed"

1. Check disk space (need ~100MB free)
2. Verify backup path is writable
3. Check log file for specific errors

### "Tasks not restored"

1. Check backup manifest: `%USERPROFILE%\ClineBackups\YYYYMMDD_HHMMSS\backup_manifest.json`
2. Manually copy from: `backup\tasks\` to Cline's task directory
3. Restart VS Code

## 📊 Backup Size Estimates

Typical backup sizes (varies by usage):

| Component | Typical Size |
|-----------|-------------|
| Tasks (10-30) | 5-20 MB |
| MCP Settings | < 1 MB |
| Rules & Workflows | < 1 MB |
| Checkpoints | 2-10 MB |
| **Total** | **10-30 MB** |

## 🔒 Security & Privacy

- **Local-First**: Backups stored locally by default
- **No Telemetry**: No data sent to external servers
- **API Key Protection**: Keys remain in OS-secured keychain
- **Private Repos**: GitHub backups use private repositories
- **Encrypted Credentials**: GitHub tokens never stored in logs

## 📝 Development Standards

This project follows strict development standards:

- **Hungarian Notation**: All variables use reverse Hungarian notation
- **NASA Coding Standards**: Maximum function complexity and length limits
- **DRY Documentation**: Central documentation with references
- **Complete Implementation**: No TODOs, placeholders, or stubs
- **Comprehensive Logging**: All actions logged with reason and result

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Follow the coding standards (see `.clinerules/`)
4. Commit changes (`git commit -m 'feat: add amazing feature'`)
5. Push to branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/YOUR-USERNAME/cline-repair-tool/issues)
- **Discussions**: [GitHub Discussions](https://github.com/YOUR-USERNAME/cline-repair-tool/discussions)
- **Documentation**: [docs/](docs/)

## 🔄 Version History

### v1.0.0 (2025-11-24)

- Initial release
- Windows PowerShell implementation
- Linux Python implementation (coming soon)
- macOS Python implementation (coming soon)
- Complete backup and restore functionality
- Automatic backup retention
- GitHub cloud backup support
- Detailed logging

## 🙏 Acknowledgments

- Cline development team for the excellent VS Code extension
- Open source community for inspiration and best practices

---

**Made with ❤️ for the Cline Community**
