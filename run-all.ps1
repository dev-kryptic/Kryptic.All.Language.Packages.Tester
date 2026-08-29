# Runs the Kryptic package verification app for every supported language
# against the running daemon, and reports a per-language pass/fail table.
#
#   .\run-all.ps1              # all languages
#   .\run-all.ps1 node python  # a subset
#
# Prerequisites: the daemon is running and signed in (`kryptic status`), and
# kryptic.json in each directory points at a project you can read.
# On a fresh Windows machine, run .\install-deps.ps1 first.
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Languages
)

$ErrorActionPreference = "Continue"

# A parent PowerShell opened before install-deps (or used to launch this
# file with powershell -File) still has the old PATH. Reload from the
# registry so winget-installed tools are visible in this process.
function Update-SessionEnvironment {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
    $cargo = Join-Path $env:USERPROFILE ".cargo\bin"
    if ((Test-Path $cargo) -and ($env:Path -notlike "*$cargo*")) {
        $env:Path = "$env:Path;$cargo"
    }
    $mavenTools = Join-Path $env:LOCALAPPDATA "Kryptic\tools"
    if (Test-Path $mavenTools) {
        $mavenDir = Get-ChildItem $mavenTools -Directory -Filter "apache-maven-*" -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName "bin\mvn.cmd") } |
            Select-Object -First 1
        if ($mavenDir) {
            $mavenBin = Join-Path $mavenDir.FullName "bin"
            if ($env:Path -notlike "*$mavenBin*") {
                $env:Path = "$env:Path;$mavenBin"
            }
        }
    }

    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if (-not $javaHome) {
        $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    }
    if (-not $javaHome -or -not (Test-Path (Join-Path $javaHome "bin\java.exe"))) {
        $jdkRoots = @(
            (Join-Path $env:ProgramFiles "Eclipse Adoptium"),
            (Join-Path $env:ProgramFiles "Microsoft"),
            (Join-Path $env:ProgramFiles "Java"),
            (Join-Path $env:ProgramFiles "Android\openjdk")
        )
        foreach ($root in $jdkRoots) {
            if (-not (Test-Path $root)) { continue }
            $jdk = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } |
                Select-Object -First 1
            if ($jdk) {
                $javaHome = $jdk.FullName
                break
            }
        }
    }
    if ($javaHome -and (Test-Path (Join-Path $javaHome "bin\java.exe"))) {
        $env:JAVA_HOME = $javaHome
        $javaBin = Join-Path $javaHome "bin"
        if ($env:Path -notlike "*$javaBin*") {
            $env:Path = "$javaBin;$env:Path"
        }
    }

    $pythonExe = Find-PythonExecutable
    if ($pythonExe) {
        $pythonDir = Split-Path $pythonExe
        if ($pythonDir -and ($env:Path -notlike "*$pythonDir*")) {
            $env:Path = "$pythonDir;$env:Path"
        }
        $scripts = Join-Path $pythonDir "Scripts"
        if ((Test-Path $scripts) -and ($env:Path -notlike "*$scripts*")) {
            $env:Path = "$scripts;$env:Path"
        }
    }
}

function Get-VsWhere {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) { return $vswhere }
    return $null
}

function Test-VsComponent {
    param([string]$Requires)
    $vswhere = Get-VsWhere
    if (-not $vswhere) { return $false }
    $installation = & $vswhere -latest -products * -requires $Requires -property installationPath 2>$null
    return -not [string]::IsNullOrWhiteSpace($installation)
}

