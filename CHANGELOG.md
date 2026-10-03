# Changelog

Record completed changes here, newest first. Each entry should explain what
changed, why it changed, and how it was checked. Use an `Unreleased` section
until changes are included in a named release. Keep proposals in
[Project notes](docs/ProjectNotes.md) so they are not mistaken for shipped features.

## Unreleased

### 2026-09-28

- **Avoid repeated migration writes on launch.** An already migrated library
  is loaded without rewriting its catalog or unchanged startup location pointer.
  Storage regression tests verify unchanged modification times and no extra
  backups after a normal launch and refresh.

- **Store the active catalog and backups with the media library.** Startup
  migrates the existing catalog into the selected folder as `video_index.json`,
  copying catalog backups into `Backups` and retaining the previous catalog for
  recovery. Library moves now transfer both media and catalog backups, reject
  conflicting catalogs, and redirect existing readers to the new catalog.
  Managed paths rebase when a copied catalog is loaded beside its matching
  library marker. Application Support retains the startup location pointer and
  the legacy recovery copy. Referenced files outside the folder remain external.
  Validation: storage migration/move regression tests, plugin tests, search tests,
  and macOS Debug build passed. Live-library migration was not run.

### 2026-09-19

- **Added collapsible video search to the song queue and menu selected video
  panel.** Click the magnifying glass to reveal and focus search; × or Escape
  clears and closes it. Results match partial words across titles,
  uploader/channel, tags, and filenames, ignoring case and accents. Multiple
  terms can match in any order. Both panels reuse the same control and matcher
  to keep behavior consistent. Panel heights stay fixed, original queue numbers
  are preserved, and filtering leaves playback order and selection intact.
  Validation: macOS Debug build succeeded; automated matching tests passed.
  Interactive visual and keyboard checks in the running app remain pending.

- **Added project change tracking.** Created this changelog for completed work
  and project notes for proposals and decisions, so the reasons behind changes
  remain available outside conversations. Documentation only; no app behavior
  changed. Checked that the files and their relative links exist.

Earlier features have not been backfilled: this checkout has no Git commits
yet, so a verified implementation timeline is not available.
