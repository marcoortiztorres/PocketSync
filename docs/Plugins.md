# Experimental local plugins

PocketSync's core imports local media, edits metadata, converts videos, and syncs
files. Optional plugins can supply a video and its metadata through a generic
process interface. No provider-specific downloader is bundled with the app.

## Install and use

Open Station → plugins → open folder. Put each plugin in its own subfolder, then
choose reload. Select a plugin, enter its input, and click Run plugin. A successful
import appears in the library with its metadata already populated; select the
video and use the existing conversion controls. Errors appear in the activity log.
Cancel stops the current import and removes incomplete output.

- Debug builds use `Plugins.local/` at the project root. This entire folder is
  ignored by Git and is outside the app source folder, so its contents are not
  bundled. Do not force-add private plugins to Git.
- Release builds use `Plugins/` inside the app's application-support directory.
  The Open folder button finds the exact location; no project checkout is needed
  for plugin discovery there.
- Discovery reads manifests without executing anything. Adding a plugin does not
  run it automatically. Invalid plugins are listed with an error.

Plugins are trusted local executable programs, **not sandboxed extensions**.
The manifest's permissions are disclosures, not operating-system access controls.
A plugin runs with the user's access to files and network. Path validation protects
library bookkeeping; it does not constrain a malicious executable. Only install
and run programs you trust. No plugin marketplace, signing, automatic updates,
or permissions-enforcement system is implemented.

## Folder format

Each plugin folder contains `manifest.json` and an executable with its executable
bit set. Script interpreters and other dependencies must already be installed.
Executable paths are relative to the plugin folder; traversal and symlink escapes
are rejected. Identifiers must be unique among installed plugins.

Example manifest (the example executable is a placeholder, not bundled):

```json
{
  "identifier": "example.media-import",
  "name": "Example Media Importer",
  "version": "0.1.0",
  "protocolVersion": 1,
  "executable": "import-media",
  "capabilities": ["import"],
  "permissions": ["write-import-output"]
}
```

Add `access-network` or `launch-external-process` if used. The other declared
permissions are `read-selected-files`, `access-removable-media`, and
`access-browser-session`. Browser-session access should be explicitly configured
by the user and must not export session cookies into library files or logs.

## Protocol v1

The executable runs with its plugin folder as its working directory, without shell
interpolation or command-line input. It reads one JSON request from stdin to EOF:

```json
{
  "protocolVersion": 1,
  "requestID": "A32BB900-8BB7-4503-987A-364DA69E4C07",
  "operation": "importMedia",
  "inputLocators": ["plugin-specific input"],
  "options": {},
  "outputDirectory": "/absolute/path/assigned-by-host"
}
```

Return exactly one JSON response on stdout, with the same request ID and protocol
version. Send diagnostics to stderr. Dates use ISO 8601 UTC strings such as
`2026-09-06T12:00:00Z`. The source of truth for fields and enum values is
`PluginModels.swift` and `VideoModels.swift`.

```json
{
  "protocolVersion": 1,
  "requestID": "A32BB900-8BB7-4503-987A-364DA69E4C07",
  "succeeded": true,
  "candidates": [{
    "sources": [{
      "id": "0F120970-2541-477D-A89D-061670EC8FE5",
      "kind": "plugin",
      "locator": "plugin-specific input",
      "addedAt": "2026-09-06T12:00:00Z"
    }],
    "metadata": {
      "title": "Example video",
      "origin": "plugin",
      "uploader": "Example creator",
      "publishedDate": "20260906",
      "durationSeconds": 12
    },
    "assets": [{
      "id": "6610A1EC-A424-4FEE-9968-8C5EA6D4C8C0",
      "role": "master",
      "path": "/absolute/path/assigned-by-host/video.mp4",
      "formatIdentifier": "mp4",
      "storageKind": "managed",
      "createdAt": "2026-09-06T12:00:00Z"
    }]
  }],
  "messages": []
}
```

Supported imports contain exactly one candidate, at least one source, a nonempty
title, and exactly one nonempty regular master file inside the assigned output
directory. `summary`, `channel`, `tags`, `thumbnailURL`, and other optional metadata
fields are also supported. The host sets plugin provenance and managed ownership.
The host validates the file's location and existence, not its media codec.

For failure, return `succeeded: false`, `candidates: []`, `messages: []`, and an
`errorMessage`. A nonzero process exit is also a failure. Stdout and stderr are
limited to 8 MB each; execution times out after 30 minutes. The host sends SIGTERM,
then SIGKILL after a two-second grace period. Plugins that spawn subprocesses must
terminate and reap them on SIGTERM; the host does not isolate process trees.

Failed/cancelled requests remove the run directory. Successful output remains in
application support under `Media/PluginImports/<run UUID>/` and is owned by the
library. Write only the final master file there; use temporary storage for other
work. Plugins never edit the library database directly. Repeated exact source
inputs for the same plugin are skipped before execution.

## Deliberately unfinished

The manifest models reserve metadata, conversion, export, playback, and library
operations. These remain intentional scaffolding, not implemented capabilities.
Before extending the protocol, add operation-specific validation and tests.
Future work includes metadata-only plugins, batch imports, structured progress
(current `messages` is reserved), portable installation/dependency UX, and a
proper trust/update model. Protocol v1 is experimental, not a stable public SDK.

## Validation

Run `Tests/run-plugin-tests.sh` on a Mac with Xcode command-line tools and
`/usr/bin/python3`. The generic fixture needs no provider dependencies or network.
It tests discovery, metadata, output ownership, malformed/mismatched responses,
path escape rejection, rollback, cancellation, timeouts, and provider identity.