# VS Build Tools do not put link.exe on PATH. Import VsDevCmd so C++ and Rust
# can find the MSVC linker. On ARM64 prefer native ARM64 toolset when present.
function Import-VsDevEnvironment {
    $script:CmakeArch = "x64"
    $vswhere = Get-VsWhere
    if (-not $vswhere) { return }

    $install = & $vswhere -latest -products * -property installationPath 2>$null
    if (-not $install) { return }
    $vsdev = Join-Path $install.Trim() "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path $vsdev)) { return }

    $arch = "x64"
    $hostArch = "x64"
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        if (Test-VsComponent "Microsoft.VisualStudio.Component.VC.Tools.ARM64") {
            $arch = "arm64"
            $hostArch = "arm64"
            $script:CmakeArch = "ARM64"
        }
    }

    $quoted = '"{0}" -no_logo -arch={1} -host_arch={2} && set' -f $vsdev, $arch, $hostArch
    cmd /c $quoted 2>$null | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            Set-Item -LiteralPath "Env:$($matches[1])" -Value $matches[2]
        }
    }
}

function Test-RealPython {
    param([string]$File)
    if (-not $File -or -not (Test-Path $File)) { return $false }
    if ($File -like "*\WindowsApps\*") { return $false }
    return $true
}

function Find-PythonExecutable {
    foreach ($name in @("python3", "python")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and (Test-RealPython $cmd.Source)) {
            return $cmd.Source
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
            Where-Object { Test-RealPython $_ } |
            Select-Object -First 1
        if ($exe) { return $exe }
    }
    return $null
}

function Find-PythonLauncher {
    foreach ($candidate in @(
        (Get-Command py -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "C:\Windows\py.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )) {
        if (Test-RealPython $candidate) { return $candidate }
    }
    return $null
}

Update-SessionEnvironment
Import-VsDevEnvironment

$Root = $PSScriptRoot
$ValidLanguages = @("dotnet", "node", "python", "go", "ruby", "java", "cpp", "rust")

if (-not $Languages -or $Languages.Count -eq 0) {
    $Languages = $ValidLanguages
}

$Results = @{}
$Failed = 0

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "-- $Title -----------------------------"
}

function Record-Result {
    param([string]$Language, [string]$Status)
    $script:Results[$Language] = $Status
    if ($Status -ne "pass") {
        $script:Failed = 1
    }
}

function Get-PythonCommand {
    $exe = Find-PythonExecutable
    if ($exe) {
        return @{ File = $exe; Prefix = @() }
    }
    $launcher = Find-PythonLauncher
    if ($launcher) {
        return @{ File = $launcher; Prefix = @("-3") }
    }
    throw "Python 3 is not on PATH. Run .\install-deps.ps1 first."
}

function Invoke-Language {
    param(
        [string]$Language,
        [string]$Title,
        [string]$Directory,
        [scriptblock]$Action
    )
    Write-Section $Title
    Push-Location (Join-Path $Root $Directory)
    try {
        & $Action
        if ($LASTEXITCODE -eq 0) {
            Record-Result $Language "pass"
        } else {
            Record-Result $Language "fail"
        }
    } catch {
        Write-Host $_
        Record-Result $Language "fail"
    } finally {
        Pop-Location
    }
}

function Invoke-Dotnet {
    Invoke-Language "dotnet" ".NET" "dotnet" {
        dotnet run
    }
}

function Invoke-Node {
    Invoke-Language "node" "Node.js" "node" {
        npm install --silent
        if ($LASTEXITCODE -ne 0) { return }
        node index.js
    }
}

function Invoke-Python {
    Invoke-Language "python" "Python" "python" {
        $py = Get-PythonCommand
        & $py.File @($py.Prefix + @("-m", "venv", ".venv"))
        $venvPython = Join-Path (Get-Location) ".venv\Scripts\python.exe"
        if (-not (Test-Path $venvPython)) {
            throw "venv python was not created at $venvPython"
        }
        & $venvPython -m pip install --quiet --upgrade -r requirements.txt
        if ($LASTEXITCODE -ne 0) { return }
        & $venvPython main.py
    }
}

function Invoke-Go {
    Invoke-Language "go" "Go" "go" {
        go run .
    }
}

function Invoke-Ruby {
    Invoke-Language "ruby" "Ruby" "ruby" {
        # Ruby 3.2+ removed String#untaint. Bundler 1.x (from an old
        # Gemfile.lock or a leftover gem) crashes on Windows Ruby 3.3.
        if (Get-Command gem -ErrorAction SilentlyContinue) {
            gem install bundler --no-document --silent
        }
        if (Get-Command bundle -ErrorAction SilentlyContinue) {
            bundle install --quiet
            if ($LASTEXITCODE -ne 0) { return }
            bundle exec ruby main.rb
        } else {
            gem install --silent kryptic-daemon-client --version 0.1.3
            if ($LASTEXITCODE -ne 0) { return }
            ruby main.rb
        }
    }
}

function Invoke-Java {
    Invoke-Language "java" "Java" "java" {
        mvn -q compile exec:java
    }
}

function Invoke-Cpp {
    Invoke-Language "cpp" "C++" "cpp" {
        $buildDir = Join-Path (Get-Location) "build"
        if (Test-Path $buildDir) {
            Remove-Item $buildDir -Recurse -Force
        }
        $cmakeArgs = @("-S", ".", "-B", "build")
        if ($env:OS -eq "Windows_NT") {
            $arch = if ($script:CmakeArch) { $script:CmakeArch } else { "x64" }
            $cmakeArgs += @("-A", $arch)
        } else {
            $cmakeArgs += "-DCMAKE_BUILD_TYPE=Release"
        }
        & cmake @cmakeArgs
        if ($LASTEXITCODE -ne 0) { return }
        cmake --build build --config Release
        if ($LASTEXITCODE -ne 0) { return }
        $candidates = @(
            (Join-Path (Get-Location) "build\Release\kryptic-test-runner.exe"),
            (Join-Path (Get-Location) "build\ARM64\Release\kryptic-test-runner.exe"),
            (Join-Path (Get-Location) "build\x64\Release\kryptic-test-runner.exe"),
            (Join-Path (Get-Location) "build\kryptic-test-runner.exe"),
            (Join-Path (Get-Location) "build\Debug\kryptic-test-runner.exe")
        )
        $exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $exe) {
            throw "built binary not found under build\"
        }
        & $exe
    }
}

