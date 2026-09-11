# Releasing

Pushing a tag like `v1.0` builds a WoW-installable zip and publishes it as a
GitHub Release (`.github/workflows/release.yml`, using
[BigWigsMods/packager](https://github.com/BigWigsMods/packager) — the
standard packaging/upload tool most WoW addons use). If CurseForge is wired
up (below), the same run also uploads the zip there.

The `.toc`'s `## Version: @project-version@` is a placeholder the packager
fills in from the tag name at build time — never hand-edit the version.

## Cutting a release

```
git tag v1.0
git push origin v1.0
```

Watch it run under the repo's **Actions** tab. Delete a bad tag with
`git tag -d v1.0 && git push origin :refs/tags/v1.0` before retagging.

## One-time CurseForge setup

1. Create the project at curseforge.com if it doesn't exist yet, named
   **Prepared**.
2. On the project's page, copy its numeric **Project ID** (sidebar, "About
   Project") and put it in `Prepared.toc`:
   ```
   ## X-Curse-Project-ID: <the number>
   ```
3. Generate an API token at <https://legacy.curseforge.com/account/api-tokens>.
4. Add it as a repo secret so the workflow can use it, without it ever
   passing through chat/logs — from a terminal you're signed into `gh` on:
   ```
   gh secret set CF_API_KEY --repo vtosh/prepared
   ```
   (pastes the token interactively), or add it via the GitHub web UI:
   **Settings → Secrets and variables → Actions → New repository secret**.

Without `CF_API_KEY` set, tagging still produces a downloadable zip on the
GitHub Release page — just not an automatic CurseForge upload.
