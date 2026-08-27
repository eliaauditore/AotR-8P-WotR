<#
.SYNOPSIS
Read-only recursive audit for nested launcher source embedded inside V17 builder Base64 templates.

.DESCRIPTION
Decodes the outer V17 builder template in memory, inventories suspicious encoding/compression/script-host
constructs, then recursively attempts to decode large Base64-like payloads found in text. Decoded bytes are
never executed and never written to disk. GZip and Deflate are attempted only as passive decompression.

No game, launcher, builder, config, registry, Git, or temporary files are modified.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$BuilderPath,

    [ValidateRange(1,5)]
    [int]$MaxDepth = 3,

    [ValidateRange(80,4096)]
    [int]$MinBase64Chars = 160,

    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Sha256Text {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')
    }
    finally { $sha.Dispose() }
}

function Convert-BytesToCandidateText {
    param([byte[]]$Bytes)

    $out = New-Object System.Collections.ArrayList
    foreach ($encoding in @(
        [Text.Encoding]::UTF8,
        [Text.Encoding]::Unicode,
        [Text.Encoding]::BigEndianUnicode,
        [Text.Encoding]::ASCII
    )) {
        try {
            $text = $encoding.GetString($Bytes)
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $printable = 0
                $sampleLen = [Math]::Min($text.Length, 4000)
                for ($i=0; $i -lt $sampleLen; $i++) {
                    $c = [int][char]$text[$i]
                    if (($c -ge 9 -and $c -le 13) -or ($c -ge 32 -and $c -le 126) -or $c -ge 160) { $printable++ }
                }
                $ratio = if ($sampleLen -gt 0) { $printable / [double]$sampleLen } else { 0 }
                if ($ratio -ge 0.75) {
                    [void]$out.Add([pscustomobject]@{
                        Encoding = $encoding.WebName
                        Text = $text
                        PrintableRatio = [Math]::Round($ratio,3)
                    })
                }
            }
        }
        catch { }
    }
    return @($out)
}

function Expand-CompressedCandidate {
    param([byte[]]$Bytes)

    $results = New-Object System.Collections.ArrayList
    foreach ($kind in @('GZip','Deflate')) {
        try {
            $input = New-Object IO.MemoryStream(,$Bytes)
            try {
                if ($kind -eq 'GZip') {
                    $stream = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
                }
                else {
                    $stream = New-Object IO.Compression.DeflateStream($input,[IO.Compression.CompressionMode]::Decompress)
                }
                try {
                    $output = New-Object IO.MemoryStream
                    try {
                        $stream.CopyTo($output)
                        $expanded = $output.ToArray()
                        if ($expanded.Length -gt 0) {
                            [void]$results.Add([pscustomobject]@{
                                Kind = $kind
                                Bytes = $expanded
                            })
                        }
                    }
                    finally { $output.Dispose() }
                }
                finally { $stream.Dispose() }
            }
            finally { $input.Dispose() }
        }
        catch { }
    }
    return @($results)
}

function Get-OuterTemplateText {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $pattern = "(?s)\$template\s*=\s*\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(@'\s*(?<b64>[A-Za-z0-9+/=\r\n]+?)\s*'@\)\)"
    $m = [regex]::Match($raw,$pattern)
    if (-not $m.Success) {
        throw 'Outer $template Base64 block was not found with the expected V17 builder pattern.'
    }
    $b64 = ($m.Groups['b64'].Value -replace '\s','')
    $bytes = [Convert]::FromBase64String($b64)
    return [pscustomobject]@{
        Text = [Text.Encoding]::UTF8.GetString($bytes)
        Bytes = $bytes
    }
}

$interestingTerms = @(
    'FromBase64String','ToBase64String','GZipStream','DeflateStream','Compression','Decompress',
    'PowerShell','pwsh','powershell.exe','ScriptBlock','ProcessStartInfo','cmd.exe',
    'Encoding.UTF8','Encoding.Unicode','Convert','Resource','payload','launcher_gui','engine','gui',
    'AgeoftheRing','Age of the Ring','rotwk','lotrbfme2ep1.exe','game.dat','zGameDats',
    '_AotR8P_WotR_Runtime','AOTR_HOME','repair-manifest','reset_install','retry_launch'
)

function Get-TextEvidence {
    param([string]$Text)

    $lines = @($Text -split "`r?`n")
    $hits = New-Object System.Collections.ArrayList
    foreach ($term in $interestingTerms) {
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                [void]$hits.Add([pscustomobject]@{
                    Term = $term
                    Line = $i + 1
                    Text = $lines[$i].Trim()
                })
            }
        }
    }
    return @($hits)
}

$visited = @{}
$nodes = New-Object System.Collections.ArrayList

