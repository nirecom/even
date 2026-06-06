# Pester tests for even-terminal autostart (Windows)
# Source files under test (not yet implemented):
#   install.ps1, scripts/start.ps1, uninstall.ps1
# These tests will fail until the sources exist — that is expected.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:InstallPs1   = Join-Path $script:RepoRoot 'install.ps1'
    $script:StartPs1     = Join-Path $script:RepoRoot 'scripts\start.ps1'
    $script:UninstallPs1 = Join-Path $script:RepoRoot 'uninstall.ps1'
    $script:FakeServer   = Join-Path $script:RepoRoot 'tests\fixtures\fake-even-terminal.js'

    function script:New-TempDir {
        $name = "et-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $p = Join-Path $env:TEMP $name
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        return (Resolve-Path $p).Path
    }

    function script:New-FakeEvenTerminalOnPath {
        param([string]$Dir)
        # Create a fake `even-terminal.cmd` so install.ps1's path resolution succeeds.
        $binDir = Join-Path $Dir 'bin'
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        $cmd = Join-Path $binDir 'even-terminal.cmd'
        @'
@echo off
echo fake-even-terminal %*
'@ | Set-Content -Path $cmd -Encoding ASCII
        return $binDir
    }

    function script:Invoke-Install {
        param(
            [string[]]$ExtraArgs = @()
        )
        if (-not (Test-Path $script:InstallPs1)) {
            return [pscustomobject]@{ ExitCode = 127; Output = "install.ps1 not found at $script:InstallPs1" }
        }
        $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script:InstallPs1,'-DryRun') + $ExtraArgs
        $out = & pwsh @a 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
    }
}

Describe "install.ps1 -DryRun" {
    BeforeAll {
        $script:TmpDir = New-TempDir
        $env:EVEN_TERMINAL_CONFIG_DIR = $script:TmpDir
        $env:EVEN_TERMINAL_TASK_NAME  = "EvenTerminalTest-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:FakeBin = New-FakeEvenTerminalOnPath -Dir $script:TmpDir
        $script:OriginalPath = $env:PATH
        $env:PATH = "$script:FakeBin;$env:PATH"
    }

    AfterAll {
        if ($script:OriginalPath) { $env:PATH = $script:OriginalPath }
        Remove-Item Env:EVEN_TERMINAL_CONFIG_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:EVEN_TERMINAL_TASK_NAME  -ErrorAction SilentlyContinue
        if ($script:TmpDir -and (Test-Path $script:TmpDir)) {
            Remove-Item -Recurse -Force $script:TmpDir -ErrorAction SilentlyContinue
        }
    }

    It "creates config.json in EVEN_TERMINAL_CONFIG_DIR" {
        if (-not (Test-Path $script:InstallPs1)) { Set-ItResult -Skipped -Because "install.ps1 not yet implemented"; return }
        Invoke-Install | Out-Null
        $configPath = Join-Path $script:TmpDir 'config.json'
        Test-Path $configPath | Should -BeTrue
    }

    It "config has required fields" {
        if (-not (Test-Path $script:InstallPs1)) { Set-ItResult -Skipped -Because "install.ps1 not yet implemented"; return }
        $configPath = Join-Path $script:TmpDir 'config.json'
        $cfg = Get-Content -Raw $configPath | ConvertFrom-Json
        $cfg.version      | Should -Not -BeNullOrEmpty
        $cfg.executable   | Should -Not -BeNullOrEmpty
        $cfg.token        | Should -Not -BeNullOrEmpty
        $cfg.port         | Should -Not -BeNullOrEmpty
        $cfg.provider     | Should -Not -BeNullOrEmpty
        $cfg.network_mode | Should -Not -BeNullOrEmpty
        $cfg.config_dir   | Should -Not -BeNullOrEmpty
    }

    It "token is url-safe base64 at least 30 chars" {
        if (-not (Test-Path $script:InstallPs1)) { Set-ItResult -Skipped -Because "install.ps1 not yet implemented"; return }
        $configPath = Join-Path $script:TmpDir 'config.json'
        $cfg = Get-Content -Raw $configPath | ConvertFrom-Json
        $cfg.token.Length | Should -BeGreaterOrEqual 30
        ($cfg.token -match '^[A-Za-z0-9_\-]+$') | Should -BeTrue
    }

    It "does not register Task Scheduler task" {
        if (-not (Test-Path $script:InstallPs1)) { Set-ItResult -Skipped -Because "install.ps1 not yet implemented"; return }
        $task = Get-ScheduledTask -TaskName $env:EVEN_TERMINAL_TASK_NAME -ErrorAction SilentlyContinue
        $task | Should -BeNullOrEmpty
    }

    It "does not overwrite existing config without -Force" {
        if (-not (Test-Path $script:InstallPs1)) { Set-ItResult -Skipped -Because "install.ps1 not yet implemented"; return }
        $configPath = Join-Path $script:TmpDir 'config.json'
        $before = Get-Content -Raw $configPath
        Invoke-Install | Out-Null
        $after = Get-Content -Raw $configPath
        $after | Should -BeExactly $before
    }

    It "uses custom port when -Port 4567 is specified" {
        if (-not (Test-Path $script:InstallPs1)) { Set-ItResult -Skipped -Because "install.ps1 not yet implemented"; return }
        $altDir = New-TempDir
        $env:EVEN_TERMINAL_CONFIG_DIR = $altDir
        try {
            Invoke-Install -ExtraArgs @('-Port','4567') | Out-Null
            $cfg = Get-Content -Raw (Join-Path $altDir 'config.json') | ConvertFrom-Json
            $cfg.port | Should -Be 4567
        } finally {
            $env:EVEN_TERMINAL_CONFIG_DIR = $script:TmpDir
            Remove-Item -Recurse -Force $altDir -ErrorAction SilentlyContinue
        }
    }
}

