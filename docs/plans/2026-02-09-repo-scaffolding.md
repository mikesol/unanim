# Repo Scaffolding: Nim Project Structure and CI

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up a working Nim project skeleton with nimble, tests, and GitHub Actions CI.

**Architecture:** Create a standard Nim project with `unanim.nimble` as the build file, a minimal `src/unanim.nim` module, a test in `tests/`, and a GitHub Actions workflow. The `_generated/` directory is already gitignored.

**Tech Stack:** Nim 2.x, nimble, GitHub Actions, `jiro4989/setup-nim-action`

---

### Task 1: Create the nimble file

**Files:**
- Create: `unanim.nimble`

**Step 1: Write the nimble file**

```nim
# Package
version       = "0.1.0"
author        = "mikesol"
description   = "Compile-time framework that eliminates the backend"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "Run tests":
  exec "nim c -r tests/test_unanim.nim"
```

**Step 2: Verify nimble recognizes the project**

Run: `nimble dump`
Expected: Shows project metadata (name, version, etc.)

**Step 3: Commit**

```bash
git add unanim.nimble
git commit -m "feat: add unanim.nimble project file"
```

---

### Task 2: Create the entry point module

**Files:**
- Create: `src/unanim.nim`
- Delete: `src/.gitkeep`

**Step 1: Write the minimal module**

```nim
## Unanim - Compile-time framework that eliminates the backend.
##
## This is the main entry point. Framework functionality will be added
## in subsequent issues.

const unanimVersion* = "0.1.0"
```

**Step 2: Verify it compiles**

Run: `nim c src/unanim.nim`
Expected: Compiles without errors, produces a binary (we won't use it, but compilation should succeed)

**Step 3: Clean up gitkeep and commit**

```bash
rm src/.gitkeep
git add src/unanim.nim
git rm src/.gitkeep
git commit -m "feat: add src/unanim.nim entry point"
```

---

### Task 3: Create a minimal test

**Files:**
- Create: `tests/test_unanim.nim`
- Delete: `tests/.gitkeep`

**Step 1: Write the test**

```nim
import ../src/unanim

block testVersion:
  doAssert unanimVersion == "0.1.0", "Version should be 0.1.0"

echo "All tests passed."
```

**Step 2: Run the test directly**

Run: `nim c -r tests/test_unanim.nim`
Expected: Compiles and prints "All tests passed."

**Step 3: Run via nimble**

Run: `nimble test`
Expected: Runs the test task, compiles and passes

**Step 4: Clean up gitkeep and commit**

```bash
rm tests/.gitkeep
git add tests/test_unanim.nim
git rm tests/.gitkeep
git commit -m "feat: add minimal test suite"
```

---

### Task 4: Create the _generated directory with .gitkeep

**Files:**
- Create: `_generated/.gitkeep`

**Step 1: Create the directory**

The `_generated/` directory is already in `.gitignore`, so we do NOT track it. But the issue says "Directory structure: `_generated/` (gitignored)". This means it just needs to exist in `.gitignore` (which it already does). We should verify it's there and document it.

Actually, since `_generated/` is gitignored, we don't need to create it or track it. It will be created by the build process when needed. The `.gitignore` already has the entry. This task is already done.

**Step 2: Verify .gitignore has the entry**

Run: `grep '_generated' .gitignore`
Expected: `_generated/`

No commit needed — already covered.

---

### Task 5: Create GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Write the CI workflow**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: jiro4989/setup-nim-action@v2
        with:
          nim-version: '2.x'
          repo-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Build
        run: nimble build -y

      - name: Test
        run: nimble test -y
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
(Or just visually check — it's simple enough.)

**Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "feat: add GitHub Actions CI workflow"
```

---

### Task 6: Local validation

**Step 1: Run nimble build**

Run: `nimble build`
Expected: Compiles successfully

**Step 2: Run nimble test**

Run: `nimble test`
Expected: Tests pass, prints "All tests passed."

**Step 3: Verify directory structure**

Run: `find . -not -path './.git/*' -not -path './.git' | sort`
Expected structure includes:
```
./src/unanim.nim
./tests/test_unanim.nim
./unanim.nimble
./.github/workflows/ci.yml
./docs/
./CLAUDE.md
./VISION.md
./.gitignore
```

---

### Task 7: Create PR

**Step 1: Push branch and create PR**

```bash
git push -u origin issue-1
gh pr create --title "Repo scaffolding: Nim project structure and CI" --body "$(cat <<'EOF'
Closes #1

## What this does
Sets up the Nim project skeleton: nimble file, entry point module, test suite, and GitHub Actions CI.

## Spec compliance
- **Section 13 (Build Philosophy)**: Project structure follows standard Nim conventions (`src/`, `tests/`, `docs/`, `_generated/` gitignored). CI validates on every push.

## Validation performed
- `nimble build` succeeds locally
- `nimble test` runs and passes locally
- CI will validate on this PR

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
