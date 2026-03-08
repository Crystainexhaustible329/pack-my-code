#!/usr/bin/env lua
-- =============================================================================
--  test.lua – Cross-platform test suite for pmc (pack-my-code)
--  Tests ONLY features documented in README.md. No undocumented features.
--  Usage:  lua test.lua
--          lua test.lua -v          (verbose)
--          lua test.lua -f <name>   (filter)
-- =============================================================================

---------------------------------------------------------------------------
-- 0. Platform detection
---------------------------------------------------------------------------
local IS_WIN = (package.config:sub(1, 1) == "\\")
local SEP    = IS_WIN and "\\" or "/"
local NULL   = IS_WIN and "NUL" or "/dev/null"
local PMC    = "lua " .. (arg[0]:match("^(.-)[/\\][^/\\]*$") or ".") .. SEP .. "pmc.lua"

-- Resolve PMC to absolute path (needed by run_pmc_in which changes CWD)
local PMC_ABS
do
    local pmc_rel_dir = arg[0]:match("^(.-)[/\\][^/\\]*$") or "."
    local resolve_cmd = IS_WIN
        and ('cd /d "' .. pmc_rel_dir:gsub("/", "\\") .. '" && cd')
        or ('cd "' .. pmc_rel_dir .. '" && pwd')
    local pipe = io.popen(resolve_cmd)
    if pipe then
        local abs_dir = (pipe:read("*l") or ""):gsub("[\r\n]+", "")
        pipe:close()
        if abs_dir ~= "" then
            PMC_ABS = "lua \"" .. abs_dir .. SEP .. "pmc.lua\""
        end
    end
    if not PMC_ABS then PMC_ABS = PMC end
end

---------------------------------------------------------------------------
-- 1. CLI argument parser
---------------------------------------------------------------------------
local VERBOSE = false
local FILTER  = nil
do
    local i = 1
    while i <= #arg do
        if arg[i] == "-v" or arg[i] == "--verbose" then
            VERBOSE = true
        elseif (arg[i] == "-f" or arg[i] == "--filter") and arg[i + 1] then
            i = i + 1; FILTER = arg[i]
        end
        i = i + 1
    end
end

---------------------------------------------------------------------------
-- 2. Filesystem helpers
---------------------------------------------------------------------------
local function path(...)
    return table.concat({ ... }, SEP)
end

local function mkdir_p(dir)
    if IS_WIN then
        os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>' .. NULL)
    else
        os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
    end
end

local function rm_rf(dir)
    if IS_WIN then
        os.execute('rmdir /s /q "' .. dir:gsub("/", "\\") .. '" 2>' .. NULL)
    else
        os.execute('rm -rf "' .. dir .. '" 2>/dev/null')
    end
end

local function write_file(fp, content)
    local parent = fp:match("^(.*)[/\\]")
    if parent then mkdir_p(parent) end
    local f = io.open(fp, "wb")
    if not f then error("cannot write: " .. fp) end
    f:write(content)
    f:close()
end

local function read_file(fp)
    local f = io.open(fp, "rb")
    if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function file_exists(fp)
    local f = io.open(fp, "rb")
    if f then
        f:close(); return true
    end
    return false
end

---------------------------------------------------------------------------
-- 3. Run pmc helpers
---------------------------------------------------------------------------
local function run_pmc(args_str)
    local tmpout = os.tmpname()
    local tmperr = os.tmpname()
    local full = PMC .. " " .. (args_str or "")
        .. ' >"' .. tmpout .. '" 2>"' .. tmperr .. '"'
    local ok, _, code = os.execute(full)
    local exit_code
    if type(ok) == "number" then
        exit_code = ok
    else
        exit_code = code or 0
        if not ok and exit_code == 0 then exit_code = 1 end
    end
    local stdout = read_file(tmpout) or ""
    local stderr = read_file(tmperr) or ""
    os.remove(tmpout); os.remove(tmperr)
    return { stdout = stdout, stderr = stderr, code = exit_code, ok = (exit_code == 0) }
end