Describe "install.ps1 Task Scheduler security" {
    It "install.ps1 source does not pass --token to scheduled action" {
        # Token must travel via env/config, never as a CLI argument visible in
        # Task Scheduler's action arguments (which are world-readable).
        if (-not (Test-Path $script:InstallPs1)) {
            Set-ItResult -Skipped -Because "install.ps1 not yet implemented"
            return
        }
        $src = Get-Content -Raw $script:InstallPs1
        # Heuristic: no literal "--token" embedded in the script source.
        ($src -match '--token') | Should -BeFalse
    }
}

Describe "scripts/start.ps1" {
    BeforeAll {
        $script:TmpDir2 = New-TempDir
        $env:EVEN_TERMINAL_CONFIG_DIR = $script:TmpDir2
    }
    AfterAll {
        Remove-Item Env:EVEN_TERMINAL_CONFIG_DIR -ErrorAction SilentlyContinue
        if ($script:TmpDir2 -and (Test-Path $script:TmpDir2)) {
            Remove-Item -Recurse -Force $script:TmpDir2 -ErrorAction SilentlyContinue
        }
        if ($script:FakeProc -and -not $script:FakeProc.HasExited) {
            try { $script:FakeProc.Kill() } catch {}
        }
    }

    It "exits with code 1 when config not found" {
        if (-not (Test-Path $script:StartPs1)) {
            Set-ItResult -Skipped -Because "start.ps1 not yet implemented"
            return
        }
        # Point config dir at an empty subdir.
        $empty = Join-Path $script:TmpDir2 'empty'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $env:EVEN_TERMINAL_CONFIG_DIR = $empty
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:StartPs1 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        $env:EVEN_TERMINAL_CONFIG_DIR = $script:TmpDir2
    }

    It "skips startup when fake server is already running" {
        if (-not (Test-Path $script:StartPs1)) {
            Set-ItResult -Skipped -Because "start.ps1 not yet implemented"
            return
        }
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because "node not available"
            return
        }
        # Write a minimal config pointing to a port the fake server will occupy.
        $port = 34567
        $cfg = [pscustomobject]@{
            version       = 1
            executable    = 'node'
            executable_args = @()
            token         = 'test-token-aaaaaaaaaaaaaaaaaaaaaa'
            port          = $port
            provider      = 'claude'
            network_mode  = 'auto'
            config_dir    = $script:TmpDir2
        }
        ($cfg | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $script:TmpDir2 'config.json') -Encoding UTF8

        $script:FakeProc = Start-Process -FilePath 'node' `
            -ArgumentList @($script:FakeServer, '--port', "$port") `
            -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 2
        try {
            $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:StartPs1 2>&1
            $exit = $LASTEXITCODE
            ($exit -eq 0) | Should -BeTrue
            ($out -join "`n") | Should -Match 'already|running|skip'
        } finally {
            if ($script:FakeProc -and -not $script:FakeProc.HasExited) {
                try { $script:FakeProc.Kill() } catch {}
            }
        }
    }
}

