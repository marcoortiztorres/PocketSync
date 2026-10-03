# Project notes

Track proposals and the reasons behind decisions here. Label each item as
Proposed, Accepted, Implemented, or Deferred. Acceptance means the direction
is agreed; it does not mean the feature is implemented. When work is completed,
update its status and add an entry to the [changelog](../CHANGELOG.md).

## 2026-09-19 — Collapsible song/video search

**Status:** Implemented — authorized and completed on 2026-09-19.

**Problem:** Find a song or video quickly without permanently adding a search
field to the app's compact layout.

**Requested interaction:** Search starts hidden. Clicking a magnifying glass
reveals the field. Clicking × clears the query and hides the field in one action.
Use this interaction in both the main page's song queue and the menu page's
selected video panel.

**Implemented approach:**

- Reuse a collapsible search control and a shared matching function, with a
  separate query for each page.
- Filter immediately by partial words, ignoring case and accents. Allow multiple
  search terms in any order across title, uploader/channel, tags, and filenames.
- Replace the decorative sparkle in those two panel headers with the search
  icon. Reveal the field above each list while keeping panel height fixed.
- Focus the field when opened; support Escape to clear and close; show a
  no-results message when appropriate.
- Filter displayed rows without changing playback order, shuffle, or selection.
  Preserve original queue positions in row numbering.

**Why:** Sharing the control and matching rules keeps both searches consistent
and makes later search improvements available in both places. Keeping the panel
height fixed limits layout movement, particularly in the narrower menu column.

**Estimated effort:** 3–5 hours for both locations, including styling, keyboard
behavior, matching tests, and layout/selection/playback checks. This is an
initial code-based estimate, subject to layout verification.

**Validation when implemented:** Check open/close and focus behavior, blank and
no-result queries, case/accent/multiword matching, original queue numbering,
selection and playback while filtering, and fit in the menu's narrow panel.

**Completed validation:** The macOS Debug build succeeded. Search tests passed
for blank queries, partial words, case/accent handling, terms across fields,
filenames, and missing matches. Playback and selection still use the original
records and IDs; filtering is local to the shared list. Interactive visual and
keyboard checks in the running app remain to be performed.
