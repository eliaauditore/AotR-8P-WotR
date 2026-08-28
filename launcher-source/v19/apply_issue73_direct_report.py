from pathlib import Path
import argparse
import hashlib
import re

EXPECTED_INPUT = "135B1FDD64B84B0DE84BC7526F04157A790228DFC49FF5DD6253C89023D71EBD"

OLD_REPORT_BORDER = '''                    <Border x:Name="DiagReportHit" Grid.Column="3" Padding="11,7"
                            VerticalAlignment="Center" Background="#332B1C1C"
                            BorderBrush="#8B4D45" BorderThickness="1" CornerRadius="2"
                            Cursor="Hand" Visibility="Collapsed">
                        <TextBlock Text="REPORT ERROR" Foreground="#DF7468" FontFamily="Georgia" FontSize="10.5" FontWeight="Bold"/>
                    </Border>'''

NEW_REPORT_BORDER = '''                    <StackPanel x:Name="DiagReportHit" Grid.Column="3" Orientation="Horizontal"
                                VerticalAlignment="Center" Visibility="Collapsed">
                        <Border x:Name="DiagSendReportHit" Padding="10,7"
                                Background="#33261F16" BorderBrush="#8B7045" BorderThickness="1" CornerRadius="2"
                                Cursor="Hand">
                            <TextBlock Text="SEND REPORT" Foreground="#D3A55F" FontFamily="Georgia" FontSize="9.5" FontWeight="Bold"/>
                        </Border>
                        <Border x:Name="DiagOpenGitHubHit" Margin="6,0,0,0" Padding="9,7"
                                Background="#221E1B18" BorderBrush="#756B58" BorderThickness="1" CornerRadius="2"
                                Cursor="Hand">
                            <TextBlock Text="OPEN GITHUB" Foreground="#B5B9B8" FontFamily="Georgia" FontSize="9.5" FontWeight="Bold"/>
                        </Border>
                        <Border x:Name="DiagCopyReportHit" Margin="6,0,0,0" Padding="9,7"
                                Background="#221E1B18" BorderBrush="#756B58" BorderThickness="1" CornerRadius="2"
                                Cursor="Hand">
                            <TextBlock Text="COPY REPORT" Foreground="#B5B9B8" FontFamily="Georgia" FontSize="9.5" FontWeight="Bold"/>
                        </Border>
                    </StackPanel>'''

OLD_FIND = '$DiagReportHit = $ErrorWindow.FindName("DiagReportHit")\n'
NEW_FIND = '''$DiagReportHit = $ErrorWindow.FindName("DiagReportHit")
$DiagSendReportHit = $ErrorWindow.FindName("DiagSendReportHit")
$DiagOpenGitHubHit = $ErrorWindow.FindName("DiagOpenGitHubHit")
$DiagCopyReportHit = $ErrorWindow.FindName("DiagCopyReportHit")
'''

OLD_COMPACT_NOTE = '        $lines += "Full support bundle was too large for a safe GitHub prefill URL. The launcher saved support_bundle_latest.json locally and copied the full JSON to the clipboard."\n'
NEW_COMPACT_NOTE = '        $lines += "Full support bundle was too large for a safe GitHub prefill URL. The launcher saved support_bundle_latest.json locally."\n'