--- Run pmc after cd-ing to `dir`.
--- Prevents Windows CRT glob expansion when `dir` contains no matching files.
--- Uses PMC_ABS so the pmc script is still found after cd.
local function run_pmc_in(dir, args_str)
    local tmpout = os.tmpname()
    local tmperr = os.tmpname()
    local cd_prefix
    if IS_WIN then
        cd_prefix = 'cd /d "' .. dir:gsub("/", "\\") .. '" && '
    else
        cd_prefix = 'cd "' .. dir .. '" && '
    end
    local full = cd_prefix .. PMC_ABS .. " " .. (args_str or "")
        .. ' >"' .. tmpout .. '" 2>"' .. tmperr .. '"'
    local ok, _, code = os.execute(full)
    local exit_code
    if type(ok) == "number" then
        exit_code = ok
    else
        exit_code = code or 0
        if not ok and exit_code == 0 then exit_code = 1 end
    end
    local stdout = read_file(tmpout) or ""
    local stderr = read_file(tmperr) or ""
    os.remove(tmpout); os.remove(tmperr)
    return { stdout = stdout, stderr = stderr, code = exit_code, ok = (exit_code == 0) }
end

---------------------------------------------------------------------------
-- 4. Mini test framework
---------------------------------------------------------------------------
local tests, test_order = {}, {}
local pass_count, fail_count, skip_count = 0, 0, 0
local errors = {}

local function test(name, fn)
    tests[name] = fn; table.insert(test_order, name)
end

local AssertError = {}
function AssertError.new(msg)
    return setmetatable({ msg = msg }, { __tostring = function(s) return s.msg end })
end

local function assert_true(v, m)
    if not v then error(AssertError.new(m or "expected truthy, got: " .. tostring(v)), 2) end
end
local function assert_false(v, m)
    if v then error(AssertError.new(m or "expected falsy, got: " .. tostring(v)), 2) end
end
local function assert_eq(a, b, m)
    if a ~= b then
        local d = string.format("expected %q, got %q", tostring(b), tostring(a))
        error(AssertError.new(m and (m .. ": " .. d) or d), 2)
    end
end
local function assert_contains(h, n, m)
    if type(h) ~= "string" or not h:find(n, 1, true) then
        local d = string.format("expected to contain %q", n)
        error(AssertError.new(m and (m .. ": " .. d) or d), 2)
    end
end
local function assert_not_contains(h, n, m)
    if type(h) == "string" and h:find(n, 1, true) then
        local d = string.format("expected NOT to contain %q", n)
        error(AssertError.new(m and (m .. ": " .. d) or d), 2)
    end
end
local function assert_match(h, p, m)
    if type(h) ~= "string" or not h:match(p) then
        local d = string.format("expected to match %q", p)
        error(AssertError.new(m and (m .. ": " .. d) or d), 2)
    end
end
local function assert_file_exists(fp, m)
    assert_true(file_exists(fp), m or ("file should exist: " .. fp))
end

---------------------------------------------------------------------------
-- 5. Test fixture
---------------------------------------------------------------------------
local TEST_ROOT = path(".", ".pmc_test_" .. os.time())

local function create_fixture()
    rm_rf(TEST_ROOT)

    mkdir_p(path(TEST_ROOT, "src", "utils"))
    mkdir_p(path(TEST_ROOT, "docs"))
    mkdir_p(path(TEST_ROOT, "build"))
    mkdir_p(path(TEST_ROOT, "assets"))
    mkdir_p(path(TEST_ROOT, "node_modules", "pkg"))
    mkdir_p(path(TEST_ROOT, ".git", "objects"))

    -- Lua sources
    write_file(path(TEST_ROOT, "src", "main.lua"),
        '-- main.lua\nlocal utils = require("utils")\nprint("hello world")\n')
    write_file(path(TEST_ROOT, "src", "utils", "init.lua"),
        '-- utils/init.lua\nlocal M = {}\nfunction M.greet(name)\n    return "Hello, " .. name\nend\nreturn M\n')
    write_file(path(TEST_ROOT, "src", "config.lua"),
        '-- config.lua\nreturn {\n    version = "1.0.0",\n    debug = false,\n}\n')

    -- Non-Lua text sources
    write_file(path(TEST_ROOT, "src", "helper.py"),
        '# helper.py\ndef greet(name):\n    return f"Hello, {name}"\n')
    write_file(path(TEST_ROOT, "src", "app.js"),
        '// app.js\nconsole.log("hello from js");\n')

    -- Docs
    write_file(path(TEST_ROOT, "docs", "guide.md"),
        "# Project Guide\nThis is the project guide.\n")

    -- Build artefact (binary)
    write_file(path(TEST_ROOT, "build", "output.bin"),
        string.rep("\0\xFF", 100))

    -- Asset (binary, not gitignored — tests binary-skip independently)
    write_file(path(TEST_ROOT, "assets", "logo.png"),
        "\137PNG\r\n\26\n" .. string.rep("\0", 50))

    -- .git internal (never listed by git ls-files)
    write_file(path(TEST_ROOT, ".git", "config"),
        "[core]\nbare = false\n")

    -- node_modules (gitignored)
    write_file(path(TEST_ROOT, "node_modules", "pkg", "index.js"),
        "module.exports = {};\n")

    -- .gitignore
    write_file(path(TEST_ROOT, ".gitignore"),
        "build/\nnode_modules/\n*.bin\n")

    -- Root text files
    write_file(path(TEST_ROOT, "README.md"),
        "# Root README\nPack my code!\n")
    write_file(path(TEST_ROOT, "Makefile"),
        "all:\n\tlua src/main.lua\n")
