# Proton-CachyOS-XDG-portal

Proton-CachyOS with native file dialogs: Windows programs' Open, Save and
folder pickers go through the XDG Desktop Portal, so you get your desktop's
own file chooser (KDE, GNOME, etc.) instead of Wine's. "Open folder location"
opens your file manager too, instead of Wine's folder window.

It is upstream [Proton-CachyOS](https://github.com/CachyOS/proton-cachyos)
plus the patches in `patches/wine/`, which come from Wine merge request
[!10060](https://gitlab.winehq.org/wine/wine/-/merge_requests/10060).

## Installing

1. Download `Proton-CachyOS-XDG-portal-<version>-x86_64.tar.xz` from the
   Releases page (`x86_64_v3` is a faster build for CPUs from about 2015 on).
2. Extract it into Steam's compatibility tools folder:
   - Steam: `~/.steam/root/compatibilitytools.d/`
   - Flatpak Steam: `~/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d/`
3. Restart Steam, then pick **Proton-CachyOS-XDG-portal-…** under the game's
   Properties → Compatibility.

Lutris, Heroic, Faugus and umu-launcher can use the same extracted folder as a
custom Proton.

You need a portal backend running on the host (`xdg-desktop-portal` plus
`-kde`, `-gnome` or `-gtk`). Every mainstream desktop ships one.

## Choosing when the portal is used

| Setting | Effect |
| --- | --- |
| *(default)* auto | Use the portal when the dialog's options are compatible; fall back to Wine's dialog for customised ones |
| `WINE_FORCE_PORTAL=1 %command%` | Always use the portal, even when some customisations are lost |
| winecfg → Desktop Integration → File dialogs | Per-prefix auto / always / never |

**Electron- and Chromium-based programs need `WINE_FORCE_PORTAL=1`.** Chromium
always registers `IFileDialogEvents` listeners on its dialogs, and under `auto`
the portal is skipped whenever a dialog has event listeners, custom controls or
options the portal cannot express — so `auto` can never succeed for them and you
silently get Wine's dialog. Verified with
[Warudo](https://store.steampowered.com/app/2079120/), whose UI is an Electron
app: unusable on `auto`, correct with the variable set.

Folder locations are not gated this way — they follow the same setting but only
`never` turns them off, since there are no dialog options to be incompatible
with.

The winecfg option is stored as the string value `FileDialogPortal`
(`auto`, `always` or `never`) under `HKCU\Software\Wine\X11 Driver`. Like other
Wine settings it can also be set for a single program under
`HKCU\Software\Wine\AppDefaults\<program>.exe\X11 Driver`. With Proton you can
reach winecfg through protontricks: `protontricks <appid> winecfg`.

If a program misbehaves, set the policy to **never** for it to get Wine's own
dialog back. `WINE_FORCE_PORTAL=1` overrides every registry setting.

## What's in `patches/wine/`

| Patch | Origin |
| --- | --- |
| 0001–0005 | Alexander Wilms, Wine MR !10060 (comdlg32 portal backend, IFileDialog routing, winecfg option, test, shell32 folder picker) |
| 0006–0007 | [WeComWine](https://github.com/loveyu/WeComWine) follow-up fixes (long portal paths, crash when the desktop folder can't be opened) |
| 0008 | This fork: "open folder location" opens the host file manager (shell32) |

Changes made when porting to Proton-CachyOS:

- `comdlg32/Makefile.in`: hunk context adjusted (Proton's file lacks the
  version-string lines upstream has).
- winecfg: the portal policy strings use IDs **60–62** instead of 19–21,
  because Proton-CachyOS already uses 19 and 20 for its Staging and Input tabs.
  Keeping upstream's numbers would compile but show the wrong labels.

The portal code ships a small Unix-side library (`comdlg32.so`) that loads
`libdbus-1.so.3` at runtime, so there is no new hard dependency.

**Status:** !10060 is still a draft upstream and its author notes it was
written with an LLM. Expect rough edges; report dialog problems here, not to
CachyOS or WineHQ.

## Maintaining the fork

`xdg-portal/BASE` records which upstream release this branch is built on.

### Moving to a new upstream release

```sh
xdg-portal/sync-upstream.sh            # newest upstream release
# or: xdg-portal/sync-upstream.sh cachyos-11.0-20261107-slr
```

The script:

1. fetches upstream's tags;
2. applies `patches/wine/*.patch` with `patch -Np1` (exactly as Proton's build
   does) to the Wine commit the new release pins, and checks winecfg string
   IDs for collisions;
3. creates branch `xdg-portal-<version>` from the upstream tag and replays the
   fork's commits on top.

It stops with an explanation if a patch no longer applies or a commit
conflicts. It never pushes; it prints the push and tag commands at the end.

### Publishing a release

Tags named after the upstream version (e.g. `11.0-20261015`, or
`11.0-20261015-r2` for a respin) trigger `.github/workflows/release.yml`, which
builds `x86_64`, `x86_64_v3` and `arm64` on GitHub-hosted runners and attaches
the `.tar.xz` files to a GitHub release. Upstream's own `cachyos-*` tags don't
trigger it.

```sh
git tag -a 11.0-20261015 -m "Proton-CachyOS-XDG-portal 11.0-20261015"
git push origin 11.0-20261015
```

GitHub Actions must be enabled on the fork (Actions tab → enable workflows).

### Building locally

Needs Docker or Podman, and git-lfs for the submodule checkout; the first build
downloads the Steam Runtime SDK image and takes a few hours.

```sh
git submodule update --init --recursive
mkdir build && cd build
../configure.sh --build-name=Proton-CachyOS-XDG-portal-11.0-20261015 --container-engine=docker
make redist        # -> Proton-CachyOS-XDG-portal-11.0-20261015.tar.xz
# or: make install # installs straight into ~/.steam/root/compatibilitytools.d
```

The build name is what Steam shows in its compatibility tool list.

Add `--enable-ccache` to `configure.sh` when building more than one variant. It
does not help across variants that differ in `-march`, though: each set of
compiler flags has its own cache keys, so a second variant is close to a full
rebuild.

#### If the submodule checkout fails

`git submodule update` stopping with `smudge filter lfs failed` means git-lfs is
missing. One of gstreamer's test-media submodules keeps its videos in LFS, and
that one failure aborts the whole recursive walk, so submodules ordered after it
(`wine`, `vkd3d-proton`) stay empty and the build later dies on a missing source
file such as `openfst/configure.ac`. Either install git-lfs, or skip the LFS
files — the build does not use them:

```sh
git -c filter.lfs.smudge=cat -c filter.lfs.process= -c filter.lfs.required=false \
    submodule update --init --recursive
```

An aborted walk can also leave submodules that `git submodule status` reports as
clean while their working tree is empty, because the recorded commit already
matches the submodule's HEAD, so a plain re-run skips them. `--force` checks
them out:

```sh
git submodule update --init --force --recursive
```

## License

Same as upstream: Proton is BSD-licensed and Wine is LGPL-2.1-or-later. The
Wine changes are in `patches/wine/` and the full source is this repository, so
publishing releases from a public fork meets the LGPL source requirement.