function Invoke-Rust {
    Invoke-Language "rust" "Rust" "rust" {
        # Native ARM64 rustc needs the ARM64 MSVC toolset. If only x64 VC
        # tools are present, build the x64 rust target under emulation.
        if ($env:OS -eq "Windows_NT" -and $env:PROCESSOR_ARCHITECTURE -eq "ARM64" -and $script:CmakeArch -ne "ARM64") {
            rustup toolchain install stable-x86_64-pc-windows-msvc --force-non-host
            if ($LASTEXITCODE -ne 0) { return }
            cargo +stable-x86_64-pc-windows-msvc run --quiet
            return
        }
        if ($env:OS -eq "Windows_NT" -and -not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
            throw "link.exe not found. Open a Developer PowerShell, or re-run .\install-deps.ps1 so the VS C++ tools are on PATH."
        }
        cargo run --quiet
    }
}

foreach ($language in $Languages) {
    switch ($language) {
        "dotnet" { Invoke-Dotnet }
        "node"   { Invoke-Node }
        "python" { Invoke-Python }
        "go"     { Invoke-Go }
        "ruby"   { Invoke-Ruby }
        "java"   { Invoke-Java }
        "cpp"    { Invoke-Cpp }
        "rust"   { Invoke-Rust }
        default {
            Write-Host "unknown language: $language" -ForegroundColor Red
            exit 2
        }
    }
}

Write-Section "Summary"
foreach ($language in $Languages) {
    if ($Results[$language] -eq "pass") {
        Write-Host "  [ok]   $language" -ForegroundColor Green
    } else {
        Write-Host "  [fail] $language" -ForegroundColor Red
    }
}

exit $Failed
