--@description: test.lua - comprehensive test suite for pmc
--@author: WaterRun
--@date: 2026-03-09

-- =============================================================================
-- Platform & Constants
-- =============================================================================

local DIR_SEP = package.config:sub(1, 1)
local IS_WINDOWS = (DIR_SEP == "\\")
local NULL_DEV = IS_WINDOWS and "NUL" or "/dev/null"

local PMC_SOURCE = "pmc.lua"
local PMC_BIN = IS_WINDOWS and "pmc.exe" or "pmc"
local TEST_DIR = "_pmc_test_workspace"
local STDOUT_TMP = "_pmc_stdout.tmp"
local STDERR_TMP = "_pmc_stderr.tmp"
local OUTPUT_MD = "_pmc_out.md"
local OUTPUT_YAML = "_pmc_out.yaml"
local PMC_CMD = nil -- assigned after build

-- =============================================================================
-- Counters
-- =============================================================================

local total = 0
local passed = 0
local failed = 0
local fail_names = {}

-- =============================================================================
-- Utilities
-- =============================================================================

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sq(s)
    if IS_WINDOWS then
        return '"' .. s:gsub('"', '""') .. '"'
    end
    return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

local function osExec(cmd)
    local r1, _, _ = os.execute(cmd)
    if type(r1) == "number" then return r1 == 0 end
    return r1 == true
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data or ""
end

local function writeFile(path, content)
    local f = io.open(path, "wb")
    if not f then error("Cannot write: " .. path) end
    f:write(content)
    f:close()
end

local function mkdirp(path)
    if IS_WINDOWS then
        osExec('mkdir "' .. path:gsub("/", "\\") .. '" 2>NUL')
    else
        osExec("mkdir -p " .. sq(path) .. " 2>/dev/null")
    end
end

local function rmrf(path)
    if IS_WINDOWS then
        osExec('rmdir /s /q "' .. path:gsub("/", "\\") .. '" 2>NUL')
        osExec('del /f /q "' .. path:gsub("/", "\\") .. '" 2>NUL')
    else
        osExec("rm -rf " .. sq(path) .. " 2>/dev/null")
    end
end

local function fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

-- =============================================================================
-- Test Infrastructure
-- =============================================================================

local function runPmc(args)
    local cmd = PMC_CMD .. " " .. (args or "")
        .. " >" .. sq(STDOUT_TMP)
        .. " 2>" .. sq(STDERR_TMP)
    local ok = osExec(cmd)
    local stdout = readFile(STDOUT_TMP) or ""
    local stderr = readFile(STDERR_TMP) or ""
    stdout = stdout:gsub("\r\n", "\n"):gsub("\r", "\n")
    stderr = stderr:gsub("\r\n", "\n"):gsub("\r", "\n")
    os.remove(STDOUT_TMP)
    os.remove(STDERR_TMP)
    return ok, stdout, stderr
end

local function contains(s, sub)
    return s:find(sub, 1, true) ~= nil
end

local function notContains(s, sub)
    return not contains(s, sub)
end

local function expect(cond, msg)
    if not cond then error(msg or "expectation failed", 2) end
end

local function test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok and err ~= false then
        passed = passed + 1
        io.write(string.format("  [PASS] %s\n", name))
    else
        failed = failed + 1
        local msg = (type(err) == "string") and err or "assertion failed"
        io.write(string.format("  [FAIL] %s -- %s\n", name, msg))
        table.insert(fail_names, name)
    end
    io.stdout:flush()
end

-- =============================================================================
-- Cleanup helpers (called at end, even on error)
-- =============================================================================

local function cleanupAll()
    io.write("\nCleaning up...\n")
    rmrf(TEST_DIR)
    os.remove(STDOUT_TMP)
    os.remove(STDERR_TMP)
    os.remove(OUTPUT_MD)
    os.remove(OUTPUT_YAML)
    if fileExists(PMC_BIN) then
        os.remove(PMC_BIN)
        io.write("  Removed binary: " .. PMC_BIN .. "\n")
    end
    io.write("  Done.\n")
end

