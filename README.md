# Doomguy for Half-Life

A Half-Life 1 (GoldSrc) mod patch that turns the game into **Doom**: the Doom status bar
with its animated face, Doom weapon viewmodels, Doom movement physics, vertical autoaim
and a Doom style `+use`.

It is a patch on top of the official **Half-Life SDK 2.3**: you drop the sources into the
SDK, build the two game DLLs, and build the sprite sets from the IWAD of your own copy of
Doom.

> **No Doom assets are distributed here.** Doom is © id Software / ZeniMax. You must own
> the game. Everything in `tools/` reads *your* `doom.wad`; no `.wad`, no extracted Doom
> art and no built sprites are part of this repository (see `.gitignore`).

## Requirements

* **Half-Life 1** on Steam (plus its retail/Steam map files).
* The **Half-Life SDK** — a separate **free** download in the same Steam library, on the
  **Tools** tab: Steam client → *Library* → the filter dropdown above the list → *Tools* →
  **Half-Life SDK** → *Install*. It lands next to the game as
  `...\steamapps\common\Half-Life SDK`, and everything this patch needs is inside it:
  `hlsdk\cl_dll\`, `hlsdk\dlls\` and `hlsdk\projects\vs2019\*.vcxproj`. (The same sources are
  also on GitHub as `ValveSoftware/halflife`, but the Steam tool is the whole thing in one
  install.)
* Visual Studio 2019/2022 with the C++ toolset (Win32) — for `MSBuild`.
* Windows PowerShell 5.1 (the builders use `System.Drawing`).
* A full Doom IWAD: `doom.wad` (Doom Classic Bundle / Doom Classic 2019 is fine).
  Shareware `doom1.wad` is missing most of the status bar and weapon frames.

## How to set up (short version)

Five steps, in this order: **(1)** put `cl_dll/` into `<sdk>\cl_dll\` and `dlls/` into
`<sdk>\dlls\` (the `hlsdk` folder of the free *Half-Life SDK* from the Steam **Tools**
tab) and build `hl_cdll.vcxproj` + `hldll.vcxproj`, Release/Win32; **(2)** build the sprites
with `tools\build_all_scales.ps1`, pointing `-Wad` at your own `doom.wad`; **(3)** create
`<Half-Life>\dg_mod\` next to `valve\` with a `liblist.gam` (below), the two built DLLs as
`cl_dlls\client.dll` and `dlls\hl.dll`, the sprites in `sprites\`, and the shipped
`userconfig.cfg` / `server.cfg`; **(4)** launch with `-game dg_mod -insecure` in Steam's
launch options; **(5)** play. Every step is spelled out in *Install — the mod folder*,
including why `-insecure` is needed.

## What it does

* **Doom status bar (STBAR)** instead of the Half-Life gauges. Ammo, health and armour are
  drawn with Doom's own `STTNUM`/`STTPRCNT` patches at Doom's own coordinates
  (`ST_AMMOX 44`, `ST_HEALTHX 90`, `ST_ARMORX 221`, row 171), taken straight from
  `st_stuff.c` / `st_lib.c`. The Half-Life health/armour/ammo readouts and the damage type
  tiles are suppressed while the bar is present.
* **Animated Doom face** (42 frames, `STFST*`, `STFOUCH*`, `STFEVL*`, `STFKILL*`, `STFGOD*`,
  `STFDEAD*`, `STFTL*`, `STFTR*`) with Doom's priority: death, pickup grin (2 s), pain
  (grimace after a big hit, otherwise it turns toward the attacker for 1 s), rampage while
  the attack key is held, and a random gaze direction when idle.
* **Doom weapon viewmodels** for the weapons that have a Doom counterpart:

  | Half-Life | Doom sprite |
  |---|---|
  | crowbar | `PUNG` (fist) |
  | 9mm pistol | `PISG` |
  | .357 revolver | `PISG` (slower) |
  | MP5 | `CHGG` (chaingun) |
  | shotgun | `SHTG` |
  | crossbow | `PLSG` (plasma) |
  | RPG | `MISG` (rocket launcher) |
  | gauss gun | `BFGG` |

  Egon, hornet gun, grenades, satchel, snark and tripmine keep the Half-Life viewmodel.
  All frames of one weapon live on a **single canvas** (the union of the patch offsets), so
  no frame ever jumps, and the muzzle flash is a second sprite drawn over the base frame.
* **Doom movement**: `sv_maxspeed 960`, `sv_friction 8`, `sv_accelerate 100`,
  `sv_airaccelerate 100`.
* **No vertical look** (`m_pitch 0`, PgUp/PgDn/Ins unbound) and **instant vertical
  autoaim** (`sv_aim 1`, `sv_allow_autoaim 1`) — like Doom's `P_AimLineAttack`.
* **Doom style `+use`**: `PlayerUse()` gets a flat (height dropped) fallback pass, so
  pressing use next to a button/crate works without pointing at it exactly.
* **Resolution independent HUD**: the engine draws HUD sprites 1:1, so the mod ships one
  sprite set per scale and the client picks the biggest one that fits the screen.

## Repository layout

```
cl_dll/   client DLL sources   -> copy into <sdk>\cl_dll\
dlls/     server DLL sources   -> copy into <sdk>\dlls\
tools/    the sprite builders (PowerShell 5.1)
```

The finished mod folder (the one you launch) is **not** in the repository — it contains
your own `doom.wad` and the sprites built from it. How to create it is the *Install*
section below; the two sections before it produce the files that go into it.

## Build — the game DLLs

`<sdk>` below is the `hlsdk` folder of that SDK install, for example
`D:\SteamLibrary\steamapps\common\Half-Life SDK\hlsdk`.

```
copy cl_dll\*.cpp cl_dll\*.h  <sdk>\cl_dll\
copy dlls\*.cpp               <sdk>\dlls\