function Add-TextNode {
    param(
        [string]$Label,
        [string]$Text,
        [int]$Depth,
        [string]$Parent,
        [string]$DecodeKind
    )

    if ($Depth -gt $MaxDepth) { return }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = Get-Sha256Text $bytes
    if ($visited.ContainsKey($hash)) { return }
    $visited[$hash] = $true

    $evidence = @(Get-TextEvidence $Text)
    $lines = @($Text -split "`r?`n")
    [void]$nodes.Add([pscustomobject]@{
        Label = $Label
        Parent = $Parent
        Depth = $Depth
        DecodeKind = $DecodeKind
        Bytes = $bytes.Length
        Lines = $lines.Count
        SHA256 = $hash
        Evidence = $evidence
    })

    if ($Depth -ge $MaxDepth) { return }

    $matches = [regex]::Matches($Text, "(?<![A-Za-z0-9+/=])([A-Za-z0-9+/]{${MinBase64Chars},}={0,2})(?![A-Za-z0-9+/=])")
    $index = 0
    foreach ($match in $matches) {
        $index++
        $candidate = $match.Groups[1].Value
        if (($candidate.Length % 4) -ne 0) { continue }
        try { $decoded = [Convert]::FromBase64String($candidate) } catch { continue }
        if ($decoded.Length -lt 32) { continue }

        $childBase = "$Label/base64#$index"
        foreach ($t in @(Convert-BytesToCandidateText $decoded)) {
            Add-TextNode -Label "$childBase/$($t.Encoding)" -Text $t.Text -Depth ($Depth+1) -Parent $Label -DecodeKind 'Base64Text'
        }

        foreach ($expanded in @(Expand-CompressedCandidate $decoded)) {
            foreach ($t in @(Convert-BytesToCandidateText $expanded.Bytes)) {
                Add-TextNode -Label "$childBase/$($expanded.Kind)/$($t.Encoding)" -Text $t.Text -Depth ($Depth+1) -Parent $Label -DecodeKind ("Base64+" + $expanded.Kind)
            }
        }
    }
}

$full = [IO.Path]::GetFullPath($BuilderPath)
if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Builder not found: $full" }
$builderHash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
$outer = Get-OuterTemplateText -Path $full
Add-TextNode -Label 'outer-template' -Text $outer.Text -Depth 0 -Parent '' -DecodeKind 'BuilderBase64'

$result = [pscustomobject]@{
    Tool = 'AOTR_8P_RECURSIVE_EMBEDDED_AUDIT_V1'
    ReadOnly = $true
    BuilderPath = $full
    BuilderSHA256 = $builderHash
    OuterDecodedBytes = $outer.Bytes.Length
    Nodes = @($nodes)
    Safety = [pscustomobject]@{
        ExecutesDecodedContent = $false
        WritesFiles = $false
        WritesRegistry = $false
        ModifiesGame = $false
        ModifiesLauncher = $false
        ModifiesGit = $false
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 10
    return
}

Write-Host ''
Write-Host '=== AOTR 8P RECURSIVE EMBEDDED AUDIT / READ ONLY ==='
Write-Host ("Builder : {0}" -f $full)
Write-Host ("SHA256  : {0}" -f $builderHash)
Write-Host ("Outer   : {0} bytes" -f $outer.Bytes.Length)
Write-Host ("Nodes   : {0}" -f $nodes.Count)
Write-Host ''

Write-Host '=== NESTED NODE INVENTORY ==='
$nodes |
    Select-Object Depth,Label,DecodeKind,Bytes,Lines,@{N='EvidenceHits';E={$_.Evidence.Count}},SHA256 |
    Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host '=== ENCODING / COMPRESSION / HOSTING EVIDENCE ==='
$nodes | ForEach-Object {
    $node = $_
    $node.Evidence |
        Where-Object { $_.Term -in @('FromBase64String','ToBase64String','GZipStream','DeflateStream','Compression','Decompress','PowerShell','pwsh','powershell.exe','ScriptBlock','ProcessStartInfo','cmd.exe','Resource','payload','launcher_gui','engine','gui') } |
        ForEach-Object {
            [pscustomobject]@{ Node=$node.Label; Term=$_.Term; Line=$_.Line; Text=$_.Text }
        }
} | Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host '=== AOTR / RESOLVER / REPAIR EVIDENCE ==='
$nodes | ForEach-Object {
    $node = $_
    $node.Evidence |
        Where-Object { $_.Term -in @('AgeoftheRing','Age of the Ring','rotwk','lotrbfme2ep1.exe','game.dat','zGameDats','_AotR8P_WotR_Runtime','AOTR_HOME','repair-manifest','reset_install','retry_launch') } |
        ForEach-Object {
            [pscustomobject]@{ Node=$node.Label; Term=$_.Term; Line=$_.Line; Text=$_.Text }
        }
} | Format-Table -Wrap -AutoSize
