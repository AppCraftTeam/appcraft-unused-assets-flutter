# Example

A project using flutter_gen, where one image is left over from a screen that
was removed.

```console
$ dart run appcraft_unused_assets report
Nothing refers to 1 asset(s):
  assets/images/im_200_need_update_app.svg  (im200NeedUpdateApp)

Check them before deleting: an asset addressed by a path built at runtime
looks unused here.
```

The accessor `Assets.images.im200NeedUpdateApp` appears nowhere but in the
generated file, and no configuration mentions the path.

A project that precaches a whole directory gets a second paragraph, saying what
the search could not look into:

```console
Not examined: 12 asset(s) in flags — the values of the class is read, which
uses every asset it holds at once.
```

## What counts as a usage

```dart
Assets.images.logo.image();              // the accessor is read
Image.asset('assets/images/logo.png');   // the path is written out
```

```yaml
# flutter_native_splash.yaml — a config of the tooling, read as well
flutter_native_splash:
  image: assets/images/splash_logo.png
```

An asset addressed by a path built at runtime cannot be seen by any of this:

```dart
Image.asset('assets/flags/$countryCode.png');   // looks unused
```

Keep such directories out of the report:

```yaml
appcraft_unused_assets:
  ignore:
    - assets/flags
```

## In CI

```console
$ dart run appcraft_unused_assets check
Nothing refers to 1 asset(s):
  assets/images/im_200_need_update_app.svg
```

Exit code 1.

## Deleting

```console
$ dart run appcraft_unused_assets clean --dry-run
Would delete 1 file(s):
  assets/images/im_200_need_update_app.svg

$ dart run appcraft_unused_assets clean
Deleted 1 file(s):
  assets/images/im_200_need_update_app.svg

Regenerate the accessors to drop them from the code.
```