MSBuild <sdk>\projects\vs2019\hl_cdll.vcxproj /p:Configuration=Release /p:Platform=Win32
MSBuild <sdk>\projects\vs2019\hldll.vcxproj   /p:Configuration=Release /p:Platform=Win32
```

The post-build `MSB3073` error is harmless: the provided projects try to copy the result
into the SDK's sample `game\mod` folder. Take the results from
`<sdk>\projects\vs2019\Release\hl_cdll\client.dll` and `...\Release\hldll\hl.dll` and copy
them into your mod folder as `<mod>\cl_dlls\client.dll` and `<mod>\dlls\hl.dll`
(the game must be closed — it locks the DLLs).

## Build — the sprite sets

```
powershell -ExecutionPolicy Bypass -File tools\build_all_scales.ps1
```

Overrides and options (all builders take the same style of parameters; **the defaults below
point at the author's own install, so pass them explicitly**):

```
-Wad    <path to doom.wad>          default: <author's mod folder>\doom.wad
-Hud    <folder with Doom PNGs>     default: <author's mod folder>\hud
-OutDir <mod>\sprites               default: <author's mod folder>\sprites
-Tags   20,25,30,35,40,45,50        build only some scales
-Clean                              remove the pre-scale-set file names first
```

The script builds every requested scale and writes `dg<TAG>_*.spr` into `-OutDir`:

| tag | x / y scale | set used at |
|---|---|---|
| `20` | 2.0 / 2.4 | 640×480 |
| `25` | 2.5 / 3.0 | 800×600, 854×480 |
| `30` | 3.0 / 3.6 | 1024×768, 960×600 |
| `35` | 3.5 / 4.2 | 1152×864 |
| `40` | 4.0 / 4.8 | 1280×720, 1280×800, 1280×960, 1280×1024, 1366×768 |
| `45` | 4.5 / 5.4 | 1440×900, 1440×1080 |
| `50` | 5.0 / 6.0 | 1600×1200, 1680×1050, 1920×1080, 1920×1200 |

Every set contains the same 39 sprites: `dg<TAG>_stbar`, `dg<TAG>_face` (42 frames),
`dg<TAG>_num` (10 frames), `dg<TAG>_pct` and the 35 viewmodel frames.

### Supported resolutions

The scale sets are the exact fits of the standard 4:3 modes — 640×480 (`dg20`),
800×600 (`dg25`), 1024×768 (`dg30`), 1152×864 (`dg35`), 1280×960 (`dg40`), 1440×1080
(`dg45`), 1920×1200 (`dg50`) — and **any other resolution, widescreen included, is served
by the biggest set that fits** (see the table above). A mode smaller than 640×480 gets the
smallest set, and a set that is missing on disk falls back to the next smaller one, so no
resolution ever ends up with a broken HUD — only with a bar that is a little smaller than
the perfect fit.

**800×600 was the first — and for a long time the only — resolution tested in game**: the
whole HUD was developed and tuned there, and it is still the reference set (`dg25`).
1440×900 and 1440×1080 were checked as well. The remaining sets come from the same Doom
patches through the same pipeline and are picked automatically; if a resolution ever looks
off, the console line `doomhud: screen <W>x<H> -> tag <n>` says which set was chosen.

Individual builders, if you want one widget at a time:

```
tools\build_stbar_spr.ps1     -ScaleX 2.5 -ScaleY 3.0        STBAR + STTPRCNT (+ a layout mock PNG)
tools\build_face_spr.ps1      -ScaleX 2.5 -ScaleY 3.0        the 42 frame face
tools\build_doomnum_spr.ps1   -ScaleX 2.5 -ScaleY 3.0        the STTNUM digits
tools\doom_weapon_sprites.ps1 -ScaleX 2.5 -ScaleY 3.0        every viewmodel + flashes
```

## Install — the mod folder

This repository is the *source*: it has no `dg_mod` folder and cannot have one, because
the mod folder holds your own `doom.wad`, the patches extracted from it and the sprites
built from them. You create it once, next to `valve`:

```
<Half-Life>\
  hl.exe
  valve\                     the original game (used as fallback_dir)
  dg_mod\                    the mod — this is what you create
    liblist.gam              tells the engine this folder is a game
    cl_dlls\client.dll       built from hl_cdll.vcxproj
    dlls\hl.dll              built from hldll.vcxproj
    sprites\dg20_*.spr       built by tools\build_all_scales.ps1
    sprites\dg25_*.spr
    ...
    sprites\dg50_*.spr
    userconfig.cfg           look / speed cvars
    server.cfg               movement / autoaim cvars
    doom.wad                 your IWAD — build input only, not read at runtime
    hud\                     your extracted Doom patches — build input only
