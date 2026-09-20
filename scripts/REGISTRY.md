# Script registry

The vetted subset of `git@github.com:Univers42/scripts.git`, pinned to
`2bb05b4f819c7f231ff00fb45cfe0d427af0f399` (`main`, 2026-09-20).

`.claude/tools/scripts.sh` reads the table below and will run **only** what is in it.
Nothing is copied into this repo; the cache lives in `.claude/cache/scripts/` and is
fetched on first use.

## Why the `Runner` column exists

Upstream is useful code with a packaging problem. Measured at the pinned sha:

- 44 of 56 top-level scripts open with the 42 header block **instead of** a shebang, so
  `./script.sh` runs under whatever shell is current rather than the one it was written
  for.
- Only 11 of 149 tracked files carry the executable bit.
- `norminette.sh` is Python. `comptree.sh` is internally `show-branch-diff.sh`.
- `README.md` is 0 bytes — there is no upstream documentation of any of this.

So `scripts.sh` never executes a file directly. It invokes
`<runner> <file> <args>` using the interpreter named here, which is what makes the
above harmless. The table is also the review record: an entry means someone read the
script and ran it.

---

## Vetted

| name | runner | file | does | args | exit |
|---|---|---|---|---|---|
| `strip-comments` | `python3` | `strip_comments.py` | Strip comments from a source tree in any language; dry-run by default | `[paths...] [--apply] [--keep-header] [--keep-todo] [--stats]` | 0 ok |
| `header-cycles` | `python3` | `check_header_cycles.py` | Detect `#include` cycles across a C/C++ header tree | `<dir>` | 0 ok, 1 cycle found |
| `valgrind-check` | `bash` | `valgrind_check.sh` | Compile every `.c` under a path and run it under valgrind | `<src-dir> <out-exe>` | 0 clean, 1 misuse or leak |
| `norm-check` | `python3` | `norminette.sh` | 42 norm wrapper over a C/C++ tree, coloured diff output | `[path]` | 0 clean |
| `leaks-check` | `python3` | `leaks_check.py` | Parse valgrind output into a readable leak report | `<valgrind-log>` | 0 ok |
| `gen-password` | `bash` | `generate_password.sh` | Emit one bcrypt hash, suitable for a preseed or a fixture | *(none)* | 0 ok |
| `disk-monitor` | `bash` | `disk_space_monitor.sh` | Warn when `/` is over threshold; silent when under | *(none)* | 0 always |
| `sysinfo` | `bash` | `system_info_report.sh` | Uptime, disk and memory in one block | *(none)* | 0 ok |
| `branch-diff` | `bash` | `comptree.sh` | Compare two git branches; optional fetch and three-dot diff | `<branchA> <branchB> [--fetch] [--three-dot]` | 0 ok, 1 misuse |
| `sonar-branch` | `bash` | `sonarcloud_fetch_branch.sh` | Pull SonarCloud findings for a branch | `<branch>` | 0 ok |
| `install-hooks` | `bash` | `install-hooks.sh` | Install the repo's git hooks (commit-msg, pre-commit, pre-push) | *(none)* | 0 ok |
| `md-to-pdf` | `python3` | `md-to-pdf/md-to-pdf.py` | Render markdown to PDF with Mermaid diagrams and a cover theme | `<file.md> [--theme <name>]` | 0 ok |

### Verification status

Run against a real tree on 2026-09-20 at the pinned sha:

| Entry | Evidence |
|---|---|
| `strip-comments` | `--help` lists a complete `argparse` surface; dry-run is the default, `--apply` is opt-in |
| `header-cycles` | Run on an empty directory: `No header files found`, exit 0 |
| `gen-password` | Emitted `$2b$12$…`, exit 0 |
| `disk-monitor` | No output under threshold, exit 0 — correct silent behaviour |
| `sysinfo` | Read in full; plain `uptime`/`df`/`free`, no side effects |
| `valgrind-check` | Arg contract read at source: `$# -ne 2` → usage, exit 1; validates the source dir before compiling |

**Ponytail:** the six entries above are exercised; the remaining six
(`norm-check`, `leaks-check`, `branch-diff`, `sonar-branch`, `install-hooks`,
`md-to-pdf`) are registered from reading the source, not from a run — their argument
and exit columns are read off the code, not observed. Treat those as a pointer to the
script, and check the output before you act on it. Move a row up once you have run it.

---

## Deliberately not registered

Not a judgement on the code — these are the ones an agent should not reach for.

| Why | Scripts |
|---|---|
| **Destructive or account-level.** Needs a human with the consequences in view (`rules/risk.md`). | `gh_delete_repo.sh`, `remove_empty_repo_gh.sh`, `create_fake_repos.sh`, `backup.sh`, `backups/github-backup.sh` |
| **Mutates a whole tree in place**, with no dry run. | `add_42_headers.js`, `modify_prefix.sh`, `search_and_replace.sh`, `organize_file.sh`, `norm_fix.py`, `norm_align.py`, `norm_fmt.py`, `norm_preproc.py`, `opti-norminette.sh` |
| **Changes the machine**, not the project. | `setup_pyenv.sh`, `register_shell.sh`, `obsidian_installation.sh`, `theme.sh`, `env_manager.ps1` |
| **Superseded** by a tool already here. | `checker.py`, `test.sh`, `optimized.sh`, `verif_dependency.sh` → `tools/quality.sh`; `lookfor.sh` → `rg`; `clean_cache.sh`, `fd_manager.sh` → project-specific |
| **Not a script.** | `extension_vs_code_glass/` (a VS Code extension), `sort.c`, `template.sh`, `utilities.sh` (function libraries meant to be sourced) |
| **Unclear contract.** `.hide_file_for_norm.sh` opens with a bare `cat **/.*`; `lookfor.sh`'s own `--help` describes different flags than its name suggests. | `.hide_file_for_norm.sh`, `lookfor.sh`, `piggyback.sh`, `sniper_non_tty.sh` |

---

## Adding an entry

1. Read the script. Confirm what it writes, what it deletes, and what it assumes is
   installed.
2. Run it on a throwaway tree. Record the command and the output.
3. Add the row, with the **real** args and exit codes — not the ones the name implies.
4. Move it into the verification table with the evidence.
5. Re-pin only deliberately: `scripts.sh sync --pin <sha>`, then re-verify. A new sha
   is new code, and the registry's claims are about the old one.
