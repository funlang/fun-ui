# Releasing fun-ui

Maintainer checklist for cutting a release.

**English** (this file) - [简体中文](RELEASING.zh.md)

## 1. Prepare

- Make sure `.github/workflows/ci.yml` is green on `master` (both
  `linux-loopback` and `linux-webkitgtk`).
- Move the `Unreleased` entries in `CHANGELOG.md` under the new version with
  today's date, and leave an empty `## [Unreleased]` section above it.
- Update the version in `README.md` and `README.zh.md`.
- Commit the three files as `release: fun-ui X.Y.Z`.

## 2. Tag with a summary, never a bare tag

GitHub renders the annotated tag message as the release page body when the
release has no description. A title-only (or lightweight) tag therefore leaves
the published release page blank.

Every release tag is an **annotated** tag with this shape:

```text
fun-ui X.Y.Z

<one-line theme for the release>

Highlights since v<previous>:

- <2-6 prose bullets, one per user-visible change group>

Full list: CHANGELOG.md.
```

Write the message to a file and tag from it, so the body keeps its blank lines
and wrapping:

```bash
git tag -a -F /tmp/vX.Y.Z.txt vX.Y.Z
git push origin master
git push origin vX.Y.Z
```

- Tag the release commit, not a later one.
- Push the tag explicitly. `git push --tags` also pushes unrelated or stale
  tags.
- Check the result before publishing: `git tag -n99 -l vX.Y.Z`.
- For a point release, keep the note short but still name the bug and the
  observable fix.

## 3. Publish

- Create the GitHub release for the pushed tag.
- Leave the description empty (or paste the same summary) so the tag annotation
  is what readers see.
- Open the release page and confirm the notes render.

## Repairing a published tag

If a tag was published without a summary:

```bash
git update-ref refs/tags-backup/vX.Y.Z vX.Y.Z
git tag -f -a -F /tmp/vX.Y.Z.txt vX.Y.Z vX.Y.Z^{commit}
git push origin vX.Y.Z --force
```

- Keep the commit unchanged: force-update only the annotation.
- The local `refs/tags-backup/*` ref preserves the old tag object.
- Anyone who already fetched the old tag may see a "tag changed" notice on the
  next fetch. Code is not moved.