```

1. **Create the folder** inside the Half-Life installation, next to `valve`
   (`...\steamapps\common\Half-Life\dg_mod`). Any name works; the rest of the section
   assumes `dg_mod`.
2. **Write `liblist.gam`** — the one file the engine needs to see a game directory. This is
   exactly what is used here:

   ```
   game "Doomguy Mod"
   startmap "c1a0"
   trainmap "c1a0"
   mp_entitylist ""
   mp_filter ""
   gamedll "dlls\hl.dll"
   mpentity "info_player_start"
   secure "1"
   fallback_dir "valve"
   type "singleplayer_only"
   ```

   `fallback_dir "valve"` is the important line: the mod reuses every Half-Life map, sound,
   model and menu, and only the files present in `dg_mod` override them. There is no need
   to copy the game data.
3. **Copy the two DLLs you built** into `dg_mod\cl_dlls\client.dll` and
   `dg_mod\dlls\hl.dll` (the game must be closed — it locks them).
4. **Build the sprites** into `dg_mod\sprites\` (the section above). The client only loads
   the sprite sets that exist, so you can install a single set while testing.

   `doom.wad` and `hud\` are only inputs for the builders. They may live anywhere (the
   builders' `-Wad` / `-Hud` parameters point at them); keeping them in the mod folder is
   just convenient.
5. **Copy the two config files** (they are plain text, not Doom assets). `userconfig.cfg` is
   executed by the client after `config.cfg`, `server.cfg` when the listen server starts:

   ```
   // dg_mod\userconfig.cfg
   unbind "PGUP"
   unbind "PGDN"
   unbind "INS"
   m_pitch "0"
   cl_forwardspeed 1000
   cl_backspeed 1000
   cl_sidespeed 1000
   r_drawviewmodel "1"
   ```

   ```
   // dg_mod\server.cfg
   sv_maxspeed 960
   sv_friction 20
   sv_accelerate 100
   sv_airaccelerate 100
   sv_aim 1
   sv_allow_autoaim 1
   ```

   These are the values the mod was developed and tested with — tune them to taste. They
   are ordinary Half-Life cvars, so you can also just type them in the console.
6. **Launch it.** In Steam: right click **Half-Life** → *Properties* → *Launch Options* and
   put

   ```
   -game dg_mod -insecure
   ```

   `-insecure` is **required** with Steam: secure mode refuses to load modified game DLLs.
   Add `-console -condebug` if you want the diagnostics (they are also written to
   `dg_mod\qconsole.log`):

   ```
   -game dg_mod -insecure -console -condebug
   ```

   Without Steam it is the same command line: `hl.exe -game dg_mod -insecure`.

`New Game` then runs Half-Life's own campaign (`startmap c1a0`) with the Doom status bar,
the Doom viewmodels and the Doom movement.

## Play

`r_drawviewmodel` is switched off automatically while a weapon with a Doom viewmodel is
held, and back on for the weapons that keep the Half-Life viewmodel. `+use` and the autoaim
are server side and need no binds. The only thing worth knowing in game: the sprite set is
chosen when a level is initialised, so after changing the video mode load a savegame to see
the new size.

## Known gaps / TODO

* The face and the digit builders read the Doom patches as PNGs from `-Hud`
  (`STFST00.png`, `STTNUM0.png`, …). There is no published extractor yet, so for now you
  have to provide those PNGs yourself; the status bar and the viewmodels already read the
  WAD directly. (A shared WAD reader for all builders is the next step.)
* Diagnostics are still compiled in (they print to the console with `-condebug`).
* The `.357` uses the pistol sprite, the egon has no Doom counterpart and the chainsaw
  (`SAWG`) is unused.

## Licence / credits

* Source code derived from the **Half-Life SDK** — © Valve Corporation; distributed under
  the Half-Life SDK licence (non-commercial use, licence headers kept in every file).
* Doom sprites and the status bar layout — © id Software; **not** included here, built from
  your own IWAD on your own machine.
* Everything else (the port, the tools) — this repository.

---

## По-русски

Патч на Half-Life 1 (GoldSrc), который превращает игру в Doom: статус-бар Doom с
анимированным лицом, вьюмодели оружия из Doom, «думовская» физика движения, вертикальный
автоприцел и `+use` как в Doom.

Это патч поверх официального **Half-Life SDK 2.3**: исходники кладутся в SDK, собираются
две игровые DLL, а спрайты собираются из IWAD вашей собственной копии Doom.

> **Ассеты Doom здесь не выкладываются.** Doom — © id Software / ZeniMax, нужна своя копия
> игры. Всё в `tools/` читает *ваш* `doom.wad`; ни `.wad`, ни распакованной графики Doom, ни
> собранных спрайтов в репозитории нет (см. `.gitignore`).

### Что нужно

* **Half-Life 1** в Steam (вместе с его картами).
* **Half-Life SDK** — отдельная **бесплатная** загрузка в той же библиотеке Steam, на
  вкладке *Инструменты*: *Библиотека* → фильтр над списком → *Инструменты* →
  **Half-Life SDK** → *Установить*. Встаёт рядом с игрой как
  `...\steamapps\common\Half-Life SDK`, и всё нужное лежит внутри: `hlsdk\cl_dll\`,
  `hlsdk\dlls\` и `hlsdk\projects\vs2019\*.vcxproj`. (Те же исходники есть на GitHub как
  `ValveSoftware/halflife`, но в Steam-инструменте всё сразу.)
* Visual Studio 2019/2022 с C++ (Win32) — для `MSBuild`.
* Windows PowerShell 5.1 (сборщики используют `System.Drawing`).
* Полный Doom IWAD — `doom.wad` (подойдёт Doom Classic Bundle / Doom Classic 2019).
  Shareware `doom1.wad` не годится: в нём нет большей части кадров статус-бара и оружия.

### Как установить (кратко)

Пять шагов, по порядку: **(1)** положить `cl_dll/` в `<sdk>\cl_dll\` и `dlls/` в
`<sdk>\dlls\` (`<sdk>` — папка `hlsdk` установленного SDK) и собрать `hl_cdll.vcxproj` +
`hldll.vcxproj`, Release/Win32; **(2)** собрать спрайты `tools\build_all_scales.ps1`, указав
`-Wad` на свой `doom.wad`; **(3)** создать `<Half-Life>\dg_mod\` рядом с `valve\`: туда
`liblist.gam` (текст ниже), две собранные DLL как `cl_dlls\client.dll` и `dlls\hl.dll`,
спрайты в `sprites\` и оба `.cfg`; **(4)** запустить с `-game dg_mod -insecure`;
**(5)** играть. Ниже каждый шаг расписан подробно.

### Сборка игровых DLL

`<sdk>` — это папка `hlsdk` из установленного SDK, например
`D:\SteamLibrary\steamapps\common\Half-Life SDK\hlsdk`.

```
copy cl_dll\*.cpp cl_dll\*.h  <sdk>\cl_dll\
copy dlls\*.cpp               <sdk>\dlls\

