--@description: pmc - pack-my-code, a minimalist code context packaging tool
--@author: WaterRun
--@file: pmc.lua
--@date: 2026-03-08
--@updated: 2026-03-09

-- =============================================================================
-- Type annotations
-- =============================================================================

---@class PmcOptions
---@field target_dir string
---@field exclude_patterns string[]
---@field include_patterns string[]
---@field ignore_gitignore boolean
---@field with_tree boolean
---@field with_stats boolean
---@field wrap_mode "md"|"nil"|"block"
---@field path_mode "relative"|"name"|"absolute"
---@field yaml_mode boolean
---@field output_file string|nil
---@field show_version boolean
---@field show_help boolean
---@field user_set_t boolean
---@field user_set_s boolean
---@field user_set_w boolean
---@field user_set_p boolean

---@class FileItem
---@field abs_path string
---@field rel_target string
---@field display_path string
---@field content string
---@field line_count integer
---@field ext_key string
---@field lang string

---@class TreeNode
---@field name string
---@field kind "dir"|"file"
---@field order integer
---@field rel_path string|nil
---@field children table<string,TreeNode>|nil
---@field files table<string,TreeNode>|nil

-- =============================================================================
-- Constants
-- =============================================================================

local VERSION = "1"

local MAX_FILE_SIZE = 1024 * 1024 -- 1 MB

local DIR_SEP = package.config:sub(1, 1)
local IS_WINDOWS = (DIR_SEP == "\\")

local WRITE_CHUNK_SIZE = 4096

-- =============================================================================
-- Lookup tables
-- =============================================================================

--@description: known no-extension filenames for stats grouping
local KNOWN_NO_EXT = {
    ["makefile"] = true,
    ["gnumakefile"] = true,
    ["dockerfile"] = true,
    ["containerfile"] = true,
    ["vagrantfile"] = true,
    ["jenkinsfile"] = true,
    ["readme"] = true,
    ["license"] = true,
    ["copying"] = true,
    ["changelog"] = true,
    ["authors"] = true,
    ["contributors"] = true,
    ["gemfile"] = true,
    ["rakefile"] = true,
    ["guardfile"] = true,
    ["procfile"] = true,
    ["brewfile"] = true,
    ["cmakelists.txt"] = true,
}

--@description: binary file extensions - skip without reading content
local BINARY_EXTENSIONS = {}
do
    local exts = {
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp",
        ".tiff", ".tga", ".psd", ".ai", ".eps", ".svg",
        ".mp3", ".mp4", ".wav", ".avi", ".mov", ".mkv", ".flv",
        ".ogg", ".flac", ".aac", ".wma", ".wmv", ".m4a", ".m4v",
        ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".zst",
        ".exe", ".dll", ".so", ".dylib", ".o", ".obj", ".a", ".lib",
        ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
        ".wasm", ".class", ".pyc", ".pyo", ".elc",
        ".ttf", ".otf", ".woff", ".woff2", ".eot",
        ".sqlite", ".db", ".mdb", ".ldb",
        ".jar", ".war", ".ear", ".apk", ".ipa", ".deb", ".rpm",
        ".iso", ".dmg", ".img", ".bin", ".dat",
        ".min.js", ".min.css",
    }
    for _, ext in ipairs(exts) do
        BINARY_EXTENSIONS[ext] = true
    end
end

