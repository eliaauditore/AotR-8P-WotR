from pathlib import Path
import argparse
import hashlib

EXPECTED_INPUT = "8A31D3EDC48B5915AC552EFB26DFF48CEABB1022D24C0A90834930117046A2AA"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def replace_once(data: bytes, old: bytes, new: bytes, label: str) -> bytes:
    count = data.count(old)
    if count != 1:
        raise SystemExit(f"{label} anchor count={count}; expected 1")
    return data.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gui_path")
    args = parser.parse_args()
    path = Path(args.gui_path)
    data = path.read_bytes()
    actual = sha256_bytes(data)
    if actual != EXPECTED_INPUT:
        raise SystemExit(f"1.16.1 input GUI hash mismatch: expected {EXPECTED_INPUT}, got {actual}")

    nl = b"\r\n" if b"\r\n" in data else b"\n"

    # Put CHANGELOG into the intentionally unused bottom-bar gap between MESSAGES and version text.
    xaml_anchor = nl.join([
        b'        <Border x:Name="MessagesHit"',
        b'                Canvas.Left="338" Canvas.Top="633"',
        b'                Width="224" Height="32"',
        b'                Background="Transparent"',
        b'                Cursor="Hand"/>',
        b'',
        b'        <!-- Always read from the running EXE; never hard-code the displayed version. -->',
    ])
    xaml_new = nl.join([
        b'        <Border x:Name="MessagesHit"',
        b'                Canvas.Left="338" Canvas.Top="633"',
        b'                Width="224" Height="32"',
        b'                Background="Transparent"',
        b'                Cursor="Hand"/>',
        b'',
        b'        <!-- Local launcher changelog. Kept in the unused bottom-bar gap. -->',
        b'        <Border x:Name="ChangelogTextHost"',
        b'                Canvas.Left="574" Canvas.Top="637"',
        b'                Width="124" Height="24"',
        b'                Background="Transparent"',
        b'                IsHitTestVisible="False">',
        b'            <TextBlock Text="CHANGELOG"',
        b'                       HorizontalAlignment="Center"',
        b'                       VerticalAlignment="Center"',
        b'                       Foreground="#8E999E"',
        b'                       FontFamily="Georgia"',
        b'                       FontSize="11.5"',
        b'                       FontWeight="Bold"/>',
        b'        </Border>',
        b'        <Border x:Name="ChangelogHit"',
        b'                Canvas.Left="570" Canvas.Top="633"',
        b'                Width="132" Height="32"',
        b'                Background="Transparent"',
        b'                Cursor="Hand"/>',
        b'',
        b'        <!-- Always read from the running EXE; never hard-code the displayed version. -->',
    ])
    data = replace_once(data, xaml_anchor, xaml_new, "CHANGELOG XAML")

    # Bind the new hit target alongside the existing MESSAGES control.
    binding_anchor = b'$MessagesHit = $Window.FindName("MessagesHit")'
    binding_new = binding_anchor + nl + b'$ChangelogHit = $Window.FindName("ChangelogHit")'
    data = replace_once(data, binding_anchor, binding_new, "CHANGELOG FindName")

    # One short, non-blocking system sound only when the newest maintainer message ID advances.
    fetch_anchor = nl.join([
        b'    $messages = @(Get-MaintainerMessages $master)',
        b'    if ($messages.Count -gt 0) {',
        b'        $latest = $messages[-1]',
        b'        $script:SupportState["latest_message_id"] = [Int64]$latest.id',
        b'        if ($MarkRead) { $script:SupportState["last_seen_message_id"] = [Int64]$latest.id }',
        b'    }',
        b'    Save-SupportState',
    ])
    fetch_new = nl.join([
        b'    $previousLatestMessageId = 0L',
        b'    try { $previousLatestMessageId = [Int64]$script:SupportState["latest_message_id"] } catch {}',
        b'    $messages = @(Get-MaintainerMessages $master)',
        b'    if ($messages.Count -gt 0) {',
        b'        $latest = $messages[-1]',
        b'        $newLatestMessageId = [Int64]$latest.id',
        b'        if ($newLatestMessageId -gt $previousLatestMessageId) {',
        b'            try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}',
        b'        }',
        b'        $script:SupportState["latest_message_id"] = $newLatestMessageId',
        b'        if ($MarkRead) { $script:SupportState["last_seen_message_id"] = $newLatestMessageId }',
        b'    }',
        b'    Save-SupportState',
    ])
    data = replace_once(data, fetch_anchor, fetch_new, "MESSAGES one-shot sound")

    # Keep changelog local and tiny: no browser/network dependency and no new payload/resource.
    function_anchor = b'function Show-SupportMessages {'
    changelog_function = nl.join([
        b'function Show-LauncherChangelog {',
        b'    $changelog = @"',
        b'Launcher 1.16.1',
        b'',
        b'- New maintainer MESSAGES play one short notification sound when first detected.',
        b'- Added a CHANGELOG button so launcher changes are visible in-app.',
        b'- No gameplay, runtime, Engine, V7, payload, or WotR logic changes.',
        b'',
        b'Launcher 1.1.6',
        b'',
        b'- Fixed Windows PowerShell 5.1 MESSAGES comment handling and unread-state behavior.',
        b'"@',
        b'    try {',
        b'        [System.Windows.Forms.MessageBox]::Show(',
        b'            $changelog.Trim(),',
        b'            "AotR 8P WotR - Changelog",',
        b'            [System.Windows.Forms.MessageBoxButtons]::OK,',
        b'            [System.Windows.Forms.MessageBoxIcon]::Information',
        b'        ) | Out-Null',
        b'    } catch {}',
        b'}',
        b'',
    ]) + function_anchor
    data = replace_once(data, function_anchor, changelog_function, "CHANGELOG function")

    event_anchor = b'$MessagesHit.Add_MouseLeftButtonUp({ Show-SupportMessages })'
    event_new = event_anchor + nl + b'$ChangelogHit.Add_MouseLeftButtonUp({ Show-LauncherChangelog })'
    data = replace_once(data, event_anchor, event_new, "CHANGELOG click handler")

    checks = {
        b'x:Name="ChangelogHit"': 1,
        b'$ChangelogHit = $Window.FindName("ChangelogHit")': 1,
        b'function Show-LauncherChangelog {': 1,
        b'[System.Media.SystemSounds]::Asterisk.Play()': 1,
        b'$ChangelogHit.Add_MouseLeftButtonUp({ Show-LauncherChangelog })': 1,
    }
    for needle, expected in checks.items():
        count = data.count(needle)
        if count != expected:
            raise SystemExit(f"post-transform verification failed for {needle!r}: {count} != {expected}")

    path.write_bytes(data)
    print("LAUNCHER_1_16_1_UX_PATCH_PASS")
    print(f"GUI_SHA256={sha256_bytes(data)}")


if __name__ == "__main__":
    main()