MSBuild <sdk>\projects\vs2019\hl_cdll.vcxproj /p:Configuration=Release /p:Platform=Win32
MSBuild <sdk>\projects\vs2019\hldll.vcxproj   /p:Configuration=Release /p:Platform=Win32
```

Ошибка `MSB3073` после сборки безвредна: проекты просто пытаются скопировать результат в
демонстрационный `game\mod` из SDK. Забирайте
`<sdk>\projects\vs2019\Release\hl_cdll\client.dll` и `...\Release\hldll\hl.dll` и кладите
их в папку мода как `<mod>\cl_dlls\client.dll` и `<mod>\dlls\hl.dll` (игра должна быть
закрыта — она держит DLL).

### Сборка спрайтов

```
powershell -ExecutionPolicy Bypass -File tools\build_all_scales.ps1
```

Скрипт собирает наборы `dg<TAG>_*.spr`; в каждом 39 спрайтов — `stbar`, `face` (42 кадра),
`num` (10 кадров), `pct` и 35 кадров вьюмоделей. Параметры (дефолты указывают на машину
автора, так что задавайте их явно):

```
-Wad    <путь к doom.wad>
-Hud    <папка с PNG-патчами Doom>
-OutDir <mod>\sprites
-Tags   20,25,30,35,40,45,50        собрать только часть масштабов
-Clean                              сначала удалить файлы старых имён
```

| набор | x / y | на каком разрешении выбирается |
|---|---|---|
| `20` | 2.0 / 2.4 | 640×480 |
| `25` | 2.5 / 3.0 | 800×600, 854×480 |
| `30` | 3.0 / 3.6 | 1024×768, 960×600 |
| `35` | 3.5 / 4.2 | 1152×864 |
| `40` | 4.0 / 4.8 | 1280×720, 1280×800, 1280×960, 1280×1024, 1366×768 |
| `45` | 4.5 / 5.4 | 1440×900, 1440×1080 |
| `50` | 5.0 / 6.0 | 1600×1200, 1680×1050, 1920×1080, 1920×1200 |

### Разрешения

Наборы точно попадают в стандартные 4:3 (640×480, 800×600, 1024×768, 1152×864, 1280×960,
1440×1080, 1920×1200), а любое другое разрешение, включая широкоэкранные, получает
наибольший подходящий набор. Первым разрешением, проверенным в игре, был **800×600** — на
нём HUD и настраивался (он же эталонный набор, `dg25`); ещё проверены 1440×900 и 1440×1080.
Если разрешение выглядит не так, строка `doomhud: screen <W>x<H> -> tag <n>` в консоли
скажет, какой набор выбран.

### Установка — папка мода

Папки `dg_mod` в репозитории нет и быть не может: в ней лежат ваш `doom.wad` и собранные из
него спрайты. Она создаётся один раз рядом с `valve`:

```
<Half-Life>\
  hl.exe
  valve\                     родная игра (используется как fallback_dir)
  dg_mod\                    мод — это и создаётся
    liblist.gam              по нему движок понимает, что папка — игра
    cl_dlls\client.dll       собранный клиент
    dlls\hl.dll              собранный сервер
    sprites\dg20..dg50_*.spr собранные наборы спрайтов
    userconfig.cfg           m_pitch и скорости
    server.cfg               движение и автоприцел
    doom.wad                 ваш IWAD — только для сборки, в игре не читается
    hud\                     распакованные патчи Doom — только для сборки