NEW_REPORT_FUNCTIONS = r'''$script:LastDirectReportUrl = ""
$script:LastDirectReportFingerprint = ""
$script:DirectReportConfigUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/direct-report.json"

function Ensure-LauncherReportIdentity {
    if ([string]::IsNullOrWhiteSpace([string]$script:LastFingerprint)) {
        $script:LastFingerprint = Get-SupportFingerprint ([string]$script:LastErrorCode) ([string]$script:LastErrorDetail)
    }
    Register-SupportFingerprint $script:LastFingerprint
}

function Get-LauncherReportTitleText {
    $titleText = [string]$script:LastErrorTitle
    if ([string]::IsNullOrWhiteSpace($titleText)) { $titleText = "Auto-Repair failed" }
    return $titleText
}

function New-LauncherReportLink {
    Ensure-LauncherReportIdentity
    $title = "[Launcher Report] " + [string]$script:LastErrorCode + " - " + (Get-LauncherReportTitleText)
    $body = Get-LauncherReportBody
    $url = $GitHubIssueUrl + "?template=launcher-auto-report.md&title=" + [Uri]::EscapeDataString($title) + "&body=" + [Uri]::EscapeDataString($body)
    $usedCompactFallback = $false

    # GitHub documents that oversized query URLs return HTTP 414. Keep a
    # safety margin and fall back to a concise URL; the full bundle remains local.
    if ($url.Length -gt 7000) {
        $usedCompactFallback = $true
        $body = Get-LauncherReportBody -Compact
        $url = $GitHubIssueUrl + "?template=launcher-auto-report.md&title=" + [Uri]::EscapeDataString($title) + "&body=" + [Uri]::EscapeDataString($body)
    }

    return [pscustomobject]@{
        Url = [string]$url
        Compact = [bool]$usedCompactFallback
    }
}

function Copy-LauncherReportLink([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        [Windows.Clipboard]::SetText($Url)
        return $true
    }
    catch {
        Write-RepairLog ("Could not copy report link: " + $_.Exception.Message)
        return $false
    }
}

function Open-ExternalUrlSafe([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        Start-Process $Url -ErrorAction Stop
        return $true
    }
    catch {
        Write-RepairLog ("Primary URL open failed: " + $_.Exception.Message)
    }

    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $Url
        $psi.UseShellExecute = $true
        [void][Diagnostics.Process]::Start($psi)
        return $true
    }
    catch {
        Write-RepairLog ("Shell-execute URL fallback failed: " + $_.Exception.Message)
        return $false
    }
}

function Copy-LauncherReport {
    if (-not $script:ReportReady) { return }
    try {
        $link = New-LauncherReportLink
        [void](Save-LatestSupportBundle)
        if (Copy-LauncherReportLink ([string]$link.Url)) {
            $DiagFooterText.Text = "Report link copied — paste it into any browser. support_bundle_latest.json is saved locally."
        } else {
            $DiagFooterText.Text = "Could not access the clipboard — support_bundle_latest.json is still saved locally."
        }
    }
    catch {
        Write-RepairLog ("Could not copy launcher report: " + $_.Exception.Message)
        $DiagFooterText.Text = "Could not prepare report link — support_bundle_latest.json remains saved locally."
    }
}

function Open-LauncherReport {
    if (-not $script:ReportReady) { return }
    try {
        # After a successful direct submission, OPEN GITHUB opens the created issue.
        if (-not [string]::IsNullOrWhiteSpace([string]$script:LastDirectReportUrl) -and
            [string]$script:LastDirectReportFingerprint -eq [string]$script:LastFingerprint) {
            if (Open-ExternalUrlSafe ([string]$script:LastDirectReportUrl)) {
                $DiagFooterText.Text = "GitHub issue opened."
                return
            }
            [void](Copy-LauncherReportLink ([string]$script:LastDirectReportUrl))
            $DiagFooterText.Text = "Browser could not open — issue link copied to clipboard."
            return
        }

        $link = New-LauncherReportLink
        Write-RepairLog ("Opening user-reviewed GitHub report for " + $script:LastFingerprint + $(if ($link.Compact) { " using compact URL fallback" } else { "" }))
        if (Open-ExternalUrlSafe ([string]$link.Url)) {
            $DiagFooterText.Text = if ($link.Compact) {
                "GitHub opened — full support bundle remains saved locally"
            } else {
                "GitHub opened — review the prefilled report and press Submit"
            }
            return
        }

        [void](Save-LatestSupportBundle)
        $copied = Copy-LauncherReportLink ([string]$link.Url)
        $DiagFooterText.Text = if ($copied) {
            "Browser could not open — report link copied. Paste it into any browser."
        } else {
            "Browser could not open — support_bundle_latest.json remains saved locally."
        }
        [System.Windows.Forms.MessageBox]::Show(
            $(if ($copied) {
                "The report page could not be opened automatically.`r`n`r`nThe complete report link was copied to the clipboard. Paste it into any browser.`r`n`r`nsupport_bundle_latest.json was also saved locally."
            } else {
                "The report page could not be opened automatically and the clipboard was unavailable.`r`n`r`nsupport_bundle_latest.json was saved locally."
            }),
            "AotR 8P WotR - Report Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
    catch {
        Write-RepairLog ("Could not prepare GitHub report: " + $_.Exception.Message)
        try { [void](Save-LatestSupportBundle) } catch {}
        $DiagFooterText.Text = "Could not prepare GitHub report — support_bundle_latest.json remains saved locally."
    }
}

function Get-DirectReportEndpoint {
    try {
        $configText = Get-HttpText $script:DirectReportConfigUrl
        if ([string]::IsNullOrWhiteSpace($configText)) { return "" }
        $config = $configText | ConvertFrom-Json
        if ($null -eq $config -or -not [bool]$config.enabled) { return "" }
        $endpoint = [string]$config.endpoint
        if ([string]::IsNullOrWhiteSpace($endpoint)) { return "" }

        $uri = $null
        if (-not [Uri]::TryCreate($endpoint,[UriKind]::Absolute,[ref]$uri)) { return "" }
        if ($null -eq $uri -or $uri.Scheme -ne "https") { return "" }
        if ([string]::IsNullOrWhiteSpace($uri.Host)) { return "" }
        return $uri.AbsoluteUri
    }
    catch {
        Write-RepairLog ("Direct-report endpoint discovery unavailable: " + $_.Exception.Message)
        return ""
    }
}

function Send-LauncherReport {
    if (-not $script:ReportReady) { return }
    try {
        Ensure-LauncherReportIdentity

        # Prevent accidental double-submit for the same report in this launcher session.
        if ([string]$script:LastDirectReportFingerprint -eq [string]$script:LastFingerprint -and
            -not [string]::IsNullOrWhiteSpace([string]$script:LastDirectReportUrl)) {
            $DiagFooterText.Text = "REPORT ALREADY SENT — use OPEN GITHUB to view the issue."
            return
        }

        $endpoint = Get-DirectReportEndpoint
        if ([string]::IsNullOrWhiteSpace($endpoint)) {
            $DiagFooterText.Text = "Direct reporting is unavailable — use OPEN GITHUB or COPY REPORT."
            Write-RepairLog "Direct reporting unavailable: no enabled HTTPS endpoint in trusted config."
            return
        }

        $bundleJson = Save-LatestSupportBundle
        if ([string]::IsNullOrWhiteSpace($bundleJson)) { throw "Support bundle could not be generated." }
        $bundle = $bundleJson | ConvertFrom-Json
        $exact = Limit-SupportText (Get-SanitizedText ([string]$script:LastErrorDetail)) 6000
        $payload = [ordered]@{
            schema = 1
            title = (Get-LauncherReportTitleText)
            exact_error = $exact
            support_bundle = $bundle
        }
        $payloadJson = $payload | ConvertTo-Json -Depth 10 -Compress
        if ([Text.Encoding]::UTF8.GetByteCount($payloadJson) -gt 65536) {
            throw "Direct report payload exceeds the 64 KB safety limit."
        }

        $DiagFooterText.Text = "Sending privacy-safe support report..."
        Write-RepairLog ("Sending accountless direct report for " + $script:LastFingerprint)

        $content = [System.Net.Http.StringContent]::new($payloadJson,[Text.Encoding]::UTF8,"application/json")
        $response = $null
        try {
            $response = $script:HttpClient.PostAsync($endpoint,$content).GetAwaiter().GetResult()
            $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                $serviceError = ""
                try {
                    $errorObject = $responseText | ConvertFrom-Json
                    $serviceError = [string]$errorObject.error
                } catch {}
                $status = [int]$response.StatusCode
                throw ("Direct report service returned HTTP " + $status + $(if ($serviceError) { " (" + $serviceError + ")" } else { "" }))
            }

            $result = $responseText | ConvertFrom-Json
            if ($null -eq $result -or -not [bool]$result.ok) { throw "Direct report service returned an invalid response." }
            $issueNumber = [int]$result.issue_number
            $issueUrl = [string]$result.issue_url
            if ($issueNumber -le 0 -or [string]::IsNullOrWhiteSpace($issueUrl)) { throw "Direct report response is missing issue identity." }

            $script:LastDirectReportFingerprint = [string]$script:LastFingerprint
            $script:LastDirectReportUrl = $issueUrl
            $ticketId = "A8P-TICKET-{0:D4}" -f $issueNumber
            $DiagRepairText.Text = "REPORT SENT — " + $ticketId
            $DiagFooterText.Text = "Issue #" + $issueNumber + " created • " + [string]$script:LastFingerprint
            Write-RepairLog ("Direct report created issue #" + $issueNumber + " for " + $script:LastFingerprint)
        }
        finally {
            if ($null -ne $response) { $response.Dispose() }
            $content.Dispose()
        }
    }
    catch {
        Write-RepairLog ("Direct report failed: " + $_.Exception.Message)
        try { [void](Save-LatestSupportBundle) } catch {}
        $DiagFooterText.Text = "Direct send failed — use OPEN GITHUB or COPY REPORT."
    }
}
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Issue73 {label}: expected exactly 1 source block, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    parser.add_argument("--expected-output", default="")
    args = parser.parse_args()

    path = Path(args.gui_path)
    actual_input = sha256(path)
    if actual_input != EXPECTED_INPUT:
        raise SystemExit(f"Issue73 input GUI hash mismatch: expected {EXPECTED_INPUT}, got {actual_input}")

    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    text = replace_once(text, OLD_REPORT_BORDER, NEW_REPORT_BORDER, "report action XAML")
    text = replace_once(text, OLD_FIND, NEW_FIND, "report control binding")
    text = replace_once(text, OLD_COMPACT_NOTE, NEW_COMPACT_NOTE, "compact fallback wording")

    pattern = r"(?ms)^function Open-LauncherReport \{\n.*?^\}\n\n(?=function Set-ReportReady)"
    text, count = re.subn(pattern, NEW_REPORT_FUNCTIONS + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"Issue73 report function replacement count={count}; expected 1")

    old_handler = '$DiagReportHit.Add_MouseLeftButtonUp({ Open-LauncherReport })\n'
    new_handler = '''$DiagSendReportHit.Add_MouseLeftButtonUp({ Send-LauncherReport })
