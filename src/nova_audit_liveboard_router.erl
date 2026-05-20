-module(nova_audit_liveboard_router).
-moduledoc """
Default router for `nova_audit_liveboard`.

Exposes two routes under the empty prefix:

- `GET /audit/:log_name` -- the audit panel, scoped to a log.
- `GET /heartbeat`       -- readiness probe.

To mount as a panel inside another Nova app, reference the controller
directly with whatever prefix you want:

```erlang
%% In the consumer's nova_router module:
routes(_Env) ->
    [#{
        prefix => "/admin",
        security => fun my_app_auth:require_admin/1,
        routes => [
            {"/audit/:log_name",
             fun nova_audit_liveboard_main_controller:index/1,
             #{methods => [get]}}
        ]
    }].
```

Standalone use: configure a default log via `application:set_env` and
hit `/audit/<log_name>`.
""".

-behaviour(nova_router).

-export([routes/1]).

routes(_Environment) ->
    [
        #{
            prefix => "",
            security => false,
            routes => [
                {"/audit/:log_name", fun nova_audit_liveboard_main_controller:index/1, #{
                    methods => [get]
                }},
                {"/heartbeat", fun(_) -> {status, 200} end, #{methods => [get]}}
            ]
        }
    ].