```

1. **Создать папку** внутри установленного Half-Life, рядом с `valve`
   (`...\steamapps\common\Half-Life\dg_mod`). Имя любое; дальше считается, что `dg_mod`.
2. **Записать `liblist.gam`** — единственный файл, по которому движок видит игру; у меня он
   такой:

   ```
   game "Doomguy Mod"
   startmap "c1a0"
   trainmap "c1a0"
   mp_entitylist ""
   mp_filter ""
   gamedll "dlls\hl.dll"
   mpentity "info_player_start"
   secure "1"
   fallback_dir "valve"
   type "singleplayer_only"
   ```

   Главная строка — `fallback_dir "valve"`: карты, звуки, модели и меню берутся из обычного
   Half-Life, а из `dg_mod` подменяется только то, что в нём лежит. Данные игры копировать
   не нужно.
3. **Положить две собранные DLL**: `dg_mod\cl_dlls\client.dll` и `dg_mod\dlls\hl.dll`.
4. **Собрать спрайты** в `dg_mod\sprites\`. Клиент грузит только те наборы, что есть на
   диске, так что для проверки можно поставить один набор.

   `doom.wad` и `hud\` — только вход для сборщиков, они могут лежать где угодно (`-Wad` и
   `-Hud` указывают на них); держать их в папке мода просто удобно.
5. **Положить два конфига** (`userconfig.cfg` клиент выполняет после `config.cfg`,
   `server.cfg` — при старте listen-сервера):

   ```
   // dg_mod\userconfig.cfg
   unbind "PGUP"
   unbind "PGDN"
   unbind "INS"
   m_pitch "0"
   cl_forwardspeed 1000
   cl_backspeed 1000
   cl_sidespeed 1000
   r_drawviewmodel "1"
   ```

   ```
   // dg_mod\server.cfg
   sv_maxspeed 960
   sv_friction 20
   sv_accelerate 100
   sv_airaccelerate 100
   sv_aim 1
   sv_allow_autoaim 1
   ```

   Это значения, с которыми мод делался и проверялся; менять можно свободно — это обычные
   cvar'ы Half-Life.
6. **Запустить.** Steam → правый клик по Half-Life → *Свойства* → *Параметры запуска*:

   ```
   -game dg_mod -insecure
   ```

   `-insecure` **обязателен**: в защищённом режиме Steam отказывается грузить изменённые
   DLL. Для диагностики можно добавить `-console -condebug` (лог пишется в
   `dg_mod\qconsole.log`). Без Steam — та же командная строка у `hl.exe`.

После этого `New Game` запускает обычную кампанию Half-Life (`startmap c1a0`) с думовским
статус-баром, вьюмоделями и движением.

### Прочее

`r_drawviewmodel` клиент включает и выключает сам: выключен, пока в руках оружие с думовской
вьюмоделью, включён для оружия, оставшегося из Half-Life. `+use` и автоприцел работают на
сервере, привязок не требуют. Единственное, что стоит знать: набор спрайтов выбирается при
инициализации уровня, поэтому после смены видеорежима загрузите сейв, чтобы увидеть новый
размер.

Известные пробелы: сборщики лица и цифр читают патчи Doom как PNG из `-Hud` (опубликованного
экстрактора пока нет, статус-бар и вьюмодели уже читают WAD напрямую); диагностика всё ещё
вкомпилирована; `.357` использует спрайт пистолета, у эгона нет думовского аналога, а
бензопила (`SAWG`) не используется. Лицензии и благодарности — в английском разделе
*Licence / credits*.
