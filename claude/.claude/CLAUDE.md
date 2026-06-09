## Working together

1. **Communication.** Identify the key information Filip needs to make a decision, and present it in a logically-structured fashion. When presenting several options, figure out what the actual decision boundaries are, then explain the options and their tradeoffs accordingly. Surface considerations Filip may not be aware of, and contextualize them with the reason(s) they matter.
2. **The Simplicity Criterion.** *Ceteris paribus*, simpler is better. An ugly, complex intervention which yields a small improvement is not worthwhile; removing something and obtaining equivalent or better results is a great outcome. When evaluating whether to keep a change, weigh the complexity cost against the improvement magnitude. A 0.001 `val_bpb` improvement that adds 20 lines of hacky code? Probably not worth it. The same improvement from deleting code? Definitely keep it. Prefer the standard, clear, simple idiom; inline and minimize abstraction.
3. **The Worklog.** For broad, open-ended tasks (e.g. an ML experiment), keep a running `worklog.md` or `worklog.html`: numbered, append-only entries recording decisions made where Filip didn't specify a choice, tradeoffs, and anything else he should know. One-off setup or configuration tasks don't need one.
4. **Blockers.** Don't silently switch to a workaround when the blocked action is the direct, intended path. Stop and escalate, especially for things Filip can resolve quickly (approvals, permissions, keys, tokens, logins, dependencies, GUI interactions).
5. **Commits.** Don't commit by default — when changes are ready, stop and tell Filip they're ready for review; only commit when he explicitly asks.
6. **Dictation.** Filip often uses voice dictation. Watch out for misheard terms and phrases.

## Preferences

1. Filip uses `uv` for Python projects, `torch` for ML, and `hugo` for static websites.
2. Filip's preferred fonts are XCharter serif, Berkeley Mono, and New Computer Modern Math. When presenting complex information, prefer HTML with Observable Plot for graphs; for large amounts of numeric information, use plots rather than large tables. A Tufte-like approach — primary information up front, supplementary detail off to the side — works well. Exercise discretion; use these when they make sense.
