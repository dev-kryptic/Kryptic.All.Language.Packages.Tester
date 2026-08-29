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
    foreach ($name in @("python3", "python")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return @{ File = $cmd.Source; Prefix = @() }
        }
    }
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        return @{ File = $launcher.Source; Prefix = @("-3") }
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
        if (Get-Command bundle -ErrorAction SilentlyContinue) {
            bundle install --quiet
            if ($LASTEXITCODE -ne 0) { return }
            bundle exec ruby main.rb
        } else {
            gem install --silent kryptic-daemon-client --version 0.1.0
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
        cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
        if ($LASTEXITCODE -ne 0) { return }
        cmake --build build --config Release
        if ($LASTEXITCODE -ne 0) { return }
        $candidates = @(
            (Join-Path (Get-Location) "build\Release\kryptic-test-runner.exe"),
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
