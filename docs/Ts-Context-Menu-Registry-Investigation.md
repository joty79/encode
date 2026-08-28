# TS Context-Menu Registry Investigation

## Scope

This document records the controlled Windows 11 investigation performed on
2026-08-27 and 2026-08-28 for the Explorer actions owned by:

```text
Video\Repair-TsTimestampRemux.reg
```

The investigation began after Registry imports reported success while real
Explorer continued to render an older label. The operational root cause and a
working deployment path are now proven. The exact Windows component that owns
the shared Shell cache is not identified.

## Production State

The committed and live production label is:

```text
Analyze TS timestamps
```

Temporary labels such as `[REG-COMMAND-TEST]`, `[AGENT-COMMAND-TEST]`,
`[SINGLE-FILE-AGENT-TEST]`, `[CODEX-NEWKEY-*]`, `[CODEX-RF-*]` and
`[CODEX-MUI-*]` were used only for controlled experiments. None remain in the
production `.reg` artifact or live Registry.

The production registrations are:

```text
HKLM\Software\Classes\SystemFileAssociations\.ts\shell\AnalyzeTsTimestamps
HKCU\Software\Classes\Directory\shell\AnalyzeTsTimestamps
HKCU\Software\Classes\Directory\Background\shell\AnalyzeTsTimestamps
```

The two folder registrations are `Shift`-only. The `.ts` file registration is
a normal verb and does not require `Shift`.

## Proven Root Cause

Windows Shell caches static context-menu verb descriptors separately from the
Registry state that `reg.exe`, Registry Finder and merged `HKCR` expose. The
cache behavior differs by association class on this host:

- For `SystemFileAssociations\.ts`, changing the default value of an existing
  internal verb key can remain stale, while a newly named verb key is discovered
  immediately.
- For `Directory\shell` and `Directory\Background\shell`, the cached entry and
  internal key identity can survive deletion of the source key, creation of a
  replacement key, new Explorer folder-window processes and an Explorer
  restart.
- An import run from the Codex execution host updates raw Registry views but
  does not invalidate those cached folder descriptors.
- The same `gsudo.exe --direct reg.exe import ...` command run by the user in an
  interactive PowerShell invalidates the folder/background cache and updates
  the visible labels without another restart.

The responsible cache is therefore outside the Registry readback path and is
not confined to one Explorer folder process. `ShellHost.exe` and `sihost.exe`
survived the controlled Explorer restart and are possible owners or
participants, but that attribution is not proven.

## Known-Good Deployment

Run the import from the user's interactive PowerShell session:

```powershell
gsudo.exe --direct reg.exe import 'D:\Users\joty79\scripts\encode\Video\Repair-TsTimestampRemux.reg'
```

Then verify all three real Explorer surfaces:

1. Right-click a `.ts` file and confirm `Analyze TS timestamps`.
2. Hold `Shift`, right-click a folder and confirm `Analyze TS timestamps`.
3. Hold `Shift`, right-click an empty area inside a folder and confirm
   `Analyze TS timestamps`.

Exit code and Registry readback are supporting checks. They are not acceptance
evidence. On this host, an agent-side import and an Explorer restart are not
substitutes for the proven interactive import path.

This procedure is proven for restoring the current production registration. It
does not prove that a future in-place rename of the existing `.ts` verb key will
refresh without a new internal key or a broader Shell-session reset.

## Controlled Evidence

### Registry and process audit

- Raw `HKLM`, `HKCU`, `HKEY_USERS\<SID>_Classes` and merged `HKCR` views agreed
  after every import.
- Both 64-bit and 32-bit Registry views agreed for the `.ts` file verb.
- Registry Finder 2.62 searched approximately 486,000 keys and 855,000 values
  after production restoration and found no remaining
  `AGENT-COMMAND-TEST` Registry data.
- No duplicate label, `MUIVerb`, 32/64-bit mismatch, wrong SID/session,
  AppContainer or package identity explained the discrepancy.
- `SeparateProcess` was `0`, but Windows still created distinct Explorer
  processes for the controlled folder windows.

### Existing-key cache versus new-key discovery

The `.ts` file baseline displayed production `Analyze TS timestamps` while raw
`HKLM` and merged `HKCR` contained `[SINGLE-FILE-AGENT-TEST]`.