end

local function destroy_fixture()
    rm_rf(TEST_ROOT)
end

---------------------------------------------------------------------------
-- 6. Test cases — strictly per README.md
---------------------------------------------------------------------------

-- ── Basic usage ─────────────────────────────────────────────────────────

test("basic: runs without error on valid directory", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_true(r.ok, "exit 0 expected, got " .. r.code .. " stderr: " .. r.stderr)
end)

test("basic: output contains source file content", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_contains(r.stdout, 'print("hello world")', "main.lua content")
    assert_contains(r.stdout, "function M.greet(name)", "utils/init.lua content")
end)

test("basic: output references file paths", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_match(r.stdout, "main%.lua", "references main.lua")
    assert_match(r.stdout, "config%.lua", "references config.lua")
end)

test("basic: includes non-Lua text files (py, js, md)", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_contains(r.stdout, "def greet(name)", ".py content")
    assert_contains(r.stdout, "hello from js", ".js content")
    assert_contains(r.stdout, "Project Guide", ".md content")
end)

-- ── Default behaviors ───────────────────────────────────────────────────

test("default: follows .gitignore — excludes build/", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_not_contains(r.stdout, string.rep("\0\xFF", 5), "build/ excluded")
end)

test("default: follows .gitignore — excludes node_modules/", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_not_contains(r.stdout, "module.exports", "node_modules/ excluded")
end)

test("default: excludes .git directory", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_not_contains(r.stdout, "bare = false", ".git content excluded")
end)

test("default: skips binary files", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_not_contains(r.stdout, "\0", "no null bytes in output")
end)

test("default: wrapping equals -w md", function()
    local r1 = run_pmc('"' .. TEST_ROOT .. '"')
    local r2 = run_pmc('-w md "' .. TEST_ROOT .. '"')
    assert_eq(r1.stdout, r2.stdout, "default output = -w md output")
end)

test("default: path mode equals -p relative", function()
    local r1 = run_pmc('"' .. TEST_ROOT .. '"')
    local r2 = run_pmc('-p relative "' .. TEST_ROOT .. '"')
    assert_eq(r1.stdout, r2.stdout, "default output = -p relative output")
end)

test("default: no tree structure in output", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_not_contains(r.stdout, "|-- ", "no tree branch markers")
end)

test("default: no statistics in output", function()
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_not_contains(r.stdout, "STATS:", "no STATS: block")
end)

-- ── -v version ──────────────────────────────────────────────────────────

test("-v: prints version string", function()
    local r = run_pmc("-v")
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "pmc -- pack-my-code. version", "version format")
end)

-- ── -h / --help ─────────────────────────────────────────────────────────

test("-h: prints help with usage info", function()
    local r = run_pmc("-h")
    assert_true(r.ok, "should succeed")
    assert_match(r.stdout:lower(), "usage", "contains usage")
end)

test("--help: prints help with usage info", function()
    local r = run_pmc("--help")
    assert_true(r.ok, "should succeed")
    assert_match(r.stdout:lower(), "usage", "contains usage")
end)

-- ── -x exclude ──────────────────────────────────────────────────────────

