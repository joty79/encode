# Background Cascade Rendering Case — Resolved for Folder Background

## Resolution status

On 2026-08-29 the user visually confirmed that `Media Tools [PREVIEW]` renders
in the real Windows 11 classic menu for ordinary folder empty space. The visible
root contains `Check audio & move here`, `TS tools`, and last-positioned
`Queues`. The inline empty-`SubCommands` plus child-`shell` registration model
therefore works at `Directory\Background` on this machine. Desktop-background
visual acceptance remains pending.

## Current visual evidence

- `Media Tools [PREVIEW]` renders on the newly added `.wmv` target.
- Its visible root children are `Inspect media`, `Video`, `Audio`, and `Queues`.
- Its nested `Video` menu visibly contains `Encode video (NVIDIA H.264)` and
  `Join WMV (smart / ASFBin)`.
- The selected-folder `Media Tools [PREVIEW]` also renders.
- `Media Tools [PREVIEW]` now renders when right-clicking empty space in an
  ordinary folder.
- The final screenshot visibly contains the new preview beside the existing
  direct `Run Audio Queue` and `Run Encode Queue` verbs and the nested `System
  Tools` cascade.
- Desktop-background rendering has not yet received a final screenshot.

## Deployed locations

```text
HKCU\Software\Classes\Directory\Background\shell\MediaToolsPreview
HKCU\Software\Classes\DesktopBackground\Shell\MediaToolsPreview
```

Both appear through their merged `HKCR` paths after the successful import. There
is no same-named HKLM root. The current user is `NEOS\joty79`, SID
`S-1-5-21-3200983924-3545123182-2143991412-1001`.

The roots contain `MUIVerb` and an empty `SubCommands` REG_SZ. Children are
stored below an inline `shell` subkey. The temporary icon experiment was rolled
back. The generated source deletes only those exact `MediaToolsPreview` roots
before rebuilding them.

## Verification already completed

- The generator covers all 104 current-direct target/verb mappings.
- Missing mappings: 0.
- Extra mappings: 0.
- Legacy launcher-command mismatches: 0.
- Post-import auditor: 139 source roots, 139 live roots.
- Missing roots: 0; unexpected roots: 0; broken paths: 0; exact tree/value
  mismatches: 0.
- Elevated imports returned success through the same user/session used in the
  earlier controlled investigation.
- No current direct verb has been removed.

Registry readback is explicitly **not** treated as Explorer acceptance.

## Historical failed observations

1. Original background profiles contained only nested submenu children.
2. They were flattened so the folder background had a direct first-level
   `Check audio & move here` command and the desktop background had a direct
   first-level `Run video queue` command. Exact import/readback passed; neither
   parent rendered.
3. The exact system icon used by the visibly working `System Tools` root,
   `imageres.dll,-109`, was added to every preview root. Exact import/readback
   passed; the folder-background parent still did not render.

Therefore the direct-child and missing-icon explanations were falsified. These
observations did not prove that Explorer rejected the inline cascade model.

## Final diagnostic sequence

1. A direct live query later found the two background preview roots absent even
   though the generated `.reg` contained them. This invalidated the earlier
   assumption that the failing visual screenshots all represented the exact
   generated live state.
2. The current generated `.reg` was imported once through elevated
   `reg.exe import`, which returned exit code 0.
3. Immediate direct readback confirmed all three intended roots: folder
   background with three children, desktop background with one child, and
   selected folder with four children.
4. The exact auditor reported 139 source roots, 139 live roots, zero missing
   roots, and zero exact-tree mismatches.
5. `SHChangeNotify(SHCNE_ASSOCCHANGED)` was sent to refresh Explorer's shell
   association cache.
6. The next user screenshot visually confirmed the complete folder-background
   preview cascade.

The observed failure was therefore deployment/cache state, not rejection of
the inline cascade structure. Registry readback remains necessary but is not a
substitute for the final Explorer screenshot.

## Causal post-mortem

The fundamental process failure was stale evidence. The generated artifact,
the import that consumed it, and the live Registry were treated as if they were
one unchanged state even after additional generation/import/rollback activity.
At the moment the background menu was missing, the exact physical roots should
have been queried before considering any Shell-structure hypothesis. The
existing aggregate auditor was capable of detecting the absence, but its older
result was incorrectly reused instead of rerunning it against the failure-time
state.

The exact event that removed or failed to deploy those roots was not logged, so
it must not be invented after the fact. The strongest supported explanation is
artifact/live-state drift: the current generated file contained the roots while
the active user's physical hive did not. A single delete-first file containing
both HKLM and HKCU payloads made that state harder to reason about, but there is
no evidence on this host that elevation redirected HKCU to another user.
Normal and `gsudo --direct` identity checks both returned
`S-1-5-21-3200983924-3545123182-2143991412-1001`.

The final successful visual result occurred after both exact live readback and
`SHChangeNotify(SHCNE_ASSOCCHANGED)`. This establishes the refresh boundary in
the observed sequence; it does not prove that the notification was the only
possible way Explorer could have reloaded the association.

Final read-only evidence snapshot:

```text
CapturedAtUtc:  2026-08-29T17:12:33.4820473Z
InteractiveSID: S-1-5-21-3200983924-3545123182-2143991412-1001
ArtifactSHA256: 10BD6D1A3D5B031689B14F5A119FB803BC94B8FD602D90CFA3576931E55BC296
HKCU Directory\Background: present
HKCU DesktopBackground:     present
HKCU Directory:             present
HKCR Directory\Background: present
HKCR DesktopBackground:     present
Explorer folder background: visual pass
```

## Same-location working control

This root visibly renders in the same folder-background menu:

```text
HKCU\Software\Classes\Directory\Background\shell\SystemTools
    MUIVerb    REG_SZ    System Tools
    Icon       REG_SZ    imageres.dll,-109
    SubCommands REG_SZ   <empty>
    shell\...
```

The failing root uses the same hive, association location, value types, icon,
empty `SubCommands`, and inline child `shell` pattern. Compare the complete live
trees rather than assuming the shared root values prove equivalence.

## Relevant prior controlled evidence

- A fresh agent-created nested cascade under
  `HKCU\Software\Classes\Directory\shell` rendered in the real classic menu
  without Explorer restart or `SHChangeNotify`.
- The earlier hypothesis that agent-side imports inherently cannot produce
  visible menus was disproved.
- A rapid sequential `gsudo` credential-cache race was observed historically,
  but these imports completed and exact live state is present; do not reuse the
  cache-race explanation without new evidence.

## Registration-model conclusion

- Microsoft documents `SubCommands` as a semicolon-delimited verb list backed
  by `CommandStore`:
  https://learn.microsoft.com/en-us/windows/win32/shell/how-to--create-cascading-menus-with-the-subcommands-registry-entry
- Microsoft documents inline/nested custom verbs below an
  `ExtendedSubCommandsKey` **subkey** and requires the parent default value to
  remain unset:
  https://learn.microsoft.com/en-us/windows/win32/shell/how-to-create-cascading-menus-with-the-extendedsubcommandskey-registry-entry
- The project and the working `System Tools` control currently use the common
  but not explicitly documented empty-`SubCommands` plus inline-`shell` pattern.

The final folder-background screenshot disproves the hypothesis that this
namespace requires `ExtendedSubCommandsKey`. No structural migration is needed
to solve the observed rendering problem. The existing inline model is retained
for the preview while visual and launcher acceptance continues. Do not claim
success for the remaining desktop-background target from Registry output alone;
require its real Explorer menu.
