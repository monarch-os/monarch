def text:
  if type == "string" then gsub("[\\x00-\\x1f\\x7f]"; " ")[0:256] else "" end;

def valid($uid):
  (.COREDUMP_UID == $uid)
  and ((._BOOT_ID // "") | test("^[a-f0-9]{32}$"))
  and ((.COREDUMP_PID // "") | test("^[0-9]{1,10}$"))
  and ((.COREDUMP_TIMESTAMP // "") | test("^[0-9]{1,20}$"));

def identifier:
  [._BOOT_ID, .COREDUMP_PID, .COREDUMP_TIMESTAMP] | join(":");

def summary:
  {
    id: identifier,
    application: ((.COREDUMP_EXE // .COREDUMP_COMM // "unknown") | split("/") | last | text),
    pid: .COREDUMP_PID,
    timestamp: .COREDUMP_TIMESTAMP,
    date: ((.COREDUMP_TIMESTAMP | tonumber) / 1000000 | strftime("%Y-%m-%d %H:%M UTC")),
    signal: ((.COREDUMP_SIGNAL_NAME // .COREDUMP_SIGNAL // "unknown") | text),
    core: "unavailable",
    truncated: (.COREDUMP_TRUNCATED == "1")
  };

def frames:
  (.MESSAGE // "")
  | if type == "string" then . else "" end
  | split("\n")
  | map(select(test("^\\s*(#[0-9]+\\s|Stack trace of thread|ELF object binary architecture:)")))
  | .[0:121]
  | map(gsub("^\\s+"; "")
      | gsub("Stack trace of thread [0-9]+:"; "Stack trace:")
      | gsub("0x[0-9a-fA-F]+\\s+"; "")
      | gsub("/(home|tmp|run/user|root)/.*?(?= \\+ 0x[0-9a-fA-F]+\\)$|$)"; "<private-path>")
      | gsub("[\\x00-\\x1f\\x7f]"; " ")
      | .[0:300]);

def report_text:
  "Monarch crash report\n\nApplication: \(.crash.application)\nDate: \(.crash.date)\nSignal: \(.crash.signal)\nCore: \(.crash.core)\n\nCurrent system\nMonarch: \(.system.monarch)\nKernel: \(.system.kernel)\nArchitecture: \(.system.architecture)\nPackage: \(.package.name) \(.package.version) (\(.package.source))\n\nBacktrace\n" +
  (if .backtrace | length == 0 then "No backtrace was recorded in the journal. A local core analysis may be needed." else .backtrace | join("\n") end) +
  (if .backtraceTruncated then "\n[Backtrace limited to 120 lines.]" else "" end) +
  "\n\nReview this report before sharing. It excludes the memory dump, environment, command line and general system logs.";