-- =============================================================================
-- Test file content definitions
-- =============================================================================

local TEST_FILES = {
    [".gitignore"]             = "*.log\nignored_dir/\n",
    ["src/main.lua"]           = "local M = {}\n\nfunction M.run()\n  print(\"Hello\")\nend\n\nreturn M\n",
    ["src/utils.lua"]          = "local U = {}\nfunction U.add(a, b) return a + b end\nreturn U\n",
    ["src/helper.py"]          = "def greet(name):\n    return f\"Hello, {name}\"\n",
    ["docs/readme.md"]         = "# Docs\n\nSome documentation.\n",
    ["config.json"]            = "{\n  \"key\": \"value\"\n}\n",
    ["data.txt"]               = "Line 1\nLine 2\nLine 3\n",
    ["empty.txt"]              = "",
    ["image.png"]              = "FAKE_PNG_BINARY_DATA",
    ["debug.log"]              = "Log entry here\n",
    ["ignored_dir/secret.txt"] = "Secret content\n",
    ["nested/deep/inner.lua"]  = "return 42\n",
    ["Makefile"]               = "all:\n\t@echo done\n",
}

-- =============================================================================
-- Main execution
-- =============================================================================

local function main()
    io.write("==================================================\n")
    io.write("           PMC Test Suite\n")
    io.write("==================================================\n\n")

    -- Check source
    if not fileExists(PMC_SOURCE) then
        io.write("ERROR: " .. PMC_SOURCE .. " not found.\n")
        io.write("       Run test.lua from the project root.\n")
        os.exit(1)
    end

    -- =========================================================================
    -- Build
    -- =========================================================================
    io.write("[BUILD]\n")
    local built = osExec("luainstaller build " .. PMC_SOURCE .. " 2>" .. NULL_DEV)
    if built and fileExists(PMC_BIN) then
        PMC_CMD = IS_WINDOWS and PMC_BIN or ("./" .. PMC_BIN)
        if not IS_WINDOWS then
            osExec("chmod +x " .. sq(PMC_BIN))
        end
        io.write("  Binary built: " .. PMC_BIN .. "\n")
    else
        io.write("  luainstaller unavailable, falling back to: lua " .. PMC_SOURCE .. "\n")
        PMC_CMD = "lua " .. PMC_SOURCE
    end

    -- Quick sanity: can we run it at all?
    do
        local ok, out, _ = runPmc("-v")
        if not ok and trim(out) == "" then
            io.write("ERROR: cannot execute pmc. Aborting.\n")
            cleanupAll()
            os.exit(1)
        end
    end

    io.write("\n")

    -- =========================================================================
    -- Group 1: Info commands (no workspace needed)
    -- =========================================================================
    io.write("[GROUP 1] Info commands\n")

    test("T01: -v shows version string", function()
        local ok, stdout, _ = runPmc("-v")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "pmc -- pack-my-code. version"), "missing version string")
    end)

    test("T02: -h shows help text", function()
        local ok, stdout, _ = runPmc("-h")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "Usage:"), "missing Usage:")
        expect(contains(stdout, "-x"), "missing -x")
        expect(contains(stdout, "-m"), "missing -m")
        expect(contains(stdout, "-r"), "missing -r")
        expect(contains(stdout, "-y"), "missing -y")
        expect(contains(stdout, "-o"), "missing -o")
    end)

    io.write("\n")

    -- =========================================================================
    -- Setup workspace
    -- =========================================================================
    io.write("[SETUP] Creating test workspace...\n")

    rmrf(TEST_DIR)
    mkdirp(TEST_DIR)
    mkdirp(TEST_DIR .. "/src")
    mkdirp(TEST_DIR .. "/docs")
    mkdirp(TEST_DIR .. "/nested/deep")
    mkdirp(TEST_DIR .. "/ignored_dir")

    for rel, content in pairs(TEST_FILES) do
        writeFile(TEST_DIR .. "/" .. rel, content)
    end

    -- Git init + add
    local git_available = osExec("git --version >" .. NULL_DEV .. " 2>" .. NULL_DEV)
    local git_init_ok = false
    if git_available then
        git_init_ok = osExec("git -C " .. sq(TEST_DIR) .. " init >" .. NULL_DEV .. " 2>" .. NULL_DEV)
        if git_init_ok then
            osExec("git -C " .. sq(TEST_DIR) .. " config core.autocrlf false 2>" .. NULL_DEV)
            osExec("git -C " .. sq(TEST_DIR) .. " config user.email test@test.com 2>" .. NULL_DEV)
            osExec("git -C " .. sq(TEST_DIR) .. " config user.name Test 2>" .. NULL_DEV)
            osExec("git -C " .. sq(TEST_DIR) .. " add . >" .. NULL_DEV .. " 2>" .. NULL_DEV)
        end
    end

    if not git_init_ok then
        io.write("  WARNING: git init failed; git-dependent tests will fail.\n")
    end
    io.write("  Workspace ready.\n\n")

    local TD = sq(TEST_DIR)

    -- =========================================================================
    -- Group 2: Default behavior (git mode, md wrap, relative paths)
    -- =========================================================================
    io.write("[GROUP 2] Default behavior\n")

    test("T03: default run produces PATH headers and md fences", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(contains(stdout, "PATH: "), "missing PATH header")
        expect(contains(stdout, "````"), "missing markdown fence")
    end)

    test("T04: default run omits gitignored .log file", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "debug.log"), "debug.log should be gitignored")
    end)

    test("T05: default run omits gitignored directory", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "secret.txt"), "ignored_dir/ should be gitignored")
    end)

    test("T06: default run skips binary extension (image.png)", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "image.png"), "binary file should be skipped")
    end)

    test("T07: default run includes expected files", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(contains(stdout, "main.lua"), "main.lua missing")
        expect(contains(stdout, "config.json"), "config.json missing")
        expect(contains(stdout, "inner.lua"), "inner.lua missing")
        expect(contains(stdout, "Makefile"), "Makefile missing")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 3: Wrap modes
    -- =========================================================================
    io.write("[GROUP 3] Wrap modes\n")

    test("T08: -w md produces markdown fences with language", function()
        local ok, stdout, _ = runPmc(TD .. " -w md")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "````lua"), "missing ````lua fence")
        expect(contains(stdout, "````json"), "missing ````json fence")
        expect(contains(stdout, "PATH: "), "missing PATH header")
    end)

    test("T09: -w nil produces PATH but no fences", function()
        local ok, stdout, _ = runPmc(TD .. " -w nil")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "PATH: "), "missing PATH header")
        expect(notContains(stdout, "````"), "should have no fences")
        expect(notContains(stdout, "<<<FILE"), "should have no block markers")
    end)

    test("T10: -w block produces <<<FILE and >>>END", function()
        local ok, stdout, _ = runPmc(TD .. " -w block")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "<<<FILE "), "missing <<<FILE marker")
        expect(contains(stdout, ">>>END"), "missing >>>END marker")
        expect(notContains(stdout, "````"), "should have no md fences")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 4: Path modes
    -- =========================================================================
    io.write("[GROUP 4] Path modes\n")

    test("T11: -p relative shows workspace-relative prefix", function()
        local ok, stdout, _ = runPmc(TD .. " -p relative")
        expect(ok, "exit non-zero")
        expect(contains(stdout, TEST_DIR .. "/"), "relative path should contain workspace dir")
    end)

    test("T12: -p name shows only filenames", function()
        local ok, stdout, _ = runPmc(TD .. " -p name")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "PATH: main.lua"), "should show bare filename main.lua")
        expect(contains(stdout, "PATH: config.json"), "should show bare filename config.json")
        -- should NOT contain directory components in PATH lines
        expect(notContains(stdout, "PATH: src/"), "name mode should not have dir prefix")
    end)

    test("T13: -p absolute shows full paths", function()
        local ok, stdout, _ = runPmc(TD .. " -p absolute")
        expect(ok, "exit non-zero")
        if IS_WINDOWS then
            -- windows absolute paths contain :\  or :/
            expect(stdout:find("PATH: [A-Za-z]:") ~= nil, "missing drive letter in absolute path")
        else
            expect(contains(stdout, "PATH: /"), "missing leading / in absolute path")
        end
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 5: Tree and Stats
    -- =========================================================================
    io.write("[GROUP 5] Tree and Stats\n")

    test("T14: -t outputs tree structure", function()
        local ok, stdout, _ = runPmc(TD .. " -t")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "|--") or contains(stdout, "`--"), "missing tree branch markers")
    end)

    test("T15: -t tree starts with dot root", function()
        local ok, stdout, _ = runPmc(TD .. " -t")
        expect(ok, "exit non-zero")
        local first_line = stdout:match("^([^\n]*)")
        expect(first_line and trim(first_line) == ".", "tree should start with .")
    end)

    test("T16: -t tree contains directory names", function()
        local ok, stdout, _ = runPmc(TD .. " -t")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "src/"), "tree should contain src/")
        expect(contains(stdout, "docs/"), "tree should contain docs/")
    end)

    test("T17: -s outputs STATS header", function()
        local ok, stdout, _ = runPmc(TD .. " -s")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "STATS:"), "missing STATS header")
    end)

    test("T18: -s outputs total_files and total_lines", function()
        local ok, stdout, _ = runPmc(TD .. " -s")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "total_files:"), "missing total_files")
        expect(contains(stdout, "total_lines:"), "missing total_lines")
    end)

    test("T19: -s outputs lines_by_suffix", function()
        local ok, stdout, _ = runPmc(TD .. " -s")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "lines_by_suffix:"), "missing lines_by_suffix")
        expect(contains(stdout, ".lua:"), "missing .lua suffix stat")
    end)

    test("T20: -t -s combined includes both", function()
        local ok, stdout, _ = runPmc(TD .. " -t -s")
        expect(ok, "exit non-zero")
        -- tree at the top
        expect(contains(stdout, "|--") or contains(stdout, "`--"), "missing tree markers")
        -- stats at the bottom
        expect(contains(stdout, "STATS:"), "missing STATS section")
        -- verify tree comes before stats
        local tree_pos = stdout:find("|--", 1, true) or stdout:find("`--", 1, true) or 0
        local stats_pos = stdout:find("STATS:", 1, true) or 0
        expect(tree_pos < stats_pos, "tree should come before stats")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 6: Exclude patterns
    -- =========================================================================
    io.write("[GROUP 6] Exclude patterns (-x)\n")

    test("T21: -x *.py excludes python files", function()
        local ok, stdout, _ = runPmc(TD .. " -x " .. sq("*.py"))
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "helper.py"), "helper.py should be excluded")
        expect(contains(stdout, "main.lua"), "main.lua should remain")
    end)

    test("T22: -x docs/ excludes directory", function()
        local ok, stdout, _ = runPmc(TD .. " -x " .. sq("docs/"))
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "readme.md"), "docs/readme.md should be excluded")
        expect(contains(stdout, "main.lua"), "main.lua should remain")
    end)

    test("T23: -x comma-separated patterns", function()
        local ok, stdout, _ = runPmc(TD .. " -x " .. sq("*.py,*.txt"))
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "helper.py"), "helper.py should be excluded")
        expect(notContains(stdout, "data.txt"), "data.txt should be excluded")
        expect(notContains(stdout, "empty.txt"), "empty.txt should be excluded")
        expect(contains(stdout, "main.lua"), "main.lua should remain")
    end)

    test("T24: -x repeated flags", function()
        local ok, stdout, _ = runPmc(TD .. " -x " .. sq("*.py") .. " -x " .. sq("*.txt"))
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "helper.py"), "helper.py should be excluded")
        expect(notContains(stdout, "data.txt"), "data.txt should be excluded")
        expect(contains(stdout, "main.lua"), "main.lua should remain")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 7: Include patterns
    -- =========================================================================
    io.write("[GROUP 7] Include patterns (-m)\n")

    test("T25: -m *.lua includes only lua files", function()
        local ok, stdout, _ = runPmc(TD .. " -m " .. sq("*.lua"))
        expect(ok, "exit non-zero")
        expect(contains(stdout, "main.lua"), "main.lua should be included")
        expect(contains(stdout, "utils.lua"), "utils.lua should be included")
        expect(contains(stdout, "inner.lua"), "inner.lua should be included")
        expect(notContains(stdout, "helper.py"), "helper.py should not be included")
        expect(notContains(stdout, "config.json"), "config.json should not be included")
    end)

    test("T26: -m src/ includes only src directory", function()
        local ok, stdout, _ = runPmc(TD .. " -m " .. sq("src/"))
        expect(ok, "exit non-zero")
        expect(contains(stdout, "main.lua"), "src/main.lua should be included")
        expect(contains(stdout, "helper.py"), "src/helper.py should be included")
        expect(notContains(stdout, "config.json"), "config.json should not be included")
        expect(notContains(stdout, "readme.md"), "docs/readme.md should not be included")
    end)

    test("T27: -m + -x priority (-x wins over -m)", function()
        local ok, stdout, _ = runPmc(TD .. " -m " .. sq("*.lua") .. " -x " .. sq("utils.lua"))
        expect(ok, "exit non-zero")
        expect(contains(stdout, "main.lua"), "main.lua should be included")
        expect(contains(stdout, "inner.lua"), "inner.lua should be included")
        expect(notContains(stdout, "utils.lua"), "-x should override -m for utils.lua")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 8: Raw mode (-r)
    -- =========================================================================
    io.write("[GROUP 8] Raw mode (-r)\n")

    test("T28: -r produces output", function()
        local ok, stdout, _ = runPmc(TD .. " -r")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "PATH: "), "missing PATH header")
        expect(contains(stdout, "main.lua"), "missing main.lua")
    end)

    test("T29: -r includes gitignored .log file", function()
        local ok, stdout, _ = runPmc(TD .. " -r")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "debug.log"), "debug.log should appear in raw mode")
    end)

    test("T30: -r includes gitignored directory contents", function()
        local ok, stdout, _ = runPmc(TD .. " -r")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "secret.txt"), "ignored_dir/secret.txt should appear in raw mode")
    end)

    test("T31: -r still skips binary extensions", function()
        local ok, stdout, _ = runPmc(TD .. " -r")
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "image.png"), "binary ext should still be skipped in raw mode")
    end)

    test("T32: -r auto-excludes .git directory", function()
        local ok, stdout, _ = runPmc(TD .. " -r")
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "COMMIT_EDITMSG"), ".git/ internals should be excluded")
        expect(notContains(stdout, "HEAD"), ".git/HEAD should be excluded")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 9: Output redirection (-o)
    -- =========================================================================
    io.write("[GROUP 9] Output redirection (-o)\n")

    test("T33: -o writes output to file", function()
        os.remove(OUTPUT_MD)
        local ok, stdout, _ = runPmc(TD .. " -o " .. sq(OUTPUT_MD))
        expect(ok, "exit non-zero")
        expect(fileExists(OUTPUT_MD), "output file should exist")
        local content = readFile(OUTPUT_MD)
        expect(content and #content > 0, "output file should have content")
        os.remove(OUTPUT_MD)
    end)

    test("T34: -o stdout is empty", function()
        os.remove(OUTPUT_MD)
        local ok, stdout, _ = runPmc(TD .. " -o " .. sq(OUTPUT_MD))
        expect(ok, "exit non-zero")
        expect(trim(stdout) == "", "stdout should be empty with -o")
        os.remove(OUTPUT_MD)
    end)

    test("T35: -o file content matches direct stdout", function()
        -- Run without -o to get stdout
        local ok1, stdout1, _ = runPmc(TD)
        expect(ok1, "direct run failed")

        -- Run with -o
        os.remove(OUTPUT_MD)
        local ok2, _, _ = runPmc(TD .. " -o " .. sq(OUTPUT_MD))
        expect(ok2, "redirect run failed")

        local file_content = readFile(OUTPUT_MD) or ""
        file_content = file_content:gsub("\r\n", "\n"):gsub("\r", "\n")
        expect(trim(stdout1) == trim(file_content), "file content should match stdout")
        os.remove(OUTPUT_MD)
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 10: YAML mode (-y)
    -- =========================================================================
    io.write("[GROUP 10] YAML mode (-y)\n")

    test("T36: -y -o creates yaml file", function()
        os.remove(OUTPUT_YAML)
        local ok, stdout, _ = runPmc(TD .. " -y -o " .. sq(OUTPUT_YAML))
        expect(ok, "exit non-zero")
        expect(fileExists(OUTPUT_YAML), "yaml file should exist")
        local content = readFile(OUTPUT_YAML)
        expect(content and #content > 0, "yaml file should have content")
        os.remove(OUTPUT_YAML)
    end)

    test("T37: -y output has type: directory root", function()
        os.remove(OUTPUT_YAML)
        local ok, _, _ = runPmc(TD .. " -y -o " .. sq(OUTPUT_YAML))
        expect(ok, "exit non-zero")
        local content = readFile(OUTPUT_YAML) or ""
        content = content:gsub("\r\n", "\n")
        expect(contains(content, "type: directory"), "missing type: directory")
        expect(contains(content, "children:"), "missing children:")
        os.remove(OUTPUT_YAML)
    end)

    test("T38: -y output has file entries with content", function()
        os.remove(OUTPUT_YAML)
        local ok, _, _ = runPmc(TD .. " -y -o " .. sq(OUTPUT_YAML))
        expect(ok, "exit non-zero")
        local content = readFile(OUTPUT_YAML) or ""
        content = content:gsub("\r\n", "\n")
        expect(contains(content, "type: file"), "missing type: file")
        expect(contains(content, "content: |-"), "missing content: |-")
        expect(contains(content, "main.lua"), "missing main.lua in yaml")
        os.remove(OUTPUT_YAML)
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 11: Error handling
    -- =========================================================================
    io.write("[GROUP 11] Error handling\n")

    test("T39: error: -y without -o", function()
        local ok, _, stderr = runPmc(TD .. " -y")
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
    end)

    test("T40: error: -y with -t", function()
        os.remove(OUTPUT_YAML)
        local ok, _, stderr = runPmc(TD .. " -y -t -o " .. sq(OUTPUT_YAML))
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
        os.remove(OUTPUT_YAML)
    end)

    test("T41: error: -y with -s", function()
        os.remove(OUTPUT_YAML)
        local ok, _, stderr = runPmc(TD .. " -y -s -o " .. sq(OUTPUT_YAML))
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
        os.remove(OUTPUT_YAML)
    end)

    test("T42: error: -y with -w", function()
        os.remove(OUTPUT_YAML)
        local ok, _, stderr = runPmc(TD .. " -y -w nil -o " .. sq(OUTPUT_YAML))
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
        os.remove(OUTPUT_YAML)
    end)

    test("T43: error: -y with -p", function()
        os.remove(OUTPUT_YAML)
        local ok, _, stderr = runPmc(TD .. " -y -p name -o " .. sq(OUTPUT_YAML))
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
        os.remove(OUTPUT_YAML)
    end)

    test("T44: error: -y -o with non-yaml extension", function()
        local ok, _, stderr = runPmc(TD .. " -y -o " .. sq("_test_bad.txt"))
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
        os.remove("_test_bad.txt")
    end)

    test("T45: error: unknown option", function()
        local ok, _, stderr = runPmc(TD .. " -z")
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
    end)

    test("T46: error: -w with invalid mode", function()
        local ok, _, stderr = runPmc(TD .. " -w banana")
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
    end)

    test("T47: error: -p with invalid mode", function()
        local ok, _, stderr = runPmc(TD .. " -p banana")
        expect(not ok, "should fail")
        expect(contains(stderr, "err:("), "missing error prefix")
    end)

    io.write("\n")

    -- =========================================================================
    -- Group 12: Edge cases
    -- =========================================================================
    io.write("[GROUP 12] Edge cases\n")

    test("T48: empty file is included in output", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(contains(stdout, "empty.txt"), "empty.txt should appear")
    end)

    test("T49: nested deep file found", function()
        local ok, stdout, _ = runPmc(TD)
        expect(ok, "exit non-zero")
        expect(contains(stdout, "inner.lua"), "nested/deep/inner.lua should appear")
    end)

    test("T50: md fence includes language (lua)", function()
        local ok, stdout, _ = runPmc(TD .. " -w md")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "````lua"), "should have ````lua fence")
    end)

    test("T51: md fence includes language (python)", function()
        local ok, stdout, _ = runPmc(TD .. " -w md")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "````python"), "should have ````python fence")
    end)

    test("T52: md fence includes language (makefile)", function()
        local ok, stdout, _ = runPmc(TD .. " -w md")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "````makefile"), "should have ````makefile fence")
    end)

    test("T53: md fence includes language (markdown)", function()
        local ok, stdout, _ = runPmc(TD .. " -w md")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "````markdown"), "should have ````markdown fence")
    end)

    test("T54: file content is correct in output", function()
        local ok, stdout, _ = runPmc(TD .. " -w nil")
        expect(ok, "exit non-zero")
        -- Check content from inner.lua
        expect(contains(stdout, "return 42"), "inner.lua content should be present")
        -- Check content from config.json
        expect(contains(stdout, '"key"'), "config.json content should be present")
    end)

    test("T55: -x with extension shorthand .py", function()
        local ok, stdout, _ = runPmc(TD .. " -x " .. sq(".py"))
        expect(ok, "exit non-zero")
        expect(notContains(stdout, "helper.py"), ".py should be excluded by shorthand")
        expect(contains(stdout, "main.lua"), "non-.py files should remain")
    end)

    test("T56: -r -w block combined", function()
        local ok, stdout, _ = runPmc(TD .. " -r -w block")
        expect(ok, "exit non-zero")
        expect(contains(stdout, "<<<FILE "), "missing block markers in -r -w block")
        expect(contains(stdout, ">>>END"), "missing >>>END in -r -w block")
        expect(contains(stdout, "debug.log"), "debug.log should appear in raw mode")
    end)

    test("T57: -m with comma-separated mixed patterns", function()
        local ok, stdout, _ = runPmc(TD .. " -m " .. sq("src/,*.json"))
        expect(ok, "exit non-zero")
        expect(contains(stdout, "main.lua"), "src/main.lua should be included")
        expect(contains(stdout, "helper.py"), "src/helper.py should be included")
        expect(contains(stdout, "config.json"), "config.json should be included")
        expect(notContains(stdout, "readme.md"), "docs/readme.md should not be included")
        expect(notContains(stdout, "data.txt"), "data.txt should not be included")
    end)

    test("T58: -t -s -w nil -p name combined", function()
        local ok, stdout, _ = runPmc(TD .. " -t -s -w nil -p name")
        expect(ok, "exit non-zero")
        -- tree present
        expect(contains(stdout, "|--") or contains(stdout, "`--"), "missing tree markers")
        -- stats present
        expect(contains(stdout, "STATS:"), "missing STATS")
        -- no fences (nil mode)
        expect(notContains(stdout, "````"), "should have no fences in nil mode")
        -- name-only paths
        expect(contains(stdout, "PATH: main.lua"), "should show name-only path")
    end)

    io.write("\n")

    -- =========================================================================
    -- Summary
    -- =========================================================================
    io.write("==================================================\n")
    io.write(string.format("  Results: %d / %d passed", passed, total))
    if failed > 0 then
        io.write(string.format(", %d FAILED", failed))
    end
    io.write("\n")

    if #fail_names > 0 then
        io.write("\n  Failed tests:\n")
        for _, name in ipairs(fail_names) do
            io.write("    - " .. name .. "\n")
        end
    end

    io.write("==================================================\n")

    -- =========================================================================
    -- Cleanup
    -- =========================================================================
    cleanupAll()

    if failed > 0 then
        os.exit(1)
    end
end

-- Run with pcall to ensure cleanup even on unexpected errors
local run_ok, run_err = pcall(main)
if not run_ok then
    io.write("\nFATAL ERROR: " .. tostring(run_err) .. "\n")
    cleanupAll()
    os.exit(2)
end