A new temporary key named `AnalyzeTsTimestampsProbe20260828A` was then created
alongside the existing `.ts` verb. In the same Explorer process and without a
restart or notification call, the real menu immediately displayed both:

```text
Analyze TS timestamps
[CODEX-NEWKEY-FILE-20260828-A]
```

This proves that existing-key label caching and new-key discovery are distinct
for `SystemFileAssociations\.ts`.

For `Directory` and `Directory\Background`, the equivalent new key was present
in raw HKCU, `HKEY_USERS\<SID>_Classes` and merged HKCR, but did not appear in
the real Shift menu. Deleting the legacy key did not remove its cached menu
entry. A newly launched Explorer window process still displayed the deleted
legacy label.

### Invalidation paths that did not work

None of the following changed the visible cached folder labels:

- agent-side `gsudo.exe --direct reg.exe import ...`;
- Registry Finder `--importSilent`;
- `SHChangeNotify(SHCNE_ASSOCCHANGED)`;
- the documented synchronous
  `SHCNE_ASSOCCHANGED + SHCNF_DWORD | SHCNF_FLUSH` call followed by a one-second
  wait;
- adding a new explicit `MUIVerb`;
- deleting the existing verb key and creating a new internal key;
- closing and reopening the controlled folder window;
- restarting Explorer.

The normal Registry Editor Yes/OK import also failed earlier to refresh the
existing `.ts` file-verb label. That was a file-association result, not a
separate folder-cache test.

Microsoft documents `SHChangeNotify(SHCNE_ASSOCCHANGED)` as the supported
association-change notification, but it did not invalidate this reproduced
folder-label cache on the host:

- [File Types](https://learn.microsoft.com/en-us/windows/win32/shell/fa-file-types)
- [SHChangeNotify](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shchangenotify)

Process Monitor was not used. Only its app-execution alias was present and no
accepted-EULA state existed; no agent accepted legal terms on the user's
behalf.

### User-interactive A/B result

After production Registry restoration, the user restarted Explorer. The real
`.ts` file menu displayed production correctly, but both Shift-only folder
menus still displayed `[AGENT-COMMAND-TEST]` even though all raw views showed
production.

The user then ran the known-good import command in an interactive PowerShell.
No Explorer process was restarted between the before and after captures:

| Target | Explorer PID | Before interactive import | After interactive import |
| --- | ---: | --- | --- |
| Folder | 6252 | `Analyze TS timestamps [AGENT-COMMAND-TEST]` | `Analyze TS timestamps` |
| Folder background | 9484 | `Analyze TS timestamps [AGENT-COMMAND-TEST]` | `Analyze TS timestamps` |

The `.ts` file menu had already passed in Explorer PID 6252 with production
`Analyze TS timestamps`. Final raw Registry readback also showed production in
HKCU, `HKEY_USERS\<SID>_Classes`, HKLM and merged HKCR.

## Gemini 3.7 Secondary Review

Gemini 3.7 Flash High was consulted through the existing approved Antigravity
CLI in read-only plan mode. Its suggestions were treated as untrusted
hypotheses:

- The new-internal-key discriminator was useful and produced the decisive
  `.ts` evidence.
- The desktop/session-notification hypothesis was contradicted by the earlier
  normal interactive Registry Editor import failure.
- The suggested `MUIVerb` workaround failed the real folder-menu test.
- A modern-versus-classic menu explanation was not needed: all acceptance
  captures used the real legacy menu reached through Shift-right-click.

Gemini did not edit the Encode repository or change Windows state.

## Acceptance Rule

A context-menu deployment is accepted only when the intended production label
is visible in the real Explorer menu for the intended target type. Registry
state, process exit codes, Shell enumeration and notification calls must be
reported separately from that visual result.

If the discrepancy returns, use a fresh unique marker and preserve this order:

1. capture raw HKCU, `HKEY_USERS\<SID>_Classes`, HKLM and HKCR views;
2. capture the real menu before deployment;
3. run the import from the user's interactive PowerShell;
4. capture the same menu again without restarting Explorer;
5. use Process Monitor only if it is already installed and the user has
   explicitly accepted its EULA.
