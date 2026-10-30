# Art and feel

Package 8 from the design doc's build plan: the fonts, plane art, split-flap animations, title promotions, sounds and app icon that make the screens match the mockups (dark departure board, amber flap text, cartoon planes on a bright map). Everything here only draws or plays; nothing changes game state.

## Fonts

Rubik (body text) and JetBrains Mono (the board's capitals) are bundled in `assets/fonts/` under the SIL Open Font License (the `OFL-*.txt` files beside them). They come from Google Fonts as variable fonts and are cut into static weights with `fonttools varLib.instancer`, because Flutter does not pick weights from a variable font on its own:

| Family | Weights |
| --- | --- |
| Rubik | 400, 500, 600, 700, 800 |
| JetBrains Mono | 500, 700, 800 |

`buildTheme()` makes Rubik the app font; `Board.flapStyle()` uses JetBrains Mono; the map's labels use `MapStyle.font`. Widget tests render with Flutter's test font as before, so layout tests stay stable.

## Plane art

`assets/planes/<model id>.svg` is one side-view picture per plane model, 260 x 130, facing right. The 12 launch planes are the plane gallery mockup's art (`Planes.dc.html`); the three planes built from parts (Barnstormer, Mach One, Cloud Nine) are drawn in the same style. `PlaneArt(modelId, height: ...)` (`lib/ui/plane_art.dart`) shows one, falling back to a plane icon if the file is missing. It is on the plane card and the loading sheet's header; the Hangar and Fleet screens can use it the same way. `test/ui/plane_art_test.dart` fails if a model in `planes.json` has no picture.

The map's planes stay the top-down sprites in `lib/game/map/sprites.dart`.

## Split-flap text

`SplitFlapText` (`lib/ui/split_flap.dart`) is text that flips like a departures board when it changes: each character that differs steps through the drum (`A-Z`, `0-9` and some punctuation) to its new letter, the columns a beat apart left to right, at most 6 flips each. It shows the text at rest on first build, keeps the final text laid out (invisible) while flipping so layout and test finders see the new value, and changes at once when the system asks for reduced motion.

`FlapText` uses it, so every amber board cell (destinations, ETAs, statuses, the Fleet clock) flips when its value changes.

## Titles and promotions

The top bar shows the airline's title (from `progression.json`) under the XP bar, and it flips when it changes. When a level-up brings a new title, `FeelLayer` (`lib/ui/feel_layer.dart`, wrapped around the whole app in `TinyAirwaysApp`) drops a "PROMOTED · AIRLINE LV n" banner under the top bar: the old title on a flap board, which flips over to the new one. It stays about 4 seconds; a tap dismisses it.

## Sounds

`assets/sounds/*.wav` are synthesised by `tool/build_sounds.py` (sines and noise, nothing to license). `Sounds` (`lib/app/sounds.dart`) plays them; `main()` installs `AudioSounds`, and tests keep the default `SilentSounds`. Sounds mix with the player's music and stay silent when the ringer switch is off.

| Sound | When |
| --- | --- |
| `takeoff` | A plane leaves a gate |
| `coins` | A plane lands at the end of its trip and gets paid |
| `level` | The airline gains a level |
| `promotion` | The airline earns a new title (flaps, then a fanfare) |
| `flap` | The Fleet tab's departures board opens |

`FeelLayer` decides when, by comparing each new game state with the last. `AudioSounds.enabled` is the switch for the Settings screen's sound toggle when that screen arrives.

## App icon and launch screen

`tool/art/app_icon.svg` is the icon: a top-down plane over a sky-blue split-flap tile on the board's dark ground. To rebuild every iOS and Android size and the iOS launch image:

```sh
NODE_PATH=$(npm root -g) node tool/art/build_icons.js   # needs Playwright + Chromium
python3 tool/art/flatten_icons.py                        # the App Store refuses alpha
```

The iOS launch screen is the board's dark ground (#0E141C) with the icon in the middle, so launch flows into the dark UI without a white flash.

## Not in this package

Local notifications ("your plane landed") are in the build plan's package 8 but need a notification plugin, a permission prompt and the Settings screen, so they are left for the package that builds Settings.