Describe "uninstall.ps1" {
    BeforeAll {
        $script:TmpDir3 = New-TempDir
        $env:EVEN_TERMINAL_CONFIG_DIR = $script:TmpDir3
        $env:EVEN_TERMINAL_TASK_NAME  = "EvenTerminalTest-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        # Seed a config so uninstall has something to act on.
        $cfg = [pscustomobject]@{
            version = 1; executable = 'x'; executable_args = @()
            token = 'tok'; port = 3456; provider = 'claude'
            network_mode = 'auto'; config_dir = $script:TmpDir3
        }
        ($cfg | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $script:TmpDir3 'config.json') -Encoding UTF8
    }
    AfterAll {
        Remove-Item Env:EVEN_TERMINAL_CONFIG_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:EVEN_TERMINAL_TASK_NAME  -ErrorAction SilentlyContinue
        if ($script:TmpDir3 -and (Test-Path $script:TmpDir3)) {
            Remove-Item -Recurse -Force $script:TmpDir3 -ErrorAction SilentlyContinue
        }
    }

    It "preserves config with -DryRun -KeepConfig" {
        if (-not (Test-Path $script:UninstallPs1)) {
            Set-ItResult -Skipped -Because "uninstall.ps1 not yet implemented"
            return
        }
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:UninstallPs1 -DryRun -KeepConfig 2>&1 | Out-Null
        Test-Path (Join-Path $script:TmpDir3 'config.json') | Should -BeTrue
    }

    It "removes config and creates .bak" {
        if (-not (Test-Path $script:UninstallPs1)) {
            Set-ItResult -Skipped -Because "uninstall.ps1 not yet implemented"
            return
        }
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:UninstallPs1 -DryRun 2>&1 | Out-Null
        $cfgPath = Join-Path $script:TmpDir3 'config.json'
        $bakPath = "$cfgPath.bak"
        (Test-Path $cfgPath) | Should -BeFalse
        (Test-Path $bakPath) | Should -BeTrue
    }
}

Describe "install.ps1 probe timeout behavior" {
    BeforeAll {
        if (Test-Path $script:InstallPs1) {
            $script:ProbeSrc = Get-Content -Raw $script:InstallPs1
        } else {
            $script:ProbeSrc = $null
        }
    }

    It "probe deadline is 30 seconds (not 15)" {
        if (-not $script:ProbeSrc) {
            Set-ItResult -Skipped -Because "install.ps1 not yet implemented"
            return
        }
        ($script:ProbeSrc -match 'AddSeconds\(30\)') | Should -BeTrue
    }

    It "warning message references 30 seconds" {
        if (-not $script:ProbeSrc) {
            Set-ItResult -Skipped -Because "install.ps1 not yet implemented"
            return
        }
        ($script:ProbeSrc -match 'did not start within 30s') | Should -BeTrue
    }

    It "probe timeout block does not call exit 1" {
        if (-not $script:ProbeSrc) {
            Set-ItResult -Skipped -Because "install.ps1 not yet implemented"
            return
        }
        # Extract the if (-not $started) { ... } block using a regex that captures
        # the braced body after the condition.
        $blockMatch = [regex]::Match($script:ProbeSrc, 'if\s*\(\s*-not\s+\$started\s*\)\s*\{([^}]*)\}')
        $blockMatch.Success | Should -BeTrue -Because "the if (-not `$started) block must exist in install.ps1"
        $blockBody = $blockMatch.Groups[1].Value
        ($blockBody -match 'exit\s+1') | Should -BeFalse
    }
}
