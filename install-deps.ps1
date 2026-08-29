# Installs the language toolchains needed to run run-all.ps1 (or run-all.sh
# from Git Bash) on Windows. Uses winget. Already-installed tools are skipped.
#
#   .\install-deps.ps1              # every language
#   .\install-deps.ps1 node python  # a subset
#
# Some packages (the Visual Studio C++ tools especially) prompt for elevation.
# Open a new terminal after this finishes if a later command is still not found.
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Languages
)

$ErrorActionPreference = "Stop"

$ValidLanguages = @("dotnet", "node", "python", "go", "ruby", "java", "cpp", "rust")

if (-not $Languages -or $Languages.Count -eq 0) {
    $Languages = $ValidLanguages
}

foreach ($language in $Languages) {
    if ($ValidLanguages -notcontains $language) {
        Write-Host "unknown language: $language" -ForegroundColor Red
        exit 2
    }
}

function Test-Cmd {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
    $cargo = Join-Path $env:USERPROFILE ".cargo\bin"
    if ((Test-Path $cargo) -and ($env:Path -notlike "*$cargo*")) {
        $env:Path = "$env:Path;$cargo"
    }
}

function Test-Msvc {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        return $false
    }
    $installation = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return -not [string]::IsNullOrWhiteSpace($installation)
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$ExtraArgs = @()
    )

    Write-Host "Installing $Name ($Id)..."
    $wingetArgs = @(
        "install", "--id", $Id, "-e", "--disable-interactivity",
        "--accept-package-agreements", "--accept-source-agreements"
    ) + $ExtraArgs
    & winget @wingetArgs
    $code = $LASTEXITCODE
    # 0 = installed, -1978335189 = already installed
    if ($code -eq 0 -or $code -eq -1978335189) {
        Update-SessionPath
        return $true
    }
    Write-Host "  winget exited $code for $Name"
    return $false
}

if (-not (Test-Cmd "winget")) {
    Write-Host "winget is not on PATH. Install 'App Installer' from the Microsoft Store, then re-run this script." -ForegroundColor Red
    exit 1
}

$Failed = New-Object System.Collections.Generic.List[string]
$NeedsGit = $false
$NeedsMsvc = $false

foreach ($language in $Languages) {
    if ($language -in @("go", "cpp")) { $NeedsGit = $true }
    if ($language -in @("cpp", "rust")) { $NeedsMsvc = $true }
}

if ($NeedsGit -and -not (Test-Cmd "git")) {
    if (-not (Install-WingetPackage -Id "Git.Git" -Name "Git")) {
        $Failed.Add("git") | Out-Null
    }
}

if ($Languages -contains "dotnet" -and -not (Test-Cmd "dotnet")) {
    if (-not (Install-WingetPackage -Id "Microsoft.DotNet.SDK.10" -Name ".NET SDK 10")) {
        $Failed.Add("dotnet") | Out-Null
    }
}

if ($Languages -contains "node" -and -not (Test-Cmd "node")) {
    if (-not (Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -Name "Node.js LTS")) {
        $Failed.Add("node") | Out-Null
    }
}

if ($Languages -contains "python" -and -not (Test-Cmd "python") -and -not (Test-Cmd "python3") -and -not (Test-Cmd "py")) {
    if (-not (Install-WingetPackage -Id "Python.Python.3.13" -Name "Python 3.13")) {
        $Failed.Add("python") | Out-Null
    }
}

if ($Languages -contains "go" -and -not (Test-Cmd "go")) {
    if (-not (Install-WingetPackage -Id "GoLang.Go" -Name "Go")) {
        $Failed.Add("go") | Out-Null
    }
}

if ($Languages -contains "ruby" -and -not (Test-Cmd "ruby")) {
    if (-not (Install-WingetPackage -Id "RubyInstallerTeam.RubyWithDevKit.3.3" -Name "Ruby 3.3 with DevKit")) {
        $Failed.Add("ruby") | Out-Null
    }
}

if ($Languages -contains "ruby" -and (Test-Cmd "gem") -and -not (Test-Cmd "bundle")) {
    Write-Host "Installing bundler..."
    gem install bundler --no-document
    if ($LASTEXITCODE -ne 0) {
        $Failed.Add("bundler") | Out-Null
    }
}

if ($Languages -contains "java") {
    if (-not (Test-Cmd "java")) {
        if (-not (Install-WingetPackage -Id "EclipseAdoptium.Temurin.17.JDK" -Name "Temurin JDK 17")) {
            $Failed.Add("java") | Out-Null
        }
    }
    if (-not (Test-Cmd "mvn")) {
        if (-not (Install-WingetPackage -Id "Apache.Maven" -Name "Apache Maven")) {
            $Failed.Add("maven") | Out-Null
        }
    }
}

if ($Languages -contains "cpp" -and -not (Test-Cmd "cmake")) {
    if (-not (Install-WingetPackage -Id "Kitware.CMake" -Name "CMake")) {
        $Failed.Add("cmake") | Out-Null
    }
}

if ($NeedsMsvc -and -not (Test-Msvc)) {
    $vsOverride = "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    if (-not (Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Name "VS 2022 Build Tools (C++)" -ExtraArgs @("--override", $vsOverride))) {
        $Failed.Add("msvc") | Out-Null
    }
}

if ($Languages -contains "rust") {
    if (-not (Test-Cmd "rustup") -and -not (Test-Cmd "cargo")) {
        if (-not (Install-WingetPackage -Id "Rustlang.Rustup" -Name "Rustup")) {
            $Failed.Add("rust") | Out-Null
        }
    }
    Update-SessionPath
    if (Test-Cmd "rustup") {
        Write-Host "Selecting the stable Rust toolchain..."
        rustup default stable
        if ($LASTEXITCODE -ne 0) {
            $Failed.Add("rust-toolchain") | Out-Null
        }
    }
}

Update-SessionPath

Write-Host ""
Write-Host "── Toolchain check ─────────────────────────────"
function Write-Check {
    param([string]$Label, [bool]$Ok)
    if ($Ok) {
        Write-Host "  [ok]  $Label" -ForegroundColor Green
    } else {
        Write-Host "  [miss] $Label" -ForegroundColor Yellow
    }
}

if ($Languages -contains "dotnet") { Write-Check "dotnet" (Test-Cmd "dotnet") }
if ($Languages -contains "node")   { Write-Check "node" (Test-Cmd "node") }
if ($Languages -contains "python") { Write-Check "python" ((Test-Cmd "python") -or (Test-Cmd "python3") -or (Test-Cmd "py")) }
if ($Languages -contains "go")     { Write-Check "go" (Test-Cmd "go") }
if ($Languages -contains "ruby")   { Write-Check "ruby" (Test-Cmd "ruby") }
if ($Languages -contains "java")   {
    Write-Check "java" (Test-Cmd "java")
    Write-Check "mvn" (Test-Cmd "mvn")
}
if ($Languages -contains "cpp")    {
    Write-Check "cmake" (Test-Cmd "cmake")
    Write-Check "msvc" (Test-Msvc)
}
if ($Languages -contains "rust")   { Write-Check "cargo" (Test-Cmd "cargo") }
if ($NeedsGit)                     { Write-Check "git" (Test-Cmd "git") }

Write-Host ""
if ($Failed.Count -gt 0) {
    Write-Host "Failed to install: $($Failed -join ', ')" -ForegroundColor Red
    Write-Host "Fix those, open a new terminal, and re-run .\install-deps.ps1"
    exit 1
}

Write-Host "Toolchains are ready. Run .\run-all.ps1 (new terminal if a command is still missing)."
exit 0
