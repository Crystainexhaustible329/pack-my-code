# pmc - A Minimalist Code Context Packaging Tool

`pmc` (`pack-my-code`) is a minimalist, ultra-lightweight code context packaging tool distributed as a binary (packaged with `luainstaller`). It is especially suitable for building LLM prompts.

Download the version for your operating system from the [Releases](https://github.com/Water-Run/pack-my-code/releases) page, then add it to your environment variables.

> To use the default behavior of `pmc`, your device needs a `git` environment.

After installation, you can run `pmc -v` to verify it.  
If installed correctly, it will output: `pmc -- pack-my-code. version <your version number>`.

## Usage

```bash
pmc <target-directory>
```

For example:

```bash
pmc .
pmc ./src
```

`pmc .` can be shortened to `pmc`.  
`pmc` also has the following default behaviors:

- Follows `.gitignore`
- Does not redirect output (prints to terminal)
- Does not output a tree structure
- Does not output statistics
- Uses `markdown` as the wrapping format
- Uses paths relative to the execution directory

When an error occurs, `pmc` outputs corresponding information, for example: `err:( <error message> )`.

## Options

### `-x`: Exclude

Exclude specified files, directories, or patterns.

Examples:

```bash
pmc . -x "*.log"
pmc . -x "bin/,obj/"
pmc . -x "*.png,*.jpg"
```

### `-m`: Include Only

Package only specified files, directories, or patterns.

Examples:

```bash
pmc . -m "*.lua"
pmc . -m "src/,README.md"
```

> `-m` has lower priority than `-x`.  
> Even if a file matches `-m`, it will still be excluded if it also matches `-x`.

### `-r`: Ignore `.gitignore`

By default, `pmc` follows `.gitignore` through `git`.  
With `-r`, it performs a direct filesystem scan and ignores `.gitignore`.

This option is useful when:

- the directory is not inside a git repository
- `git` is not available

### `-t`: Output Tree Structure at the Beginning

Adds the tree structure of the current result at the beginning of the packaged output.

### `-s`: Output Statistics at the End

Appends statistical information at the end of the output.

### `-w`: Wrapping Mode

Specifies how each file’s content is wrapped in output.

`-w` supports the following modes:

- `md` (default): wrapped as Markdown code blocks
- `nil`: no wrapping
- `block`: wrapped in a “block” format

### `-p`: Path Mode

Specifies how paths are displayed before each file block.

`-p` supports the following modes:

- `relative` (default): relative to execution path
- `name`: filename only
- `absolute`: absolute path

### `-y`: YAML Mode

Enables YAML-mode output.

In YAML mode, output no longer follows normal plain-text concatenation.  
Instead, it uses its own tree hierarchy structure to organize content.

Therefore, in `-y` mode, the following options cannot be used together:

- `-t`
- `-s`
- `-w`
- `-p`

That is, YAML mode handles structure, paths, and content organization by itself.

### `-o`: Output Redirection

Write results directly to a specified file instead of printing to terminal.

Examples:

```bash
pmc . -o context.md
pmc . -o output.txt
```

> In YAML mode, output can only be written to files ending with `.yaml` or `.yml`.

## Combination Examples

Output the current directory content and prepend a tree structure:

```bash
pmc . -t
```

Package only `.lua` files in the `src` directory and output statistics:

```bash
pmc . -m "src/,*.lua" -s
```

Exclude image and log files, then write to a file:

```bash
pmc . -x "*.png,*.jpg,*.log" -o context.md
```

Ignore `.gitignore` and use `block` wrapping mode:

```bash
pmc . -r -w block
```

Export in YAML mode:

```bash
pmc . -y -o context.yaml
```

## Notice

- Files larger than **1 MB** are automatically skipped.
- Known binary formats and files containing null bytes are skipped.
- Files are assumed to be **UTF‑8 compatible text**.
- Very large repositories may produce large outputs; consider using `-x` or `-m` to limit scope.
- Pattern syntax supports `*`, `**`, and `?`, but not advanced glob expressions such as `{}` or `[]`.
