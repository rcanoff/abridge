# Git hooks

```sh
git config core.hooksPath .githooks
```

## pre-push

Runs path-aware CI verify, then optional local agent review (`local/review/`) if installed.

| Variable | Effect |
|----------|--------|
| `CI_STRICT=1` | verify failures block push |
| `REVIEW_STRICT=1` | review failures block push |
| default | advisory — warn, push proceeds |