--@description: language detection by file extension
local LANG_BY_EXT = {
    [".lua"] = "lua",
    [".py"] = "python",
    [".pyw"] = "python",
    [".pyi"] = "python",
    [".js"] = "javascript",
    [".mjs"] = "javascript",
    [".cjs"] = "javascript",
    [".ts"] = "typescript",
    [".mts"] = "typescript",
    [".cts"] = "typescript",
    [".jsx"] = "jsx",
    [".tsx"] = "tsx",
    [".sh"] = "bash",
    [".bash"] = "bash",
    [".zsh"] = "zsh",
    [".fish"] = "fish",
    [".rb"] = "ruby",
    [".erb"] = "erb",
    [".go"] = "go",
    [".rs"] = "rust",
    [".c"] = "c",
    [".h"] = "c",
    [".cpp"] = "cpp",
    [".cc"] = "cpp",
    [".cxx"] = "cpp",
    [".hpp"] = "cpp",
    [".hxx"] = "cpp",
    [".hh"] = "cpp",
    [".java"] = "java",
    [".cs"] = "csharp",
    [".fs"] = "fsharp",
    [".fsx"] = "fsharp",
    [".php"] = "php",
    [".html"] = "html",
    [".htm"] = "html",
    [".xhtml"] = "html",
    [".css"] = "css",
    [".scss"] = "scss",
    [".less"] = "less",
    [".sass"] = "sass",
    [".json"] = "json",
    [".jsonc"] = "jsonc",
    [".json5"] = "json5",
    [".xml"] = "xml",
    [".xsl"] = "xml",
    [".xsd"] = "xml",
    [".yaml"] = "yaml",
    [".yml"] = "yaml",
    [".toml"] = "toml",
    [".ini"] = "ini",
    [".cfg"] = "ini",
    [".conf"] = "ini",
    [".sql"] = "sql",
    [".md"] = "markdown",
    [".markdown"] = "markdown",
    [".rst"] = "rst",
    [".tex"] = "latex",
    [".sty"] = "latex",
    [".cls"] = "latex",
    [".vue"] = "vue",
    [".svelte"] = "svelte",
    [".swift"] = "swift",
    [".kt"] = "kotlin",
    [".kts"] = "kotlin",
    [".scala"] = "scala",
    [".sc"] = "scala",
    [".clj"] = "clojure",
    [".cljs"] = "clojure",
    [".cljc"] = "clojure",
    [".r"] = "r",
    [".dart"] = "dart",
    [".ex"] = "elixir",
    [".exs"] = "elixir",
    [".erl"] = "erlang",
    [".hrl"] = "erlang",
    [".hs"] = "haskell",
    [".lhs"] = "haskell",
    [".pl"] = "perl",
    [".pm"] = "perl",
    [".ps1"] = "powershell",
    [".psm1"] = "powershell",
    [".psd1"] = "powershell",
    [".bat"] = "batch",
    [".cmd"] = "batch",
    [".cmake"] = "cmake",
    [".tf"] = "terraform",
    [".hcl"] = "hcl",
    [".proto"] = "protobuf",
    [".graphql"] = "graphql",
    [".gql"] = "graphql",
    [".txt"] = "text",
    [".log"] = "text",
    [".env"] = "dotenv",
    [".zig"] = "zig",
    [".nim"] = "nim",
    [".v"] = "v",
    [".groovy"] = "groovy",
    [".gradle"] = "groovy",
    [".m"] = "objectivec",
    [".mm"] = "objectivec",
    [".d"] = "d",
    [".jl"] = "julia",
    [".ml"] = "ocaml",
    [".mli"] = "ocaml",
    [".lisp"] = "lisp",
    [".cl"] = "lisp",
    [".el"] = "elisp",
    [".scm"] = "scheme",
    [".rkt"] = "racket",
    [".asm"] = "asm",
    [".s"] = "asm",
    [".glsl"] = "glsl",
    [".hlsl"] = "hlsl",
    [".wgsl"] = "wgsl",
    [".dockerfile"] = "dockerfile",
}

--@description: language detection by special filename
local LANG_BY_NAME = {
    ["makefile"] = "makefile",
    ["gnumakefile"] = "makefile",
    ["dockerfile"] = "dockerfile",
    ["containerfile"] = "dockerfile",
    ["vagrantfile"] = "ruby",
    ["gemfile"] = "ruby",
    ["rakefile"] = "ruby",
    ["guardfile"] = "ruby",
    ["jenkinsfile"] = "groovy",
    ["cmakelists.txt"] = "cmake",
    [".gitignore"] = "gitignore",
    [".gitattributes"] = "gitignore",
    [".gitmodules"] = "gitignore",
    [".dockerignore"] = "gitignore",
    [".hgignore"] = "gitignore",
    [".editorconfig"] = "ini",
    [".env"] = "dotenv",
    [".env.local"] = "dotenv",
    [".env.development"] = "dotenv",
    [".env.production"] = "dotenv",
    [".babelrc"] = "json",
    [".eslintrc"] = "json",
    [".prettierrc"] = "json",
    ["package.json"] = "json",
    ["tsconfig.json"] = "json",
    ["cargo.toml"] = "toml",
    ["pyproject.toml"] = "toml",
    ["go.mod"] = "gomod",
    ["go.sum"] = "gosum",
}

--@description: default exclude patterns applied in -r (raw scan) mode
local DEFAULT_RAW_EXCLUDES = {
    ".git/", ".svn/", ".hg/",
    "node_modules/", "__pycache__/", ".tox/", ".mypy_cache/",
    ".vscode/", ".idea/", ".vs/",
    "*.lock",
}

--@description: lua pattern magic characters
local LUA_MAGIC_CHARS = {
    ["^"] = true,
    ["$"] = true,
    ["("] = true,
    [")"] = true,
    ["%"] = true,
    ["."] = true,
    ["["] = true,
    ["]"] = true,
    ["+"] = true,
    ["-"] = true,
    ["*"] = true,
    ["?"] = true,
}

-- =============================================================================
-- Utility functions
-- =============================================================================

--@description: fail with standardized error format and exit
local function fail(message)
    io.stderr:write(string.format("err:( %s )\n", message))
    io.stderr:flush()
    os.exit(1)
end

--@description: print warning to stderr
local function warn(message)
    io.stderr:write(string.format("warn: %s\n", message))
    io.stderr:flush()
end

--@description: trim leading and trailing whitespace
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--@description: normalize path separators to forward slash, collapse duplicates
local function normalizePath(p)
    local s = p:gsub("\\", "/")
    s = s:gsub("/+", "/")
    if #s > 1 then
        s = s:gsub("/$", "")
    end
    return s
end

--@description: normalize pattern separators; keep trailing slash semantics
local function normalizePattern(p)
    local s = p:gsub("\\", "/")
    s = s:gsub("/+", "/")
    return s
end

--@description: check whether string starts with prefix
local function startsWith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