$DiagOpenGitHubHit.Add_MouseLeftButtonUp({ Open-LauncherReport })
$DiagCopyReportHit.Add_MouseLeftButtonUp({ Copy-LauncherReport })
'''
    text = replace_once(text, old_handler, new_handler, "report click handlers")

    required = (
        'x:Name="DiagSendReportHit"',
        'Text="SEND REPORT"',
        'x:Name="DiagOpenGitHubHit"',
        'Text="OPEN GITHUB"',
        'x:Name="DiagCopyReportHit"',
        'Text="COPY REPORT"',
        'function Send-LauncherReport {',
        'function Open-ExternalUrlSafe([string]$Url)',
        'function Get-DirectReportEndpoint {',
        '$script:DirectReportConfigUrl = "https://raw.githubusercontent.com/eliaauditore/AotR-8P-WotR/main/direct-report.json"',
        '$script:HttpClient.PostAsync($endpoint,$content)',
        'A8P-TICKET-{0:D4}',
        'Direct send failed — use OPEN GITHUB or COPY REPORT.',
        '$DiagRetryHit.Add_MouseLeftButtonUp({',
    )
    forbidden = (
        '$DiagReportHit.Add_MouseLeftButtonUp({ Open-LauncherReport })',
        'The support bundle was saved locally and copied to the clipboard when possible.',
        'GITHUB_REPORT_TOKEN',
        'Authorization: Bearer',
        'github_pat_',
        'ghp_',
    )
    for token in required:
        if token not in text:
            raise SystemExit("Issue73 required token missing: " + token)
    for token in forbidden:
        if token in text:
            raise SystemExit("Issue73 forbidden token present: " + token)

    path.write_text(text, encoding="utf-8-sig", newline="\n")
    output_hash = sha256(path)
    print("ISSUE73_GUI_SHA256=" + output_hash)
    print("ISSUE73_DIRECT_REPORT_GATE=PASS")

    expected = args.expected_output.strip().upper()
    if expected and output_hash != expected:
        raise SystemExit(f"Issue73 output GUI hash mismatch: expected {expected}, got {output_hash}")


if __name__ == "__main__":
    main()
