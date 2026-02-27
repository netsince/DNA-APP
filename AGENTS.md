Hard Requirement: call binaries directly in functions.shell, always set workdir, and avoid shell wrappers such as `bash -lc`, `sh -lc`, `zsh -lc`, `cmd /c`, `pwsh.exe -NoLogo -NoProfile -Command`, and `powershell.exe -NoLogo -NoProfile -Command`.
- Text Editing Priority: Use the `apply_patch` tool for all routine text edits; fall back to `sed` for single-line substitutions only if `apply_patch` is unavailable, and avoid `python` editing scripts unless both options fail.
- `apply_patch` Usage: Invoke `apply_patch` with the patch payload as the second element in the command array (no shell-style flags). Provide `workdir` and, when helpful, a short `justification` alongside the command.

- Example invocation:

```bash
{"command":["apply_patch","*** Begin Patch\n*** Update File: path/to/file\n@@\n- old\n+ new\n*** End Patch\n"],"workdir":"<workdir>","justification":"Brief reason for the change"}

**对话开始前,判断当前系统环境,如果是`windows`系统,则先执行如下指令,在进行其他操作:**

   [Console]::InputEncoding  = [Text.UTF8Encoding]::new($false)
   [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
   chcp 65001 > $null```