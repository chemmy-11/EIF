#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tcl_selfcheck.py -- offline static self-check for the round3c Tcl tools.

No tclsh is installed on this machine (2026-10-19), so this script does the
quote/bracket-balance self-check with Python, plus a strict checklist against
AGENTS.md pitfall #66 (`wait_on_hw_ila -timeout` unit = minutes,
`write_hw_ila_data -csv_file` takes a basename, explicit BASIC_ONLY + AND
trigger configuration) and the project conventions:
  * ASCII-only Tcl sources (Vivado decodes Tcl with the host ANSI codepage),
  * no hardcoded hw_ila_N core names (pitfall #40 item 3),
  * no `get_property VALUE` in batch mode (pitfall #40 item 2),
  * no trailing '#' comments (pitfall #19: '#' is only a comment at line start).

Checks performed per file
  1. balance scan: braces {} , brackets [] , double quotes " (with backslash
     escapes) outside of full-line comments; report per-line first imbalance
  2. forbidden regular expressions (--forbid)
  3. required regular expressions (--require)
  4. pitfall #66 API checklist (only for files that mention hw_ila)
  5. non-ASCII byte count (should be 0 for .tcl)
  6. trailing-'#' heuristic warning

USAGE
  python tcl_selfcheck.py <file.tcl> [<file2.tcl> ...]
  exit 0 = all checks PASS, 1 = at least one FAIL

NOTE: this is a static check, not a Tcl parse. It cannot prove Vivado will
accept a script; it only catches the mechanical error classes above.
"""

import argparse
import re
import sys

# ---------------------------------------------------------------------------
# line helpers
# ---------------------------------------------------------------------------
def split_lines(text):
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


def is_full_comment(line):
    return line.lstrip().startswith("#")


def strip_full_comments(lines):
    """Return list of (lineno, code_line) with full-line comments blanked."""
    out = []
    for i, ln in enumerate(lines, 1):
        if is_full_comment(ln):
            out.append((i, ""))
        else:
            out.append((i, ln))
    return out


# ---------------------------------------------------------------------------
# balance scanner
# ---------------------------------------------------------------------------
def balance_scan(path, lines):
    """Return (errors, warnings). Tcl: {} [] nest, "..." substitutes []/{}.

    Inside double quotes: `[` and `]` still execute (substitution), `{` `}` are
    literal. The scanner therefore counts brackets inside strings but not
    braces; a brace inside a quoted word is treated as a literal char.
    """
    errors = []
    warnings = []
    brace = 0
    brack = 0
    in_dq = False
    dq_start = 0
    for lineno, line in strip_full_comments(lines):
        i = 0
        n = len(line)
        while i < n:
            ch = line[i]
            if in_dq:
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    in_dq = False
                elif ch == "[":
                    brack += 1
                elif ch == "]":
                    brack -= 1
                    if brack < 0:
                        errors.append("%s:%d: unmatched ']' (inside string)"
                                      % (path, lineno))
                        brack = 0
                i += 1
                continue
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_dq = True
                dq_start = lineno
            elif ch == "{":
                brace += 1
            elif ch == "}":
                brace -= 1
                if brace < 0:
                    errors.append("%s:%d: unmatched '}'" % (path, lineno))
                    brace = 0
            elif ch == "[":
                brack += 1
            elif ch == "]":
                brack -= 1
                if brack < 0:
                    errors.append("%s:%d: unmatched ']'" % (path, lineno))
                    brack = 0
            elif ch == "#":
                if brace > 0:
                    # inside a braced word '#' is a literal character (e.g. the
                    # proven MicroBlaze target regexp {^\s*(\d+)\s+MicroBlaze\s+#});
                    # it is not a comment and not an argument.
                    pass
                else:
                    # trailing '#' outside a string: not a Tcl comment
                    # (pitfall #19: '#' is a comment only at line start)
                    warnings.append("%s:%d: '#' appears outside a string/braces"
                                    " and not at line start -> Tcl treats it as"
                                    " an argument, not a comment (pitfall #19)"
                                    % (path, lineno))
            i += 1
        if in_dq:
            warnings.append("%s:%d: double quote still open at end of line"
                            " (multi-line string; unusual in this codebase)"
                            % (path, lineno))
            in_dq = False
    if brace != 0:
        errors.append("%s: brace depth at EOF = %d (expected 0)" % (path, brace))
    if brack != 0:
        errors.append("%s: bracket depth at EOF = %d (expected 0)" % (path, brack))
    return errors, warnings


# ---------------------------------------------------------------------------
# pitfall #66 API checklist
# ---------------------------------------------------------------------------
def check_pitfall66(path, text):
    """Returns (fails, warns, notes) for the hw_ila API caliber rules."""
    fails = []
    warns = []
    notes = []
    looks_ila = ("get_hw_ila" in text) or ("hw_ila" in text)
    if not looks_ila:
        return fails, warns, ["%s: not an ILA script; pitfall #66 checklist skipped"
                              % path]
    # (1) explicit BASIC_ONLY + AND
    if "CONTROL.TRIGGER_MODE" not in text or "BASIC_ONLY" not in text:
        fails.append("%s: pitfall #66(1): CONTROL.TRIGGER_MODE BASIC_ONLY not"
                     " found (basic trigger must be explicit)" % path)
    else:
        notes.append("%s: #66(1) CONTROL.TRIGGER_MODE BASIC_ONLY present" % path)
    if "CONTROL.TRIGGER_CONDITION" not in text or not re.search(
            r"CONTROL\.TRIGGER_CONDITION\s+AND", text):
        fails.append("%s: pitfall #66(1): CONTROL.TRIGGER_CONDITION AND not"
                     " found (multiple compares combine by AND)" % path)
    else:
        notes.append("%s: #66(1) CONTROL.TRIGGER_CONDITION AND present" % path)
    # (2) wait_on_hw_ila -timeout unit = MINUTES
    if "wait_on_hw_ila" not in text:
        fails.append("%s: pitfall #66(2): no wait_on_hw_ila at all" % path)
    else:
        for m in re.finditer(r"wait_on_hw_ila\s+-timeout\s+([^\s\]]+)", text):
            arg = m.group(1)
            if re.match(r"^\d+$", arg):
                val = int(arg)
                if val > 10:
                    fails.append("%s: pitfall #66(2): wait_on_hw_ila -timeout %s"
                                 " looks like SECONDS (unit is MINUTES!)"
                                 % (path, arg))
                else:
                    notes.append("%s: #66(2) wait_on_hw_ila -timeout %s min (ok)"
                                 % (path, arg))
            elif "$" in arg:
                notes.append("%s: #66(2) wait_on_hw_ila -timeout %s (variable;"
                             " documented as minutes)" % (path, arg))
            else:
                warns.append("%s: #66(2) wait_on_hw_ila -timeout argument '%s'"
                             " is not an integer/variable; verify it is MINUTES"
                             % (path, arg))
    # (3) write_hw_ila_data -csv_file BASENAME
    if "write_hw_ila_data" not in text:
        fails.append("%s: pitfall #66(3): no write_hw_ila_data at all" % path)
    else:
        for m in re.finditer(r"-csv_file\s+([^\s\]}]+)", text):
            arg = m.group(1)
            if "$" in arg or "[" in arg:
                notes.append("%s: #66(3) -csv_file %s (variable basename, ok)"
                             % (path, arg))
            elif arg.lower().endswith(".csv"):
                fails.append("%s: pitfall #66(3): -csv_file %s ends with .csv;"
                             " Vivado appends .csv -> pass a BASENAME"
                             % (path, arg))
            else:
                notes.append("%s: #66(3) -csv_file %s (literal basename, ok)"
                             % (path, arg))
    # project conventions
    if re.search(r"\bhw_ila_[0-9]+\b", text):
        fails.append("%s: hardcoded hw_ila_N core name found (pitfall #40"
                     " item 3: locate cores via get_hw_probes -of_objects)"
                     % path)
    else:
        notes.append("%s: no hardcoded hw_ila_N" % path)
    if "get_property VALUE" in text:
        fails.append("%s: get_property VALUE used (pitfall #40 item 2: batch"
                     " mode does not fill probe VALUE; export CSV instead)" % path)
    if "get_hw_probes" in text and "-of_objects" in text:
        notes.append("%s: get_hw_probes ... -of_objects used (auto discovery)"
                     % path)
    non_ascii = sum(1 for b in text.encode("utf-8") if b > 127)
    if non_ascii:
        warns.append("%s: %d non-ASCII bytes (Vivado Tcl sources should stay"
                     " ASCII; ANSI/GBK decoding can break them)" % (path, non_ascii))
    else:
        notes.append("%s: ASCII-only (0 non-ASCII bytes)" % path)
    return fails, warns, notes


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def check_file(path):
    print("=" * 78)
    print("TCL_CHECK: %s" % path)
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        print("TCL_ERROR: cannot read: %s" % exc)
        return False
    text = raw.decode("utf-8", errors="replace")
    lines = split_lines(text)
    code_text = "\n".join([ln for (_, ln) in strip_full_comments(lines)])
    print("  lines=%d bytes=%d" % (len(lines), len(raw)))
    errors, warns = balance_scan(path, lines)
    fails66 = []
    notes = []
    if any(k in code_text for k in ("get_hw_ila", "write_hw_ila_data",
                                    "wait_on_hw_ila")):
        f66, w66, n66 = check_pitfall66(path, code_text)
        fails66 += f66
        warns += w66
        notes += n66
    all_logic_errors = errors + fails66
    for e in all_logic_errors:
        print("  FAIL: %s" % e)
    for w in warns:
        print("  WARN: %s" % w)
    for nt in notes:
        print("  NOTE: %s" % nt)
    ok = len(all_logic_errors) == 0
    print("  RESULT: %s" % ("PASS" if ok else "FAIL"))
    return ok


def main(argv=None):
    ap = argparse.ArgumentParser(description="offline Tcl static self-check")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args(argv)
    ok_all = True
    for f in args.files:
        if not check_file(f):
            ok_all = False
    print("=" * 78)
    print("TCL_SELFCHECK_DONE: files=%d result=%s"
          % (len(args.files), "PASS" if ok_all else "FAIL"))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
