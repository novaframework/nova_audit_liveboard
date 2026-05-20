# nova_audit_liveboard

Browser panel for [`nova_audit`](https://github.com/novaframework/nova_audit). A Nova app.

Filterable, paginated table of audit events. Mount it as a route in
your existing Nova app, or run it standalone.

## Add it to your app

```erlang
%% rebar.config
{deps, [
    nova,
    {nova_audit, {git, "https://github.com/novaframework/nova_audit.git", {tag, "v0.2.0"}}},
    {nova_audit_liveboard,
        {git, "https://github.com/novaframework/nova_audit_liveboard.git", {branch, "main"}}}
]}.
```

```erlang
%% .app.src
{applications, [kernel, stdlib, nova, nova_audit, nova_audit_liveboard]}.
```

## Mount in your router

```erlang
routes(_Env) ->
    [#{
        prefix => "/admin",
        security => fun my_app_auth:require_admin/1,   %% wrap with your auth
        routes => [
            {"/audit/:log_name",
             fun nova_audit_liveboard_main_controller:index/1,
             #{methods => [get]}}
        ]
    }].
```

Then browse to `/admin/audit/app_events` (or whichever `nova_audit` log
name you've configured).

## Config

```erlang
{nova_audit_liveboard, [
    {page_size, 50},
    {default_log, app_events}
]}.
```

## What you see

- Filter by actor ID, action, target type, target ID, request ID, outcome, and time range.
- Cursor-paginated table of matching events.
- ISO-formatted timestamps.
- Success / failure outcome highlighting.
- Dark mode support.

## Standalone use

If you don't have a Nova app and just want to browse:

```sh
rebar3 nova new my_audit_browser    # or use this repo as a starting point
rebar3 shell
```

The default router exposes `/audit/:log_name` at `http://localhost:8080`.

## Security

`nova_audit_liveboard` ships with `security => false` in its default
router. **Always** wrap with authentication when mounting in your own
app. The panel exposes audit data — treat it like the most sensitive
table in your database, because it is.

## License

Apache-2.0.
