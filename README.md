# appcraft_unused_assets

[![Pub Version](https://img.shields.io/pub/v/appcraft_unused_assets)](https://pub.dev/packages/appcraft_unused_assets)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Finds the assets that nothing in a Flutter project refers to.

## Accessors, not paths

The usual cleaners look for the path of an asset among the string literals of
the code. That answer is worthless in a project using [flutter_gen][gen]: the
paths do appear as literals — inside the generated `assets.gen.dart`, which
lives in `lib` like everything else. Every asset looks referenced, and the tool
reports nothing.

Here the generated file is the input, not a scanning target. The accessors are
read out of it, and an asset counts as used when something reads its accessor.

[gen]: https://pub.dev/packages/flutter_gen

## Requirements

The project must use flutter_gen: the generated `assets.gen.dart` is the input
of the whole search. Without it there is nothing to read the accessors from,
and the tool stops with a message saying so.

## Installation

```yaml
dev_dependencies:
  appcraft_unused_assets: ^0.0.1
```

## What counts as a usage

| Source | Example |
|---|---|
| The accessor is read as a property | `Assets.images.logo.image()` |
| The `values` of the class holding it is read | `for (final a in Assets.images.values)` |
| The path is written out as a literal | `Image.asset('assets/images/logo.png')` |
| A configuration file names the path | `flutter_native_splash.yaml`, `flutter_launcher_icons` |

Every `*.yaml` and `*.yml` of the project root is read, because assets are
referenced from outside the code as often as from within it — the launcher icon
and the splash image are never mentioned by a single line of Dart. The
`flutter: assets:` list of the `pubspec.yaml` is the one exception: it declares
directories, and a declared directory would otherwise cover everything inside
it and hide every unused asset at once.

Only property reads count as a usage of an accessor: a local variable that
happens to carry the same name does not keep the asset alive. Reading the
`values` of a container marks every asset of that container as used, which is
what a precache loop over a whole directory does.

### Dead code does not count

In an app, a file under `lib` counts only when the app can reach it: from a
file under `lib` that declares a top-level `main` — `lib/main.dart`, and a
flavor entry such as `lib/flavors/main_prod.dart` alike — through imports,
exports and parts, conditional imports included. A screen nobody imports any
more keeps no asset alive. Files outside `lib` — the tests — are always read,
along with everything they import.

The report lists the files it left out, so an app that starts from a file
without a `main` of its own shows at once — list its entry files in
`entry_points`. A project with no `main` under `lib` is a package: everything
in its `lib` is public, and every file counts.

The search needs every file it walks through. When a reached import points at a
file that is not there — generated code not built yet, such as an injectable
`*.config.dart` — or an entry point is outside the scanned directories, nothing
is taken for dead, and the report names the missing files instead.

## Usage

```bash
dart run appcraft_unused_assets report
```

| Command | What it does |
|---|---|
| `report` | lists the assets nothing refers to |
| `check` | exits with 1 if anything is unused — for CI |
| `clean` | deletes the files of the unused assets, `--dry-run` to preview |

| Option | Meaning |
|---|---|
| `--generated` | path of the generated file, overriding the configuration |
| `--scan` | directory to scan for usages, repeatable |
| `--dry-run` | for `clean`: list what would be deleted, delete nothing |

### Before running clean

Commit first — there is no backup and no confirmation prompt. Then read the
report, or `clean --dry-run`, which lists every file `clean` would delete,
resolution variants included; the cases it cannot see are below.

Resolution variants go with the asset they belong to: deleting
`images/logo.png` deletes `images/2.0x/logo.png` as well. They carry no accessor
of their own, so nothing would ever report them and they would stay behind.

Afterwards two things are left to do. Regenerate the accessors — the generated
file is deliberately left untouched, since the generator would overwrite an edit
anyway. And if any deleted file was listed one by one in the `assets` section of
`pubspec.yaml`, remove its entry: a declared asset that does not exist fails the
build.

## Configuration

Optional. The generated file is located through the `output` flutter_gen is
configured with: first the options of its builder in `build.yaml` — under the
default target, or in `global_options`, `dev_options` taking precedence, the way
build_runner applies them — then the `flutter_gen` section of `pubspec.yaml`.
A project that configured flutter_gen usually needs nothing here; `generated`
and `--generated` override both:

```yaml
appcraft_unused_assets:
  generated: lib/app/resources/assets.gen.dart
  scan:
    - lib
    - test
  ignore:
    - assets/flags
  entry_points:
    - lib/main.dart
    - lib/flavors/main_prod.dart
```

An `ignore` entry covers a path and everything under it. `entry_points`
replaces the default — the files under `lib` that declare a top-level `main`.

## Where it is wrong

The tool leans towards calling an asset used — a name that matches anything at
all keeps it alive. The cases below are the opposite, and each one can put a
needed asset into the report. Read it before deleting.

**A path built at runtime.** Nothing reads an accessor, nothing writes the whole
path:

```dart
Image.asset('assets/flags/$countryCode.png');
```

The whole directory looks unused. This is what `ignore` is for.

**A path assembled from pieces.** Only a single, whole literal is matched;
adjacent literals and concatenated constants are not:

```dart
Image.asset('assets/images/' 'logo.png');   // looks unused
```

**A reference from outside the Dart code and the root configs.** Assets loaded
by native code through `lookupKeyForAsset`, named in `web/index.html`, or listed
in a JSON config or a YAML that does not sit in the project root — none of these
are read.

**A `values` reached through a variable.** `Assets.images.values` is understood;
`final images = Assets.images; images.values` is understood as well, but
`final gen = Assets.images; gen.values` is not — the name no longer matches the
class it came from.

**A sibling package in a monorepo** that reads the `Assets` of this one. Only
the directories of `scan` are looked at.

**An app started from a file without a `main` of its own** — one that only
re-exports the `main` of another file, or code reached only through
`Isolate.spawnUri`. What only that file reaches is taken for dead code. The
report lists the files it left out; add the entry file to `entry_points`.

## The blind spot it admits to

Reading the `values` of a class uses every asset it holds at once, so nothing
inside can be told apart — a genuinely unused asset there is invisible. Rather
than let that pass for "everything is referenced", the report says how much was
skipped and where:

```console
Not examined: 12 asset(s) in flags — the values of the class is read, which
uses every asset it holds at once.
```

To examine such a directory, stop reading its `values` — or accept that it is
kept whole.

## Where it is imprecise the safe way

Accessors are matched by name alone, so anything named alike keeps an asset
alive: `user.avatar` anywhere in the code counts as a usage of
`Assets.images.avatar`, and two assets named `logo` in different directories are
indistinguishable. The report is therefore incomplete rather than dangerous —
some genuinely unused assets stay unreported.

## Not covered

- Assets of the packages a project depends on. Only the assets of the project
  itself are read.
- Unused entries in the `pubspec.yaml` — a declared directory that no longer
  exists, or one holding nothing.
- Dead code inside a live file. Only whole files are told dead: an unused
  class or function in a file the app imports keeps its assets alive.
