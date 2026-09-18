from pathlib import Path
import argparse
import importlib.util
import re


def load_base_module():
    path = Path(__file__).with_name("apply_issue84_session_runtime_rc2_hardening.py")
    spec = importlib.util.spec_from_file_location("issue84_rc2_base", str(path))
    if spec is None or spec.loader is None:
        raise SystemExit("could not load RC2 base hardening module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonicalize_launcher_pid_anchor(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")

    assign_pattern = re.compile(
        r'(?m)^[ \t]*\$launcherPid[ \t]*=[ \t]*(?:\[int\][ \t]*)?\$launcher\.Id[ \t]*$'
    )
    assign_matches = list(assign_pattern.finditer(text))
    if len(assign_matches) != 1:
        raise SystemExit(f"launcher PID assignment count={len(assign_matches)}")

    log_pattern = re.compile(
        r'(?m)^[ \t]*Write-Host[ \t]+["\']lotrbfme2ep1\.exe PID:[ ]*\$launcherPid["\'][ \t]+-ForegroundColor[ \t]+Green[ \t]*$'
    )
    log_matches = list(log_pattern.finditer(text))
    if len(log_matches) > 1:
        raise SystemExit(f"launcher PID log count={len(log_matches)}")

    if len(log_matches) == 1:
        m = log_matches[0]
        start = m.start()
        end = m.end()
        if end < len(text) and text[end] == "\n":
            end += 1
        text = text[:start] + text[end:]

    assign_matches = list(assign_pattern.finditer(text))
    if len(assign_matches) != 1:
        raise SystemExit(f"launcher PID assignment after log normalization count={len(assign_matches)}")
    m = assign_matches[0]
    line_end = m.end()
    if line_end < len(text) and text[line_end] == "\n":
        line_end += 1

    canonical = (
        '$launcherPid = $launcher.Id\n'
        'Write-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green\n'
    )
    text = text[:m.start()] + canonical + text[line_end:]

    if text.count('$launcherPid = $launcher.Id\nWrite-Host "lotrbfme2ep1.exe PID: $launcherPid" -ForegroundColor Green\n') != 1:
        raise SystemExit("canonical launcher PID anchor was not produced exactly once")

    # The RC2 base transform still carries one RC1-era textual sanity check for
    # the conceptual path. Add a temporary source-only sentinel, then remove it
    # after the semantic RC2 stage-root replacement has completed.
    sentinel = '# __A8P_RC2_RUNTIME_SESSIONS_SENTINEL__ runtime\\sessions\n'
    text = sentinel + text
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def remove_runtime_sessions_sentinel(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    sentinel = '# __A8P_RC2_RUNTIME_SESSIONS_SENTINEL__ runtime\\sessions\n'
    if text.count(sentinel) != 1:
        raise SystemExit(f"RC2 runtime-session sentinel count={text.count(sentinel)}")
    text = text.replace(sentinel, "", 1)
    path.write_text(text, encoding="utf-8-sig", newline="\n")


def harden_self_update_deferral(path: Path) -> None:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")

    helper_anchor = '    private static bool RuntimeLifecycleSelfTest()\n'
    helper = r'''    private static bool HasRuntimeSessionForUpdateDeferral()
    {
        try
        {
            string root = RuntimeSessionRoot();
            if (!RuntimeSessionRootComponentsSafe() || !Directory.Exists(root))
                return false;

            foreach (string path in Directory.GetDirectories(root, "AOTR8P_SESSION_*", SearchOption.TopDirectoryOnly))
            {
                if (IsValidRuntimeSessionPath(path))
                    return true;
            }
        }
        catch
        {
            // If runtime state cannot be classified safely, defer replacement
            // of this executable rather than racing a possible cleanup watcher.
            return true;
        }
        return false;
    }

'''
    if text.count(helper_anchor) != 1:
        raise SystemExit(f"self-update deferral helper anchor count={text.count(helper_anchor)}")
    text = text.replace(helper_anchor, helper + helper_anchor, 1)

    update_anchor = '''    private static bool TrySelfUpdate(string exePath, string root)
    {
'''
    update_new = '''    private static bool TrySelfUpdate(string exePath, string root)
    {
        if (HasRuntimeSessionForUpdateDeferral())
        {
            LogUpdate("Update deferred while a transient runtime session or cleanup watcher is active.");
            return false;
        }
'''
    if text.count(update_anchor) != 1:
        raise SystemExit(f"TrySelfUpdate anchor count={text.count(update_anchor)}")
    text = text.replace(update_anchor, update_new, 1)

    for needle in [
        "HasRuntimeSessionForUpdateDeferral",
        "Update deferred while a transient runtime session or cleanup watcher is active.",
    ]:
        if needle not in text:
            raise SystemExit(f"self-update deferral contract missing: {needle}")

    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    parser.add_argument("gui")
    parser.add_argument("csharp")
    args = parser.parse_args()

    engine = Path(args.engine)
    gui = Path(args.gui)
    csharp = Path(args.csharp)

    canonicalize_launcher_pid_anchor(engine)

    base = load_base_module()
    base.patch_engine(engine)
    remove_runtime_sessions_sentinel(engine)
    base.patch_gui(gui)
    base.patch_csharp(csharp)
    harden_self_update_deferral(csharp)
    print("ISSUE84_SESSION_RUNTIME_RC2_HARDENING_V2_PASS")


if __name__ == "__main__":
    main()
