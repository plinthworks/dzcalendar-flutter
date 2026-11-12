# dzcalendar for Flutter

The Dart and Flutter port of [DzCalendar](https://github.com/plinthworks/dzcalendar):
a calendar where every event keeps its own time zone, and days of 23 h, 25 h or
23 h 30 are drawn as they are. iOS and Android from one package.

| Package | | |
|---|---|---|
| [`dzcalendar`](packages/dzcalendar) | the Flutter widgets | [pub.dev](https://pub.dev/packages/dzcalendar) |
| [`dzcalendar_core`](packages/dzcalendar_core) | the engine, pure Dart | [pub.dev](https://pub.dev/packages/dzcalendar_core) |

```yaml
dependencies:
  dzcalendar: ^1.0.0
```

How to start: [`packages/dzcalendar/README.md`](packages/dzcalendar/README.md).

The core is ported by hand against the language-independent conformance cases
of the main repository (`conformance/cases`, copied here by
`tool/sync_conformance.dart`, never edited). `apps/showcase` is a full calendar
app for iOS, Android and macOS; `packages/dzcalendar/example` the small one.

## Releases

Both packages carry the same version, under semantic versioning: a fix raises
the patch, an addition the minor, a break the major.

1. Write what changed under `## X.Y.Z` in both `CHANGELOG.md`, and commit.
2. `dart run tool/release.dart X.Y.Z` sets the version in both pubspecs,
   commits "Release X.Y.Z" and tags `vX.Y.Z`.
3. `git push git@github.com:plinthworks/dzcalendar-flutter.git main vX.Y.Z`:
   the tag runs `.github/workflows/publish.yml`, which tests, publishes
   `dzcalendar_core`, then `dzcalendar`.

MIT.

---

# dzcalendar pour Flutter

Le portage Dart et Flutter de [DzCalendar](https://github.com/plinthworks/dzcalendar) :
un calendrier où chaque événement garde son propre fuseau, et où les journées de
23 h, 25 h ou 23 h 30 sont dessinées telles qu'elles sont. iOS et Android depuis
un seul paquet.

Deux paquets sur pub.dev : `dzcalendar` (les widgets Flutter) et
`dzcalendar_core` (le moteur, en Dart pur). Pour commencer :
[`packages/dzcalendar/README.md`](packages/dzcalendar/README.md).

## Publier une version

Les deux paquets portent le même numéro (versionnage sémantique : une
correction monte le dernier chiffre, un ajout le deuxième, une rupture le
premier).

1. Écrire les changements sous `## X.Y.Z` dans les deux `CHANGELOG.md`, et
   commiter.
2. `dart run tool/release.dart X.Y.Z` met la version dans les deux pubspecs,
   commite « Release X.Y.Z » et pose le tag `vX.Y.Z`.
3. `git push git@github.com:plinthworks/dzcalendar-flutter.git main vX.Y.Z` :
   le tag lance `.github/workflows/publish.yml`, qui teste puis publie
   `dzcalendar_core`, puis `dzcalendar`.

MIT.