test("-x: excludes files by glob pattern", function()
    local r = run_pmc('-x "*.py" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_not_contains(r.stdout, "def greet", ".py excluded")
    assert_contains(r.stdout, "hello world", ".lua remains")
end)

test("-x: excludes directory with trailing slash", function()
    local r = run_pmc('-x "docs/" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_not_contains(r.stdout, "Project Guide", "docs/ excluded")
end)

test("-x: comma-separated multiple patterns", function()
    local r = run_pmc('-x "*.py,*.js" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_not_contains(r.stdout, "def greet", ".py excluded")
    assert_not_contains(r.stdout, "hello from js", ".js excluded")
    assert_contains(r.stdout, "hello world", ".lua remains")
end)

-- ── -m include only ─────────────────────────────────────────────────────

-- NOTE: These two tests use run_pmc_in(TEST_ROOT, ...) to cd into the test
-- fixture before invoking pmc. This prevents the Windows C runtime from
-- glob-expanding "*.lua" against CWD files (pmc.lua, test.lua in the project
-- root). TEST_ROOT has no .lua files at its root level, so expansion is
-- avoided. The target is passed as "." since CWD is now TEST_ROOT.

test("-m: includes only matching files", function()
    local r = run_pmc_in(TEST_ROOT, '-m "*.lua" .')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "hello world", ".lua included")
    assert_not_contains(r.stdout, "def greet", ".py excluded")
    assert_not_contains(r.stdout, "hello from js", ".js excluded")
end)

test("-m: lower priority than -x (file matching both is excluded)", function()
    local r = run_pmc_in(TEST_ROOT, '-m "*.lua" -x "config.lua" .')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "hello world", "main.lua kept by -m")
    assert_not_contains(r.stdout, "debug = false", "config.lua excluded by -x despite -m")
end)

-- ── -r ignore .gitignore ────────────────────────────────────────────────

test("-r: includes files normally excluded by .gitignore", function()
    local r = run_pmc('-r "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "module.exports", "node_modules content appears with -r")
end)

-- ── -t tree structure ───────────────────────────────────────────────────

test("-t: prepends tree structure before content", function()
    local r = run_pmc('-t "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    local tree_pos = r.stdout:find("|-- ", 1, true) or r.stdout:find("`-- ", 1, true)
    local content_pos = r.stdout:find("PATH: ", 1, true)
    assert_true(tree_pos ~= nil, "tree markers present")
    assert_true(content_pos ~= nil, "content present")
    assert_true(tree_pos < content_pos, "tree appears before content")
end)

-- ── -s statistics ───────────────────────────────────────────────────────

test("-s: appends statistics after content", function()
    local r = run_pmc('-s "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "STATS:", "has STATS:")
    assert_contains(r.stdout, "total_files:", "has total_files")
    assert_contains(r.stdout, "total_lines:", "has total_lines")
    local stats_pos = r.stdout:find("STATS:", 1, true)
    local path_pos  = r.stdout:find("PATH: ", 1, true)
    assert_true(stats_pos > path_pos, "stats after content")
end)

-- ── -w wrapping modes ───────────────────────────────────────────────────

test("-w md: PATH header + backtick fence", function()
    local r = run_pmc('-w md "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "PATH: ", "has PATH: header")
    assert_contains(r.stdout, "````", "has backtick fence")
end)

test("-w nil: PATH header, no fence, no block markers", function()
    local r = run_pmc('-w nil "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "PATH: ", "has PATH: header")
    assert_not_contains(r.stdout, "````", "no backtick fence")
    assert_not_contains(r.stdout, "<<<FILE", "no block marker")
end)

test("-w block: <<<FILE / >>>END markers", function()
    local r = run_pmc('-w block "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "<<<FILE ", "has <<<FILE")
    assert_contains(r.stdout, ">>>END", "has >>>END")
    assert_not_contains(r.stdout, "````", "no backtick fence")
end)

-- ── -p path modes ───────────────────────────────────────────────────────

test("-p name: filename only, no directory separators", function()
    local r = run_pmc('-p name "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    local p = r.stdout:match("PATH: ([^\n]+)")
    assert_true(p ~= nil, "has PATH: header")
    assert_false(p:find("/", 1, true), "no / in filename-only path")
end)

test("-p absolute: full absolute path in header", function()
    local r = run_pmc('-p absolute "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    local p = r.stdout:match("PATH: ([^\n]+)")
    assert_true(p ~= nil, "has PATH: header")
    if IS_WIN then
        assert_match(p, "^%a:", "starts with drive letter on Windows")
    else
        assert_match(p, "^/", "starts with / on Unix")
    end
end)

-- ── -y YAML mode ────────────────────────────────────────────────────────

test("-y -o .yaml: produces YAML structured output", function()
    local out = path(TEST_ROOT, "_out.yaml")
    local r = run_pmc('-y -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_file_exists(out)
    local c = read_file(out)
    assert_contains(c, "type: directory", "has type: directory")
    assert_contains(c, "type: file", "has type: file")
    assert_contains(c, "content: |-", "has block scalar marker")
    assert_contains(c, "hello world", "has file content")
    os.remove(out)
end)

test("-y -o .yml: also accepted", function()
    local out = path(TEST_ROOT, "_out.yml")
    local r = run_pmc('-y -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed with .yml extension")
    assert_file_exists(out)
    os.remove(out)
end)

test("-y without -o: fails with error", function()
    local r = run_pmc('-y "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "should fail without -o")
    assert_contains(r.stderr, "err:(", "uses err:( format")
end)

test("-y -o non-yaml extension: fails with error", function()
    local out = path(TEST_ROOT, "_out.txt")
    local r = run_pmc('-y -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "should fail with .txt extension")
    assert_contains(r.stderr, "err:(", "uses err:( format")
end)

test("-y with -t: fails (incompatible)", function()
    local out = path(TEST_ROOT, "_out.yaml")
    local r = run_pmc('-y -t -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "-y and -t incompatible")
    assert_contains(r.stderr, "err:(", "uses err:( format")
end)

test("-y with -s: fails (incompatible)", function()
    local out = path(TEST_ROOT, "_out.yaml")
    local r = run_pmc('-y -s -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "-y and -s incompatible")
    assert_contains(r.stderr, "err:(", "uses err:( format")
end)

test("-y with -w: fails (incompatible)", function()
    local out = path(TEST_ROOT, "_out.yaml")
    local r = run_pmc('-y -w md -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "-y and -w incompatible")
    assert_contains(r.stderr, "err:(", "uses err:( format")
end)

test("-y with -p: fails (incompatible)", function()
    local out = path(TEST_ROOT, "_out.yaml")
    local r = run_pmc('-y -p name -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "-y and -p incompatible")
    assert_contains(r.stderr, "err:(", "uses err:( format")
end)

-- ── -o output redirection ───────────────────────────────────────────────

test("-o: redirects packed output to file", function()
    local out = path(TEST_ROOT, "_packed.txt")
    local r = run_pmc('-o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_file_exists(out)
    local c = read_file(out)
    assert_contains(c, "hello world", "file has source content")
    assert_contains(c, "PATH: ", "file has path headers")
    os.remove(out)
end)

-- ── Error handling ──────────────────────────────────────────────────────

test("error: nonexistent directory fails", function()
    local r = run_pmc('"' .. path(TEST_ROOT, "nonexistent_xyz") .. '"')
    assert_false(r.ok, "should fail")
end)

test("error: stderr uses err:( format", function()
    local r = run_pmc('"' .. path(TEST_ROOT, "nonexistent_xyz") .. '"')
    assert_contains(r.stderr, "err:(", "has err:( prefix")
end)

test("error: unknown option fails", function()
    local r = run_pmc('--bogus "' .. TEST_ROOT .. '"')
    assert_false(r.ok, "should fail for unknown option")
    assert_contains(r.stderr, "err:(", "has err:( prefix")
end)

-- ── Combination examples (from README) ──────────────────────────────────

test("combo: -t -s produces tree then content then stats", function()
    local r = run_pmc('-t -s "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    local tree_pos    = r.stdout:find("|-- ", 1, true) or r.stdout:find("`-- ", 1, true)
    local content_pos = r.stdout:find("PATH: ", 1, true)
    local stats_pos   = r.stdout:find("STATS:", 1, true)
    assert_true(tree_pos ~= nil, "tree present")
    assert_true(content_pos ~= nil, "content present")
    assert_true(stats_pos ~= nil, "stats present")
    assert_true(tree_pos < content_pos, "tree before content")
    assert_true(content_pos < stats_pos, "content before stats")
end)

test("combo: -r -w block (raw scan + block wrap)", function()
    local r = run_pmc('-r -w block "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_contains(r.stdout, "<<<FILE ", "block markers present")
    assert_contains(r.stdout, "module.exports", "gitignored content appears with -r")
end)

test("combo: -x with -o writes filtered output to file", function()
    local out = path(TEST_ROOT, "_filtered.md")
    local r = run_pmc('-x "*.py,*.js" -o "' .. out .. '" "' .. TEST_ROOT .. '"')
    assert_true(r.ok, "should succeed")
    assert_file_exists(out)
    local c = read_file(out)
    assert_not_contains(c, "def greet", "py excluded in file")
    assert_not_contains(c, "hello from js", "js excluded in file")
    assert_contains(c, "hello world", "lua present in file")
    os.remove(out)
end)

-- ── Edge cases ──────────────────────────────────────────────────────────

test("edge: empty directory — no crash", function()
    local empty = path(TEST_ROOT, "empty_dir")
    mkdir_p(empty)
    local r = run_pmc('"' .. empty .. '"')
    assert_true(type(r.stdout) == "string", "produces string output")
end)

test("edge: large file handled without crash", function()
    local big = path(TEST_ROOT, "src", "big.lua")
    local lines = {}
    for i = 1, 5000 do lines[i] = string.format("local x%d = %d", i, i) end
    write_file(big, table.concat(lines, "\n"))
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_true(r.ok, "no crash on large file")
    assert_contains(r.stdout, "local x5000 = 5000", "large file content present")
    os.remove(big)
end)

test("edge: recurses into deeply nested directories", function()
    local deep = path(TEST_ROOT, "a", "b", "c", "d")
    mkdir_p(deep)
    write_file(path(deep, "deep.lua"), "-- deep nested\nlocal d = true\n")
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_contains(r.stdout, "deep nested", "finds deeply nested file")
end)

test("edge: filenames with spaces", function()
    local sp = path(TEST_ROOT, "src", "my module.lua")
    write_file(sp, "-- file with spaces\nlocal sp = 1\n")
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_contains(r.stdout, "file with spaces", "handles spaces in names")
    os.remove(sp)
end)

test("edge: preserves UTF-8 content", function()
    write_file(path(TEST_ROOT, "src", "i18n.lua"),
        '-- 你好世界 こんにちは\nlocal g = "Héllo"\n')
    local r = run_pmc('"' .. TEST_ROOT .. '"')
    assert_contains(r.stdout, "你好世界", "CJK characters preserved")
    assert_contains(r.stdout, "Héllo", "accented characters preserved")
end)

test("edge: deterministic output across runs", function()
    local r1 = run_pmc('"' .. TEST_ROOT .. '"')
    local r2 = run_pmc('"' .. TEST_ROOT .. '"')
    assert_eq(r1.stdout, r2.stdout, "two consecutive runs produce identical output")
end)

---------------------------------------------------------------------------
-- 7. Runner
---------------------------------------------------------------------------
local function run_tests()
    io.write("\n" .. string.rep("=", 60) .. "\n")
    io.write("  pmc test suite\n")
    io.write(string.rep("=", 60) .. "\n\n")

    create_fixture()

    for _, name in ipairs(test_order) do
        if FILTER and not name:find(FILTER, 1, true) then
            -- filtered out, skip silently
        else
            io.write(string.format("  %-55s ", name))
            io.flush()
            local ok, err = pcall(tests[name])
            if ok then
                if err == "skip" then
                    skip_count = skip_count + 1
                    io.write("[SKIP]\n")
                else
                    pass_count = pass_count + 1
                    if VERBOSE then
                        io.write("\27[32m[PASS]\27[0m\n")
                    else
                        io.write("[PASS]\n")
                    end
                end
            else
                fail_count = fail_count + 1
                local msg = tostring(err)
                if VERBOSE then
                    io.write("\27[31m[FAIL]\27[0m\n")
                    io.write("         " .. msg .. "\n")
                else
                    io.write("[FAIL]\n")
                end
                table.insert(errors, { name = name, err = msg })
            end
        end
    end

    destroy_fixture()

    io.write("\n" .. string.rep("-", 60) .. "\n")
    local total = pass_count + fail_count + skip_count
    io.write(string.format("  Total: %d  |  Pass: %d  |  Fail: %d  |  Skip: %d\n",
        total, pass_count, fail_count, skip_count))

    if #errors > 0 then
        io.write("\n  Failures:\n")
        for i, e in ipairs(errors) do
            io.write(string.format("    %d) %s\n       %s\n", i, e.name, e.err))
        end
    end

    io.write(string.rep("-", 60) .. "\n")
    if fail_count > 0 then
        io.write("\27[31m  FAILED\27[0m\n\n")
        os.exit(1)
    else
        io.write("\27[32m  ALL PASSED\27[0m\n\n")
        os.exit(0)
    end
end

run_tests()
