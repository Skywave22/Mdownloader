# d4rt (analyzer 14 port)

This is **d4rt 0.1.7** - the Dart interpreter that
[`anymex_extension_runtime_bridge`](https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge)
runs Mangayomi's Dart extensions on - with exactly one purpose: let it live in
the same dependency graph as the rest of this app. It is wired in through
`dependency_overrides` in the app's `pubspec.yaml`, and the license is
upstream's (MIT, see `LICENSE`).

## Why

d4rt parses Dart source with `package:analyzer` at runtime, and depends on
`analyzer ^7.4.5` (0.1.7) or `^8.4.0` (the latest, 0.2.4). This app resolves
analyzer 14.4: `source_gen` 4.3, which the code generators here
(`riverpod_generator`, `go_router_builder`) are built on, requires
`>=14.0.0 <15.0.0`. A pub graph holds one analyzer, so with the stock package
`flutter pub get` cannot resolve at all, and forcing analyzer 7 down with an
override would pull the code generators down with it.

The other way out is forcing analyzer 14 under the stock d4rt, and that does not
compile: it reads the AST through accessors analyzer has since removed.

## What changed

Only the calls into `package:analyzer`, 43 edits across six files in `lib/src/`.
Interpreter behaviour is untouched. Each one is a rename or a re-shaping with the
same meaning, taken from the analyzer changelog:

| analyzer | Before | After |
| --- | --- | --- |
| 8.0 | `NamedType.name2` | `NamedType.name` (a `Token`) |
| 9.0 | `ErrorSeverity`, `Diagnostic.errorCode.errorSeverity` | `DiagnosticSeverity`, `diagnosticCode.diagnosticSeverity` |
| 10-12 | `ClassDeclaration.name` / `.typeParameters` / `.members` | `namePart.typeName` / `namePart.typeParameters` / `body.members` |
| 10-12 | `EnumDeclaration.name` / `.constants` / `.members` | `namePart.typeName` / `body.constants` / `body.members` |
| 10-12 | `MixinDeclaration.members`, `ExtensionDeclaration.members` | `body.members` |
| 13 | `NamedExpression` (`.name.label.name`, `.expression`) | `NamedArgument` (`.name.lexeme`, `.argumentExpression`) |
| 13 | record literal `NamedExpression` | `RecordLiteralNamedField` (`.name.lexeme`, `.fieldExpression`) |
| 13 | `DefaultFormalParameter` wrapper + `NormalFormalParameter` | every `FormalParameter` carries `defaultClause`; no wrapper |
| 13 | `Label.label.name`, `BreakStatement.label.name` | `Label.name.lexeme`, `LabelReference.name.lexeme` |

## How it is checked

`test/` is upstream's own suite, unchanged. CI runs it (and the analyzer) on
every pull request through the `packages` job, so a future analyzer bump that
breaks the interpreter goes red instead of failing inside someone's extension.

## When to delete this

When the bridge moves to a d4rt that supports the analyzer this app resolves, or
stops using d4rt. Then drop the `d4rt` entry from `dependency_overrides`, and the
`d4rt` leg from the `packages` job in `.github/workflows/ci.yml`.
