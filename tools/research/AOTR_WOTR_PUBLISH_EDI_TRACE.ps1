param(
    [string]$GameDat = 'D:\Games\AotR\AgeoftheRing\rotwk\game.dat',
    [uint32]$WindowStart = 0x00787F00,
    [uint32]$WindowEnd   = 0x00788560,
    [uint32]$EdiScanStart = 0x00786000,
    [uint32]$PublishVa = 0x00788542
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DISK ONLY / READ ONLY.
# Uses Visual Studio dumpbin to disassemble the exact AotR game.dat and isolates
# the code leading into the known GameInfo publish tail around 0x00788542:
#   mov eax,edi
#   mov [0x00DE7D6C],eax
#   mov [0x00DE892C],eax
# The goal is to identify where EDI was sourced before the publish.
# No process is opened. No file bytes are modified.

$ExpectedHash = 'CC08275D60FF8E3BFD4374C29D61304DEA8336E6DD00AB8ADD88B1DF95A705DC'

if (-not (Test-Path -LiteralPath $GameDat)) {
    throw "game.dat not found: $GameDat"
}

$hash = (Get-FileHash -LiteralPath $GameDat -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $ExpectedHash) {
    throw "HASH MISMATCH. Expected $ExpectedHash, got $hash"
}

function Find-Dumpbin {
    $candidates = New-Object System.Collections.Generic.List[string]

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        try {
            $install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)
            if ($install) {
                Get-ChildItem -LiteralPath (Join-Path $install 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    ForEach-Object {
                        $candidates.Add((Join-Path $_.FullName 'bin\Hostx64\x86\dumpbin.exe'))
                        $candidates.Add((Join-Path $_.FullName 'bin\Hostx86\x86\dumpbin.exe'))
                        $candidates.Add((Join-Path $_.FullName 'bin\Hostx64\x64\dumpbin.exe'))
                    }
            }
        } catch { }
    }

    foreach ($root in @(
        'C:\Program Files\Microsoft Visual Studio\2022',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022'
    )) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $msvcRoot = Join-Path $_.FullName 'VC\Tools\MSVC'
                if (Test-Path -LiteralPath $msvcRoot) {
                    Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue |
                        Sort-Object Name -Descending |
                        ForEach-Object {
                            $candidates.Add((Join-Path $_.FullName 'bin\Hostx64\x86\dumpbin.exe'))
                            $candidates.Add((Join-Path $_.FullName 'bin\Hostx86\x86\dumpbin.exe'))
                            $candidates.Add((Join-Path $_.FullName 'bin\Hostx64\x64\dumpbin.exe'))
                        }
                }
            }
        }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }

    $cmd = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Parse-Address([string]$line) {
    if ($line -match '^\s*([0-9A-Fa-f]{8}):') {
        return [uint32][Convert]::ToUInt32($Matches[1],16)
    }
    return $null
}

$dumpbin = Find-Dumpbin
if (-not $dumpbin) {
    throw 'dumpbin.exe not found. Install/enable Visual Studio C++ build tools or run from a Developer PowerShell where dumpbin is available.'
}

$tmp = Join-Path $env:TEMP ("aotr_publish_edi_{0}.txt" -f ([Guid]::NewGuid().ToString('N')))

Write-Host ''
Write-Host '============================================================'
Write-Host ' AOTR WOTR GAMEINFO PUBLISH EDI TRACE - DISK ONLY'
Write-Host '============================================================'
Write-Host ("Image       : {0}" -f $GameDat)
Write-Host ("SHA256      : {0}" -f $hash)
Write-Host ("dumpbin     : {0}" -f $dumpbin)
Write-Host ("Publish VA  : 0x{0:X8}" -f $PublishVa)
Write-Host ("Window      : 0x{0:X8}..0x{1:X8}" -f $WindowStart,$WindowEnd)
Write-Host ("EDI scan    : 0x{0:X8}..0x{1:X8}" -f $EdiScanStart,$PublishVa)
Write-Host ''

try {
    Write-Host 'Running dumpbin /DISASM. This may take a moment...'
    & $dumpbin /nologo /disasm $GameDat 2>&1 | Set-Content -LiteralPath $tmp -Encoding UTF8

    $all = Get-Content -LiteralPath $tmp
    $parsed = New-Object System.Collections.Generic.List[object]

    foreach ($line in $all) {
        $addr = Parse-Address $line
        if ($null -ne $addr) {
            $parsed.Add([pscustomobject]@{ Address=[uint32]$addr; Text=[string]$line })
        }
    }

    if ($parsed.Count -eq 0) {
        throw 'No disassembly address lines were parsed from dumpbin output.'
    }

    Write-Host ''
    Write-Host '================ PUBLISH TAIL ================='
    $tail = @($parsed | Where-Object { $_.Address -ge 0x00788520 -and $_.Address -le 0x00788558 })
    if ($tail.Count -eq 0) {
        Write-Host '<no lines in expected publish-tail range>'
    } else {
        $tail | ForEach-Object { Write-Host $_.Text }
    }

    Write-Host ''
    Write-Host '================ EDI TOUCHES BEFORE PUBLISH ================='
    $edi = @($parsed | Where-Object {
        $_.Address -ge $EdiScanStart -and
        $_.Address -le $PublishVa -and
        $_.Text -match '(?i)\bedi\b'
    })
    Write-Host ("EDI lines: {0}" -f $edi.Count)
    $edi | ForEach-Object { Write-Host $_.Text }

    Write-Host ''
    Write-Host '================ GAMEINFO GLOBAL REFERENCES IN SAME RANGE ================='
    $globals = @($parsed | Where-Object {
        $_.Address -ge $EdiScanStart -and
        $_.Address -le $WindowEnd -and
        $_.Text -match '(?i)(00DE7D6C|00DE892C|00DE8930|DE7D6C|DE892C|DE8930)'
    })
    Write-Host ("Global-ref lines: {0}" -f $globals.Count)
    $globals | ForEach-Object { Write-Host $_.Text }

    Write-Host ''
    Write-Host '================ FULL PUBLISH WINDOW ================='
    $window = @($parsed | Where-Object { $_.Address -ge $WindowStart -and $_.Address -le $WindowEnd })
    Write-Host ("Window lines: {0}" -f $window.Count)
    $window | ForEach-Object { Write-Host $_.Text }

    Write-Host ''
    Write-Host 'Interpretation:'
    Write-Host '  1. The PUBLISH TAIL should show mov eax,edi followed by writes to TheGameInfo and 0x00DE892C.'
    Write-Host '  2. In EDI TOUCHES, the last path-valid instruction that DEFINES EDI is the key source candidate.'
    Write-Host '  3. If EDI is loaded from 0x00DE892C or from a call using that object, same-instance handoff becomes strongly supported.'
    Write-Host '  4. If EDI comes from an allocation/copy constructor, the handoff uses a distinct instance.'
    Write-Host ''
    Write-Host 'DISK-ONLY COMPLETE. No process memory or game.dat bytes were modified.'
}
finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
