# TS Context-Menu Registry Investigation

## Scope

This document records the controlled Windows 11 investigation performed on
2026-08-27 for the `Analyze TS timestamps` Explorer actions owned by:

```text
Video\Repair-TsTimestampRemux.reg
```

The investigation began after Registry imports and Explorer refresh commands
reported success while the visible context-menu label did not change. The goal
was to separate Registry state from actual Explorer behavior. The exact cause
of those original stale-label observations remains unresolved, but the later
controlled tests recorded below disprove an agent-versus-user import
restriction.

## 2026-08-29 Resolution Addendum

Two fresh-key tests closed the execution-context question:

1. An agent-only import created unique flat verbs under machine-wide `.mp4` and
   per-user selected-folder locations. The user confirmed both in the real
   classic Explorer menu.
2. A second agent-only import created a fresh per-user selected-folder cascade
   named `Media Tools [CLAUDE CASCADE TEST]`, using `SubCommands=""` and two
   child verbs. The user screenshot confirmed the parent and both children.

Neither test used a user-run import, Explorer restart or `SHChangeNotify`.
Pre-test absence, post-import Registry state and post-test cleanup were all
verified. The temporary flat and cascade probe keys are absent from both their
direct locations and the merged `HKCR` view.

Therefore, agent-initiated Registry imports can create visible flat and nested
Explorer verbs on this machine. The earlier observation did **not** prove an
execution-context restriction. Its exact cause remains unresolved. The folder
preview root was new during its original non-appearance, so stale duplicate
children cannot explain that first result.

Later, after several revisions reused the same preview root and renamed/reordered
its children, the installed selected-folder cascade accumulated stale duplicate
branches because Registry imports do not delete omitted keys. This was a
separate cleanup problem, not the cause of the original non-appearance. A
single re-import of the now-idempotent preview source removed those branches.
Registry readback then showed exactly `01_Inspect`, `10_Process`, `20_TsTools`
and `30_Queues`, with `Queues` last.

## Production State

The committed production label is:

```text
Analyze TS timestamps
```

Temporary labels such as `[REG-COMMAND-TEST]`, `[AGENT-COMMAND-TEST]` and
`[SINGLE-FILE-AGENT-TEST]` were used only for the controlled experiment and are
not retained in the `.reg` file.

The relevant registrations are:

```text
HKLM\Software\Classes\SystemFileAssociations\.ts\shell\AnalyzeTsTimestamps
HKCU\Software\Classes\Directory\shell\AnalyzeTsTimestamps
HKCU\Software\Classes\Directory\Background\shell\AnalyzeTsTimestamps
```

The two folder registrations are `Shift`-only. The `.ts` file registration is
a normal verb and does not require `Shift`.

## Confirmed Evidence

### Registry audit

- `reg.exe import` and `regedit.exe /s` returned exit code `0` during the agent
  tests.
- Raw `HKLM`, `HKCU` and merged `HKCR` readback showed the temporary labels that
  had just been imported.
- Both 64-bit and 32-bit Registry views agreed for the `.ts` file verb.
- Registry Finder 2.62 searched the relevant hives in seconds and found no
  duplicate or stale TS label registration.
- No `MUIVerb` value exists under the `.ts` analysis verb; Explorer therefore
  was not preferring a stale `MUIVerb` over the default value.
- The `.reg` file association remained the Windows default:

  ```text
  regedit.exe "%1"
  ```

- The Codex command host and its elevated `gsudo --direct` child used the same
  user SID as Explorer, Windows session 1 and a 64-bit process. The elevated
  child was confirmed elevated.
- The command host had no package identity and was not an AppContainer, so the
  observed discrepancy was not explained by ordinary MSIX/AppContainer Registry
  virtualization.

Registry readback proves what a Registry API view contains. It does **not**
prove that Explorer is rendering the same label.

### Shift-only folder verb

The following A/B result was reproduced with the user observing the real
Explorer menu:

1. The user ran this command in an interactive PowerShell window:

   ```powershell
   gsudo.exe --direct reg.exe import 'D:\Users\joty79\scripts\encode\Video\Repair-TsTimestampRemux.reg'
   ```

2. The visible folder label changed to `[REG-COMMAND-TEST]` without an Explorer
   restart.
3. The `.reg` source was changed to `[AGENT-COMMAND-TEST]` and the agent ran the
   same command. It returned success and Registry readback changed, but Explorer
   continued to show `[REG-COMMAND-TEST]`.
4. An agent-side `SHChangeNotify(SHCNE_ASSOCCHANGED)` did not update the visible
   menu.
5. The user ran the same `gsudo reg.exe import` command again. Explorer then
   displayed `[AGENT-COMMAND-TEST]` immediately.

This was the original observation. The fresh-key tests in the resolution
addendum show that it does not prove a general execution-context difference.

### Normal `.ts` file verb

The file verb behaved differently:

1. The agent imported `[SINGLE-FILE-AGENT-TEST]`. Raw `HKLM` and merged `HKCR`
   readback showed that label, but Explorer still displayed the production
   `Analyze TS timestamps` label.
2. The user ran the same interactive `gsudo reg.exe import`; the visible file
   label still did not change.
3. The user launched the `.reg` file through its normal interactive Registry
   Editor Yes/OK path; the visible file label still did not change.
4. A synchronous
   `SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_FLUSH, ...)` call also had no visible
   effect.

The file-verb result therefore cannot be explained only by agent versus user
command context. It is consistent with an Explorer file-association/verb cache,
but the exact cache and invalidation rule remain unproven.

## What Is Not Proven

- A successful `.reg` import is not proof of visible Explorer deployment.
- Registry Finder, `reg.exe query`, merged `HKCR` reads and Shell COM verb
  enumeration are supporting evidence only.
- `SHChangeNotify`, including `SHCNF_FLUSH`, did not solve the reproduced file
  label case.
- Multiple Explorer processes were present, but a generic "stale Explorer
  process" explanation is insufficient: the user had already performed a full
  scripted Explorer restart during an earlier failed rename attempt, while a
  later interactive import changed the folder label without another restart.
- The copied clean TS fixtures used by performance work do not test broken-file
  detection or repair.

## Historical Continuation Checklist

The first item below was completed by the 2026-08-29 flat-verb and cascade
tests. The remaining items are retained only if the stale-label behavior needs
deeper diagnosis later. Use a fresh, unique marker for every step and inspect
file and folder menus separately.

1. **Test a new internal verb key instead of renaming the existing key.** Add a
   temporary `AnalyzeTsTimestampsProbe` key with a unique visible label. If a
   newly-created verb appears while an existing verb rename remains stale, that
   explains why initial registrations succeeded but later renames did not.
2. **Compare raw views before user-side import.** Immediately after an
   agent-side import, capture `HKCU\Software\Classes`, the corresponding
   `HKEY_USERS\<SID>_Classes` view, `HKLM\Software\Classes`, and merged `HKCR`
   before running any user command.
3. **Test Registry Finder import separately.** Registry Finder 2.62 exposes
   `--import <file>` and `--importSilent`; use a new marker so its behavior is
   not confused with a previous import.
4. **Trace Explorer Registry reads if Process Monitor is already available and
   its EULA has already been accepted by the user.** Filter on `explorer.exe`,
   `AnalyzeTsTimestamps`, and `.ts` while opening the actual menu. Do not accept
   an EULA automatically.
5. **Treat a sign-out or reboot as a separate disruptive cache test.** Obtain
   immediate permission first and record the label before and after. Do not use
   it as a substitute for identifying which invalidation path failed.
6. **Require real Explorer evidence.** Record the exact target type, whether
   `Shift` was held, the unique marker, the importing process and the visible
   result. Do not close the incident from Registry readback alone.

## Acceptance Rule

A context-menu label change is accepted only when the intended label is visible
in the real Explorer menu for the intended target type. Registry state and
command exit code must be reported separately from that visual result.
