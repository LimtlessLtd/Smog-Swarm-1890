# Project Rules

Godot 4.x / GDScript RTS. See `todo.md` for the full spec, feature log, and the "Technical Debt" section. These rules override default behavior and apply to all code and comments written or edited in this repo.

## 1. Loose coupling / OOP

- Every new or edited manager/controller must follow Single Responsibility: one class, one reason to change. Don't add a new responsibility to an existing class just because it already has a `NodePath` to the thing you need — extract a collaborator instead.
- Dependency injection via `@export var x_path: NodePath` + a typed private `_x` var resolved in `_ready()` is the project's established DI convention. Keep using it. Never reach a dependency via `get_node("/root/...")` unless it's one of the five real global autoloads (`TickManager`, `TimeCycleManager`, `DisplaySettings`, `GameLaunchState`, `BackgroundExecutionManager`).
- Never read or write another class's underscore-prefixed (`_foo`) field from outside that class. Cross-class communication goes through public methods and signals only.
- Prefer signals (push) over polling another manager's public getters every frame/redraw (pull). A class that needs to react to another class's state change should connect to that class's signal, not re-derive the state itself.
- Before adding a new `@export var *_path: NodePath` to an already-wide class (roughly 8+ existing dependencies), extract a narrower collaborator that owns just the new dependency instead.
- No circular manager-to-manager references. If two managers both seem to need each other, one of them owns the data and the other listens to its signal.

## 2. Comments

- Comments contain technical detail and concrete specifics only: what the code does, why a non-obvious choice was made, what invariant/precondition/edge case matters. No narrative, no scene-setting, no restating what the code already says in prose form.
- When a comment explains a decision the user made, quote the user directly and verbatim (in quotation marks) instead of paraphrasing or dramatizing it.
- No filler qualifiers ("real bug found and fixed", "adversarial review", "genuinely", "deliberately" used as flavor rather than to mark an actual design tradeoff). State the fact plainly.
