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

function Get-MavenBin {
    $tools = Join-Path $env:LOCALAPPDATA "Kryptic\tools"
    if (-not (Test-Path $tools)) {
        return $null
    }
    $dir = Get-ChildItem $tools -Directory -Filter "apache-maven-*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\mvn.cmd") } |
        Select-Object -First 1
    if ($dir) {
        return (Join-Path $dir.FullName "bin")
    }
    return $null
}

function Add-UserPath {
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path $Dir)) {
        return
    }
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $user) {
        $user = ""
    }
    $parts = $user -split ";" | Where-Object { $_ }
    if ($parts -contains $Dir) {
        return
    }
    $joined = (@($parts) + $Dir) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $joined, "User")
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
    $cargo = Join-Path $env:USERPROFILE ".cargo\bin"
    if ((Test-Path $cargo) -and ($env:Path -notlike "*$cargo*")) {
        $env:Path = "$env:Path;$cargo"
    }
    $mavenBin = Get-MavenBin
    if ($mavenBin -and ($env:Path -notlike "*$mavenBin*")) {
        $env:Path = "$env:Path;$mavenBin"
    }
}

function Get-MsvcComponentId {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        return "Microsoft.VisualStudio.Component.VC.Tools.ARM64"
    }
    return "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
}

function Get-VsWhere {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) { return $vswhere }
    return $null
}

function Get-VsInstallPath {
    $vswhere = Get-VsWhere
    if (-not $vswhere) { return $null }
    $installation = & $vswhere -latest -products * -property installationPath 2>$null
    if ([string]::IsNullOrWhiteSpace($installation)) { return $null }
    return $installation.ToString().Trim()
}

function Test-Msvc {
    $vswhere = Get-VsWhere
    if (-not $vswhere) { return $false }
    $installation = & $vswhere -latest -products * `
        -requires (Get-MsvcComponentId) `
        -property installationPath 2>$null
    return -not [string]::IsNullOrWhiteSpace($installation)
}

# winget will not add workloads to an existing VS install (it reports
# "already installed" and exits). Use the Visual Studio installer instead.
function Install-Msvc {
    $component = Get-MsvcComponentId
    $installPath = Get-VsInstallPath
    $setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"

    if ($installPath -and (Test-Path $setup)) {
        Write-Host "Adding $component to Visual Studio at $installPath..."
        Write-Host "  this needs elevation and can take several minutes."
        $setupArgs = @(
            "modify",
            "--installPath", $installPath,
            "--add", "Microsoft.VisualStudio.Workload.VCTools",
            "--add", $component,
            "--includeRecommended",
            "--passive", "--wait", "--norestart"
        )
        $proc = Start-Process -FilePath $setup -ArgumentList $setupArgs -Wait -PassThru -Verb RunAs
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne $null) {
            Write-Host "  VS installer exited $($proc.ExitCode)"
        }
        return (Test-Msvc)
    }

    $vsOverride = "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add $component"
    if (-not (Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Name "VS 2022 Build Tools (C++)" -ExtraArgs @("--override", $vsOverride))) {
        return $false
    }
    return (Test-Msvc)
}

function Test-RealPython {
    foreach ($name in @("python3", "python")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and ($cmd.Source -notlike "*\WindowsApps\*") -and (Test-Path $cmd.Source)) {
            return $true
        }
    }
    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    )
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $exe = Get-ChildItem $root -Directory -Filter "Python3*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "python.exe" } |
            Where-Object { $_ -and (Test-Path $_) -and ($_ -notlike "*\WindowsApps\*") } |
            Select-Object -First 1
        if ($exe) { return $true }
    }
    return $false
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

# winget has no Apache Maven package (it ships as a zip of scripts, not an
# installer). Download the official binary zip and put mvn on the user PATH.
function Install-MavenZip {
    $version = "3.9.9"
    $name = "apache-maven-$version"
    $url = "https://archive.apache.org/dist/maven/maven-3/$version/binaries/$name-bin.zip"
    $tools = Join-Path $env:LOCALAPPDATA "Kryptic\tools"
    $dest = Join-Path $tools $name
    $bin = Join-Path $dest "bin"
    $zip = Join-Path $env:TEMP "$name-bin.zip"

    if (Test-Path (Join-Path $bin "mvn.cmd")) {
        Write-Host "Maven $version already unpacked at $dest"
        Add-UserPath $bin
        Update-SessionPath
        return $true
    }

    Write-Host "Installing Apache Maven $version from apache.org..."
    try {
        New-Item -ItemType Directory -Force -Path $tools | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        if (Test-Path $dest) {
            Remove-Item $dest -Recurse -Force
        }
        Expand-Archive -Path $zip -DestinationPath $tools -Force
    } catch {
        Write-Host "  Maven download failed: $($_.Exception.Message)"
        return $false
    } finally {
        if (Test-Path $zip) {
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path (Join-Path $bin "mvn.cmd"))) {
        Write-Host "  Maven zip did not contain bin\mvn.cmd"
        return $false
    }

    Add-UserPath $bin
    Update-SessionPath
    return $true
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

if ($Languages -contains "python" -and -not (Test-RealPython)) {
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

if ($Languages -contains "ruby" -and (Test-Cmd "gem")) {
    $needsBundler = -not (Test-Cmd "bundle")
    if (-not $needsBundler) {
        $bundleVer = & bundle -v 2>$null
        if ("$bundleVer" -match 'Bundler version 1\.') {
            $needsBundler = $true
        }
    }
    if ($needsBundler) {
        Write-Host "Installing bundler 2.x..."
        gem install bundler --no-document
        if ($LASTEXITCODE -ne 0) {
            $Failed.Add("bundler") | Out-Null
        }
    }
}

if ($Languages -contains "java") {
    if (-not (Test-Cmd "java")) {
        if (-not (Install-WingetPackage -Id "EclipseAdoptium.Temurin.17.JDK" -Name "Temurin JDK 17")) {
            $Failed.Add("java") | Out-Null
        }
    }
    if (-not (Test-Cmd "mvn")) {
        if (-not (Install-MavenZip)) {
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
    if (-not (Install-Msvc)) {
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
Write-Host "-- Toolchain check -----------------------------"
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
if ($Languages -contains "python") { Write-Check "python" (Test-RealPython) }
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