--@description: check whether string ends with suffix
local function endsWith(s, suffix)
    if suffix == "" then return true end
    return s:sub(- #suffix) == suffix
end

--@description: split string by literal delimiter
local function splitByChar(s, delim)
    local out = {}
    local start_i = 1
    while true do
        local i, j = s:find(delim, start_i, true)
        if not i then
            table.insert(out, s:sub(start_i))
            break
        end
        table.insert(out, s:sub(start_i, i - 1))
        start_i = j + 1
    end
    return out
end

--@description: extract basename from normalized path
local function baseName(p)
    local s = normalizePath(p)
    local i = s:match("^.*()/")
    if i then return s:sub(i + 1) end
    return s
end

--@description: extract file extension including the dot, or nil
local function fileExtension(name)
    return name:match("^.+(%.[^%.]+)$")
end

--@description: check if filename has a real extension (not just a leading dot)
local function hasExtension(name)
    local i = name:match("^.*()%.")
    if not i then return false end
    if i == 1 then return false end
    return i < #name
end

-- =============================================================================
-- Safe output writing (chunked to prevent Windows console truncation)
-- =============================================================================

--@description: write string in safe-sized chunks
local function safeWrite(handle, s)
    if s == "" then return end
    if #s <= WRITE_CHUNK_SIZE then
        handle:write(s)
        return
    end
    local pos = 1
    while pos <= #s do
        local end_pos = pos + WRITE_CHUNK_SIZE - 1
        if end_pos > #s then end_pos = #s end
        handle:write(s:sub(pos, end_pos))
        pos = end_pos + 1
    end
end

-- =============================================================================
-- Shell and command utilities
-- =============================================================================

--@description: shell-quote a string for the current platform
local function shellQuote(s)
    if IS_WINDOWS then
        return "\"" .. s:gsub("\"", "\"\"") .. "\""
    end
    return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

--@description: run shell command, capture stdout
local function runCommand(cmd)
    local pipe, err = io.popen(cmd, "r")
    if not pipe then
        return false, "", err or "popen failed"
    end
    local data = pipe:read("*a") or ""
    local ok, why, code = pipe:close()
    if ok == nil then
        return false, data, code or why or "command failed"
    end
    return true, data, 0
end

-- =============================================================================
-- Path utilities
-- =============================================================================

--@description: resolve absolute path via shell
local function getAbsolutePath(p)
    if IS_WINDOWS then
        local cmd = "cd /d " .. shellQuote(p) .. " 2>nul && cd"
        local ok, out = runCommand(cmd)
        if not ok then fail("cannot resolve absolute path: " .. p) end
        local line = trim(out:gsub("\r", ""))
        if line == "" then fail("cannot resolve absolute path: " .. p) end
        return normalizePath(line)
    end
    local cmd = "cd " .. shellQuote(p) .. " 2>/dev/null && pwd"
    local ok, out = runCommand(cmd)
    if not ok then fail("cannot resolve absolute path: " .. p) end
    local line = trim(out)
    if line == "" then fail("cannot resolve absolute path: " .. p) end
    return normalizePath(line)
end

--@description: get current working directory
local function getCwd()
    if IS_WINDOWS then
        local ok, out = runCommand("cd")
        if not ok then fail("cannot get current directory") end
        return normalizePath(trim(out:gsub("\r", "")))
    end
    local ok, out = runCommand("pwd")
    if not ok then fail("cannot get current directory") end
    return normalizePath(trim(out))
end

--@description: split path into segments
local function splitPathSegments(p)
    local segs = {}
    for seg in normalizePath(p):gmatch("[^/]+") do
        table.insert(segs, seg)
    end
    return segs
end

--@description: compute relative path from base to target
local function relativePath(base_abs, target_abs)
    local base = splitPathSegments(base_abs)
    local targ = splitPathSegments(target_abs)
    local i = 1
    while i <= #base and i <= #targ and base[i] == targ[i] do
        i = i + 1
    end
    local out = {}
    for _ = i, #base do table.insert(out, "..") end
    for j = i, #targ do table.insert(out, targ[j]) end
    if #out == 0 then return "." end
    return table.concat(out, "/")
end

--@description: make path relative to target directory
local function toTargetRelative(target_abs, file_abs)
    local t = normalizePath(target_abs)
    local f = normalizePath(file_abs)
    if f == t then return "." end
    if startsWith(f, t .. "/") then return f:sub(#t + 2) end
    return relativePath(t, f)
end

--@description: format display path according to path mode
local function formatDisplayPath(path_mode, cwd_abs, file_abs)
    if path_mode == "absolute" then return normalizePath(file_abs) end
    if path_mode == "name" then return baseName(file_abs) end
    return relativePath(cwd_abs, normalizePath(file_abs))
end

-- =============================================================================
-- Language detection
-- =============================================================================

--@description: detect programming language from file path
local function detectLang(rel_path)
    local name = baseName(rel_path)
    local lower_name = name:lower()

    -- special filenames first
    local special = LANG_BY_NAME[lower_name]
    if special then return special end

    -- check for .min.js / .min.css compound extensions
    if endsWith(lower_name, ".min.js") then return "javascript" end
    if endsWith(lower_name, ".min.css") then return "css" end

    -- standard extension lookup
    local ext = fileExtension(name)
    if ext then
        local lang = LANG_BY_EXT[ext:lower()]
        if lang then return lang end
        -- case-sensitive fallback (e.g. .R)
        lang = LANG_BY_EXT[ext]
        if lang then return lang end
    end

    return ""
end

-- =============================================================================
-- File inspection
-- =============================================================================

--@description: check if file has a known binary extension
local function isBinaryExtension(rel_path)
    local name = baseName(rel_path):lower()
    -- check compound extensions first
    if endsWith(name, ".min.js") or endsWith(name, ".min.css") then
        return true
    end
    local ext = fileExtension(name)
    if not ext then return false end
    return BINARY_EXTENSIONS[ext] == true
end

--@description: get file size in bytes, or nil on error
local function getFileSize(abs_path)
    local f = io.open(abs_path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end

--@description: read entire file as binary-safe string
local function readFile(abs_path)
    local f, err = io.open(abs_path, "rb")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()
    return data or "", nil
end

--@description: heuristic text detection by null-byte sniffing in the first 8KB
local function isTextContent(data)
    local check_len = math.min(#data, 8192)
    local chunk = data:sub(1, check_len)
    return not chunk:find("\0", 1, true)
end

--@description: normalize all line endings to LF
local function normalizeLineEndings(data)
    return data:gsub("\r\n", "\n"):gsub("\r", "\n")
end

--@description: count lines in LF-normalized content
local function countLines(content)
    if content == "" then return 0 end
    local n = 0
    for _ in content:gmatch("[^\n]*\n") do
        n = n + 1
    end
    if content:sub(-1) ~= "\n" then
        n = n + 1
    end
    return n
end

--@description: extension key for statistics grouping
local function detectExtKey(rel_path)
    local bn = baseName(rel_path)
    local lower_bn = bn:lower()
    if not hasExtension(bn) then
        if KNOWN_NO_EXT[lower_bn] then return "[no_ext:known]" end
        return "[no_ext:unknown]"
    end
    local ext = bn:match("^.+(%.[^%.]+)$")
    if not ext then return "[no_ext:unknown]" end
    return ext:lower()
end

-- =============================================================================
-- Pattern matching
-- =============================================================================

--@description: escape one lua pattern magic character
local function escapeLuaMagic(ch)
    if LUA_MAGIC_CHARS[ch] then return "%" .. ch end
    return ch
end

--@description: convert a glob pattern to a lua pattern string
--  Supports: * (any non-slash chars), ** (any chars including slash), ? (single non-slash char)
local function globToLuaPattern(s)
    local out = { "^" }
    local i = 1
    while i <= #s do
        local ch = s:sub(i, i)
        if ch == "*" then
            if s:sub(i + 1, i + 1) == "*" then
                -- ** matches everything including /
                table.insert(out, ".*")
                i = i + 2
                -- consume one optional / after **
                if i <= #s and s:sub(i, i) == "/" then
                    -- ** already covers /, so we make the slash optional
                    table.insert(out, "/?")
                    i = i + 1
                end
            else
                -- single * matches everything except /
                table.insert(out, "[^/]*")
                i = i + 1
            end
        elseif ch == "?" then
            table.insert(out, "[^/]")
            i = i + 1
        else
            table.insert(out, escapeLuaMagic(ch))
            i = i + 1
        end
    end
    table.insert(out, "$")
    return table.concat(out)
end

--@description: check if pattern contains wildcard characters
local function hasWildcard(p)
    return p:find("*", 1, true) ~= nil or p:find("?", 1, true) ~= nil
end

--@description: check if a directory segment appears in any parent directory of the path
local function hasPathSegment(rel_path, seg)
    local parts = splitByChar(rel_path, "/")
    for i = 1, (#parts - 1) do
        if parts[i] == seg then return true end
    end
    return false
end

--@description: match a single include/exclude pattern against a target-relative path
local function matchOnePattern(rel_path, pattern)
    local rp = normalizePath(rel_path)
    local pt = normalizePattern(pattern)
    local is_dir_pattern = endsWith(pt, "/")
    local bname = baseName(rp)

    -- directory patterns (trailing /)
    if is_dir_pattern then
        local d = pt:sub(1, -2)
        if d == "" then return false end
        if d:find("/", 1, true) then
            return startsWith(rp, d .. "/")
        end
        if startsWith(rp, d .. "/") then return true end
        return hasPathSegment(rp, d)
    end

    -- patterns containing /  -> match against full relative path
    if pt:find("/", 1, true) then
        if hasWildcard(pt) then
            return rp:match(globToLuaPattern(pt)) ~= nil
        end
        return rp == pt
    end

    -- no-slash patterns with wildcards -> match basename, fallback full path
    if hasWildcard(pt) then
        local lp = globToLuaPattern(pt)
        if bname:match(lp) then return true end
        return rp:match(lp) ~= nil
    end

    -- extension shorthand like ".lua"
    if startsWith(pt, ".") then
        return endsWith(bname:lower(), pt:lower())
    end

    -- literal name match
    return bname == pt or rp == pt
end

--@description: check if any pattern in list matches the path
local function matchPatterns(rel_path, patterns)
    for _, p in ipairs(patterns) do
        if matchOnePattern(rel_path, p) then return true end
    end
    return false
end

-- =============================================================================
-- Pattern parsing
-- =============================================================================

--@description: parse comma-separated pattern string into a list
local function parsePatternList(raw)
    local patterns = {}
    if not raw or raw == "" then return patterns end
    local parts = splitByChar(raw, ",")
    for _, part in ipairs(parts) do
        local p = trim(part)
        if p ~= "" then
            p = normalizePattern(p)
            table.insert(patterns, p)
        end
    end
    return patterns
end

-- =============================================================================
-- Git integration
-- =============================================================================

--@description: check if git is available
local function hasGit()
    local ok = runCommand("git --version")
    return ok
end

--@description: split null-byte separated string (replaces %z pattern for Lua 5.2+ compat)
local function splitNullSeparated(s)
    local items = {}
    local start = 1
    for i = 1, #s do
        if s:byte(i) == 0 then
            local item = s:sub(start, i - 1)
            if item ~= "" then
                table.insert(items, item)
            end
            start = i + 1
        end
    end
    if start <= #s then
        local item = s:sub(start)
        if item ~= "" then
            table.insert(items, item)
        end
    end
    return items
end

--@description: list tracked + untracked files via git, respecting .gitignore
local function listFilesWithGit(target_abs)
    if not hasGit() then
        fail("git is required for default mode; use -r to scan directly")
    end

    local ok_repo, repo_out = runCommand(
        "git -C " .. shellQuote(target_abs) .. " rev-parse --show-toplevel"
    )
    if not ok_repo then
        fail("target is not inside a git work tree; use -r to scan directly")
    end
    local root_abs = normalizePath(trim(repo_out:gsub("\r", "")))
    if root_abs == "" then
        fail("failed to get git repository root")
    end

    local target_norm = normalizePath(target_abs)
    local rel_target = ""
    if target_norm ~= root_abs then
        if not startsWith(target_norm, root_abs .. "/") then
            fail("target path is outside repository root")
        end
        rel_target = target_norm:sub(#root_abs + 2)
    end

    -- On Windows: use newline-separated output to avoid io.popen text-mode 0x1A
    --             (NTFS does not allow \n in filenames, so newline split is safe)
    -- On Unix:    use null-separated output (filenames can contain \n)
    local raw_items
    if IS_WINDOWS then
        local ok_list, list_out = runCommand(
            "git -C " .. shellQuote(root_abs) ..
            " ls-files --cached --others --exclude-standard --full-name"
        )
        if not ok_list then
            fail("failed to list files through git")
        end
        raw_items = {}
        list_out = list_out:gsub("\r", "")
        for line in list_out:gmatch("([^\n]+)") do
            table.insert(raw_items, line)
        end
    else
        local ok_list, list_out = runCommand(
            "git -C " .. shellQuote(root_abs) ..
            " ls-files -z --cached --others --exclude-standard --full-name"
        )
        if not ok_list then
            fail("failed to list files through git")
        end
        raw_items = splitNullSeparated(list_out)
    end

    local files = {}
    for _, item in ipairs(raw_items) do
        local rel_repo = normalizePath(item)
        if rel_repo ~= "" then
            local dominated = false
            if rel_target == "" then
                dominated = true
            elseif rel_repo == rel_target or startsWith(rel_repo, rel_target .. "/") then
                dominated = true
            end
            if dominated then
                table.insert(files, normalizePath(root_abs .. "/" .. rel_repo))
            end
        end
    end

    return files
end

-- =============================================================================
-- Direct file scanning (-r mode)
-- =============================================================================

--@description: list files by recursive directory scan
local function listFilesDirect(target_abs)
    local cmd
    if IS_WINDOWS then
        cmd = "dir /a-d /s /b " .. shellQuote(target_abs) .. " 2>nul"
    else
        cmd = "find " .. shellQuote(target_abs) .. " -type f -print 2>/dev/null"
    end

    local ok, out = runCommand(cmd)
    if not ok then
        return {}
    end

    local files = {}
    out = out:gsub("\r", "")
    for line in out:gmatch("([^\n]+)") do
        local p = trim(line)
        if p ~= "" then
            table.insert(files, normalizePath(p))
        end
    end
    return files
end

-- =============================================================================
-- File item building (filtering, reading, normalizing)
-- =============================================================================

--@description: process a single file path into a FileItem, or nil if skipped
local function processOneFile(abs_path, target_abs, effective_excludes, include_patterns,
                              path_mode, cwd_abs)
    local rel_target = toTargetRelative(target_abs, abs_path)
    if rel_target == "." then return nil end

    -- skip known binary extensions without reading
    if isBinaryExtension(rel_target) then return nil end

    -- include filter
    if #include_patterns > 0 then
        if not matchPatterns(rel_target, include_patterns) then return nil end
    end

    -- exclude filter
    if #effective_excludes > 0 then
        if matchPatterns(rel_target, effective_excludes) then return nil end
    end

    -- file size guard
    local size = getFileSize(abs_path)
    if not size then
        warn("cannot access file: " .. abs_path)
        return nil
    end
    if size > MAX_FILE_SIZE then
        warn("skipped (exceeds 1 MB): " .. rel_target)
        return nil
    end
    if size == 0 then
        -- include empty files as-is
        return {
            abs_path = normalizePath(abs_path),
            rel_target = normalizePath(rel_target),
            display_path = formatDisplayPath(path_mode, cwd_abs, abs_path),
            content = "",
            line_count = 0,
            ext_key = detectExtKey(rel_target),
            lang = detectLang(rel_target),
        }
    end

    -- read content
    local data, read_err = readFile(abs_path)
    if not data then
        warn("cannot read file: " .. abs_path .. " (" .. tostring(read_err) .. ")")
        return nil
    end

    -- text/binary check
    if not isTextContent(data) then return nil end

    -- normalize line endings to LF
    data = normalizeLineEndings(data)

    return {
        abs_path = normalizePath(abs_path),
        rel_target = normalizePath(rel_target),
        display_path = formatDisplayPath(path_mode, cwd_abs, abs_path),
        content = data,
        line_count = countLines(data),
        ext_key = detectExtKey(rel_target),
        lang = detectLang(rel_target),
    }
end

--@description: build filtered, sorted list of FileItems from raw file paths
local function buildFileItems(abs_files, target_abs, opt, cwd_abs)
    -- merge default raw-scan excludes when in -r mode
    local effective_excludes = {}
    if opt.ignore_gitignore then
        for _, p in ipairs(DEFAULT_RAW_EXCLUDES) do
            table.insert(effective_excludes, p)
        end
    end
    for _, p in ipairs(opt.exclude_patterns) do
        table.insert(effective_excludes, p)
    end

    table.sort(abs_files, function(a, b)
        return normalizePath(a) < normalizePath(b)
    end)

    local items = {}
    for _, abs_path in ipairs(abs_files) do
        local item = processOneFile(
            abs_path, target_abs, effective_excludes, opt.include_patterns,
            opt.path_mode, cwd_abs
        )
        if item then
            table.insert(items, item)
        end
    end

    table.sort(items, function(a, b)
        return a.rel_target < b.rel_target
    end)

    return items
end

-- =============================================================================
-- Tree building and rendering
-- =============================================================================

--@description: build tree model from sorted file items
local function buildTree(items)
    local root = {
        name = ".",
        kind = "dir",
        order = 1,
        rel_path = nil,
        children = {},
        files = {},
    }

    for i, item in ipairs(items) do
        local parts = splitByChar(item.rel_target, "/")
        local node = root
        node.order = math.min(node.order, i)

        for j = 1, (#parts - 1) do
            local seg = parts[j]
            local child = node.children[seg]
            if not child then
                child = {
                    name = seg,
                    kind = "dir",
                    order = i,
                    rel_path = nil,
                    children = {},
                    files = {},
                }
                node.children[seg] = child
            else
                child.order = math.min(child.order, i)
            end
            node = child
        end

        local fname = parts[#parts]
        node.files[fname] = {
            name = fname,
            kind = "file",
            order = i,
            rel_path = item.rel_target,
            children = nil,
            files = nil,
        }
    end

    return root
end

--@description: collect children of a tree node in display order
local function orderedChildren(node)
    local arr = {}
    if node.children then
        for _, d in pairs(node.children) do table.insert(arr, d) end
    end
    if node.files then
        for _, f in pairs(node.files) do table.insert(arr, f) end
    end
    table.sort(arr, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.kind ~= b.kind then return a.kind == "dir" end
        return a.name < b.name
    end)
    return arr
end

--@description: render tree as ascii art, return list of lines
local function renderTree(root)
    local lines = { "." }

    local function visit(node, prefix, is_last)
        local branch = is_last and "`-- " or "|-- "
        local suffix = (node.kind == "dir") and "/" or ""
        table.insert(lines, prefix .. branch .. node.name .. suffix)

        if node.kind == "dir" then
            local next_prefix = prefix .. (is_last and "    " or "|   ")
            local children = orderedChildren(node)
            for idx, child in ipairs(children) do
                visit(child, next_prefix, idx == #children)
            end
        end
    end

    local top = orderedChildren(root)
    for idx, child in ipairs(top) do
        visit(child, "", idx == #top)
    end

    return lines
end

-- =============================================================================
-- Standard output rendering
-- =============================================================================

--@description: render non-yaml output body, return list of output entries
--  Each entry is a string that may contain embedded newlines (file content).
local function renderStandard(items, opt)
    local out = {}

    for _, item in ipairs(items) do
        -- strip trailing newlines from content for clean output
        local content = item.content:gsub("\n+$", "")

        if opt.wrap_mode == "md" then
            table.insert(out, "PATH: " .. item.display_path)
            table.insert(out, "````" .. item.lang)
            table.insert(out, content)
            table.insert(out, "````")
        elseif opt.wrap_mode == "block" then
            table.insert(out, "<<<FILE " .. item.display_path)
            table.insert(out, content)
            table.insert(out, ">>>END")
        else -- "nil"
            table.insert(out, "PATH: " .. item.display_path)
            table.insert(out, content)
        end
    end

    return out
end

-- =============================================================================
-- Statistics rendering
-- =============================================================================

--@description: render statistics block, return list of lines
local function renderStats(items)
    local total_files = #items
    local total_lines = 0
    local ext_lines = {}

    for _, it in ipairs(items) do
        total_lines = total_lines + it.line_count
        ext_lines[it.ext_key] = (ext_lines[it.ext_key] or 0) + it.line_count
    end

    local keys = {}
    for k, _ in pairs(ext_lines) do table.insert(keys, k) end
    table.sort(keys)

    local lines = {}
    table.insert(lines, "STATS:")
    table.insert(lines, string.format("  total_files: %d", total_files))
    table.insert(lines, string.format("  total_lines: %d", total_lines))
    table.insert(lines, "  lines_by_suffix:")
    for _, k in ipairs(keys) do
        table.insert(lines, string.format("    %s: %d", k, ext_lines[k]))
    end
    return lines
end

-- =============================================================================
-- YAML rendering
-- =============================================================================

--@description: yaml-quote a scalar string
local function yamlQuote(s)
    local t = s:gsub("\\", "\\\\"):gsub("\"", "\\\"")
    return "\"" .. t .. "\""
end

--@description: append lines of a block-scalar value with proper indentation
--  Fixes the original bug where content was truncated at the first empty line.
local function yamlAppendBlock(out, indent, content)
    if content == "" then
        table.insert(out, indent)
        return
    end
    local c = content
    -- strip one trailing newline (YAML |- semantics)
    if c:sub(-1) == "\n" then
        c = c:sub(1, -2)
    end
    -- split by newlines and indent each line
    for line in (c .. "\n"):gmatch("(.-)\n") do
        table.insert(out, indent .. line)
    end
end

--@description: render yaml hierarchy from tree and file contents, return list of lines
local function renderYaml(root, items, target_abs)
    local out = {}
    local content_by_rel = {}
    for _, it in ipairs(items) do
        content_by_rel[it.rel_target] = it.content
    end

    table.insert(out, "type: directory")
    table.insert(out, "path: " .. yamlQuote(target_abs))
    table.insert(out, "children:")

    local function renderNodeList(nodes, indent)
        for _, node in ipairs(nodes) do
            if node.kind == "dir" then
                table.insert(out, indent .. "- type: directory")
                table.insert(out, indent .. "  name: " .. yamlQuote(node.name))
                table.insert(out, indent .. "  children:")
                local kids = orderedChildren(node)
                renderNodeList(kids, indent .. "    ")
            else
                local rel = node.rel_path or node.name
                local content = content_by_rel[rel] or ""
                table.insert(out, indent .. "- type: file")
                table.insert(out, indent .. "  path: " .. yamlQuote(rel))
                table.insert(out, indent .. "  content: |-")
                yamlAppendBlock(out, indent .. "    ", content)
            end
        end
    end

    renderNodeList(orderedChildren(root), "  ")
    return out
end

-- =============================================================================
-- Output emission
-- =============================================================================

--@description: write sections to output, each section is a list of string entries.
--  Between sections a blank line is inserted.
--  Each entry is written via safeWrite followed by a newline.
--  File content entries may contain embedded newlines — that is fine.
local function emitOutput(sections, output_file)
    local handle
    if output_file then
        local f, err = io.open(output_file, "wb")
        if not f then
            fail("cannot open output file: " .. output_file .. " (" .. tostring(err) .. ")")
        end
        handle = f
    else
        handle = io.stdout
    end

    for sect_idx, lines in ipairs(sections) do
        if sect_idx > 1 then
            -- blank line between sections
            handle:write("\n")
        end
        for _, entry in ipairs(lines) do
            safeWrite(handle, entry)
            handle:write("\n")
        end
    end

    handle:flush()

    if output_file then
        handle:close()
    end
end

-- =============================================================================
-- CLI argument parsing
-- =============================================================================

--@description: create default option table
local function makeDefaultOptions()
    return {
        target_dir = ".",
        exclude_patterns = {},
        include_patterns = {},
        ignore_gitignore = false,
        with_tree = false,
        with_stats = false,
        wrap_mode = "md",
        path_mode = "relative",
        yaml_mode = false,
        output_file = nil,
        show_version = false,
        show_help = false,
        user_set_t = false,
        user_set_s = false,
        user_set_w = false,
        user_set_p = false,
    }
end

--@description: parse CLI arguments into PmcOptions
--  -x and -m each take exactly one argument (comma-separated patterns).
--  They can appear multiple times:  -x "*.log" -x "build/"
local function parseArgs(argv)
    local opt = makeDefaultOptions()
    local i = 1
    local target_set = false

    while i <= #argv do
        local a = argv[i]

        if a == "-v" then
            opt.show_version = true
            i = i + 1
        elseif a == "-h" or a == "--help" then
            opt.show_help = true
            i = i + 1
        elseif a == "-x" then
            local val = argv[i + 1]
            if not val or (startsWith(val, "-") and #val > 1) then
                fail("missing value for -x (use quotes: -x \"pattern\")")
            end
            local pats = parsePatternList(val)
            for _, p in ipairs(pats) do
                table.insert(opt.exclude_patterns, p)
            end
            i = i + 2
        elseif a == "-m" then
            local val = argv[i + 1]
            if not val or (startsWith(val, "-") and #val > 1) then
                fail("missing value for -m (use quotes: -m \"pattern\")")
            end
            local pats = parsePatternList(val)
            for _, p in ipairs(pats) do
                table.insert(opt.include_patterns, p)
            end
            i = i + 2
        elseif a == "-r" then
            opt.ignore_gitignore = true
            i = i + 1
        elseif a == "-t" then
            opt.with_tree = true
            opt.user_set_t = true
            i = i + 1
        elseif a == "-s" then
            opt.with_stats = true
            opt.user_set_s = true
            i = i + 1
        elseif a == "-w" then
            local val = argv[i + 1]
            if not val then fail("missing value for -w") end
            val = trim(val)
            if val ~= "md" and val ~= "nil" and val ~= "block" then
                fail("invalid -w mode: " .. val .. " (expected: md | nil | block)")
            end
            opt.wrap_mode = val
            opt.user_set_w = true
            i = i + 2
        elseif a == "-p" then
            local val = argv[i + 1]
            if not val then fail("missing value for -p") end
            val = trim(val)
            -- typo tolerance
            if val == "releative" then val = "relative" end
            if val ~= "relative" and val ~= "name" and val ~= "absolute" then
                fail("invalid -p mode: " .. val .. " (expected: relative | name | absolute)")
            end
            opt.path_mode = val
            opt.user_set_p = true
            i = i + 2
        elseif a == "-y" then
            opt.yaml_mode = true
            i = i + 1
        elseif a == "-o" then
            local val = argv[i + 1]
            if not val or trim(val) == "" then
                fail("missing value for -o")
            end
            opt.output_file = trim(val)
            i = i + 2
        elseif startsWith(a, "-") then
            fail("unknown option: " .. a)
        else
            if target_set then
                fail("multiple target directories are not allowed")
            end
            opt.target_dir = a
            target_set = true
            i = i + 1
        end
    end

    -- validate yaml mode constraints
    if opt.yaml_mode then
        if opt.user_set_t or opt.user_set_s or opt.user_set_w or opt.user_set_p then
            fail("-y cannot be used with -t, -s, -w, or -p")
        end
        if not opt.output_file then
            fail("yaml mode requires -o with .yaml or .yml file")
        end
        local lower = opt.output_file:lower()
        if not (endsWith(lower, ".yaml") or endsWith(lower, ".yml")) then
            fail("yaml output file must end with .yaml or .yml")
        end
    end

    return opt
end

-- =============================================================================
-- Help text
-- =============================================================================

--@description: print usage help
local function printHelp()
    local msg = [[pmc - pack-my-code

Usage:
  pmc [target-directory] [options]

Options:
  -v               Show version
  -x "<patterns>"  Exclude patterns (comma-separated, repeatable)
  -m "<patterns>"  Include-only patterns (comma-separated, repeatable)
                   Lower priority than -x
  -r               Ignore .gitignore (direct scan)
  -t               Output tree at beginning
  -s               Output statistics at end
  -w <mode>        Wrap mode: md | nil | block
  -p <mode>        Path mode: relative | name | absolute
  -y               YAML mode (cannot combine with -t -s -w -p)
  -o <file>        Redirect output to file
  -h, --help       Show help

Pattern syntax:
  *.lua            Match by extension
  .lua             Extension shorthand
  src/             Match directory name
  **/test/         Match directory at any depth
  build/*.o        Match with path prefix
  *.min.js         Compound extension

Notes:
  - Default mode requires git; use -r to scan without git
  - Files > 1 MB and known binary formats are skipped automatically
  - Always quote patterns to prevent shell expansion

Examples:
  pmc .
  pmc ./src -t -s
  pmc . -x "*.log,build/" -o context.md
  pmc . -m "*.lua" -x "test/"
  pmc . -r -w block
  pmc . -y -o context.yaml
]]
    io.write(msg)
    io.stdout:flush()
end

-- =============================================================================
-- Main
-- =============================================================================

local function main(argv)
    local opt = parseArgs(argv)

    if opt.show_help then
        printHelp()
        return
    end

    if opt.show_version then
        io.write(string.format("pmc -- pack-my-code. version %s\n", VERSION))
        io.stdout:flush()
        return
    end

    local cwd_abs = getCwd()
    local target_abs = getAbsolutePath(opt.target_dir)

    local raw_files
    if opt.ignore_gitignore then
        raw_files = listFilesDirect(target_abs)
    else
        raw_files = listFilesWithGit(target_abs)
    end

    local items = buildFileItems(raw_files, target_abs, opt, cwd_abs)
    local root = buildTree(items)

    -- yaml mode: dedicated output path
    if opt.yaml_mode then
        local yaml_lines = renderYaml(root, items, target_abs)
        emitOutput({ yaml_lines }, opt.output_file)
        return
    end

    -- standard mode: assemble sections
    local sections = {}

    if opt.with_tree then
        table.insert(sections, renderTree(root))
    end

    table.insert(sections, renderStandard(items, opt))

    if opt.with_stats then
        table.insert(sections, renderStats(items))
    end

    emitOutput(sections, opt.output_file)
end

main(arg)
