# The plugin manifest `skills` array is the stable set is out of scope

- Decided: 2026-09-30 · by the maintainer
- Holds while: the manifest key is additive, not a filter

## The concept

List the promoted skills explicitly in the plugin manifest's `skills` array, so the
plugin loads exactly the stable set and the beta skills stay invisible to users.

## Why not

The key is a subset that can only add to what the plugin root already exposes. A
directory that is not listed is still scanned, so the array cannot exclude anything;
it is a second list of names to keep in step with the files, while the stage
metadata and the generated index already say which skill is which stage. The
stable set is shown, not enforced by omission.

- the fact behind it: the manifest's `skills` is an array of directory paths,
  documented as a subset, while the root is scanned in full (see `doc/HARNESSES.md`)
- what carries the stage today: `metadata.stage` in each skill's frontmatter, and
  the skill table in `README.md`

## Prior requests

- 2026-09-30 (planning pass): adopt an explicit array as the promoted set, the way the
  neighbouring repo gates its plugin contents.
- 2026-09-30 (planning pass, same day): keep the array out and let the stage metadata
  plus the index carry it.

## Reopen when

A harness is found where the array excludes what the root exposes, cited the way
`doc/HARNESSES.md` cites a cell. Then the array is a real filter on that harness
and gets generated from the same stage metadata, never hand-kept.
