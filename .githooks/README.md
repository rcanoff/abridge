# Git hooks

```sh
git config core.hooksPath .githooks
```

## pre-push

Runs path-aware CI verify, then optional local agent review (`local/review/`) if installed.

| Variable | Effect |
|----------|--------|
| default | verify failures (fmt, lint, test) **block** push |
| `CI_STRICT=0` | verify failures advisory — warn, push proceeds |
| `REVIEW_STRICT=1` | review failures block push |
| review default | advisory — warn, push proceeds |