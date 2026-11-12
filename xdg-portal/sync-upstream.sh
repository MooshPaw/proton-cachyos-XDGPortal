#!/usr/bin/env bash
# Move the Proton-CachyOS-XDG-portal fork onto a newer upstream proton-cachyos
# release, and check that the Wine portal patches still apply to the Wine
# commit that release pins.
#
# Usage (run from the root of your fork's checkout):
#   xdg-portal/sync-upstream.sh                      # newest upstream *-slr tag
#   xdg-portal/sync-upstream.sh cachyos-11.0-20261107-slr
#
# Nothing is pushed. At the end the script prints the commands to push the new
# branch and tag, which is what starts the GitHub release build.

set -euo pipefail

UPSTREAM_URL="https://github.com/CachyOS/proton-cachyos.git"
WINE_URL="https://github.com/CachyOS/wine-cachyos.git"

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }

[ -f xdg-portal/BASE ] && [ -d patches/wine ] ||
    die "run this from the root of the Proton-CachyOS-XDG-portal checkout"
[ -z "$(git status --porcelain --untracked-files=no)" ] ||
    die "the working tree has uncommitted changes; commit or stash them first"
command -v patch >/dev/null || die "'patch' is not installed"

old_base=$(cat xdg-portal/BASE)
cur_branch=$(git symbolic-ref --short HEAD)

# --- 1. Find the upstream release to move to --------------------------------
if ! git remote get-url upstream >/dev/null 2>&1; then
    info "Adding remote 'upstream' -> $UPSTREAM_URL"
    git remote add upstream "$UPSTREAM_URL"
fi
info "Fetching upstream tags"
git fetch --quiet upstream 'refs/tags/cachyos-*:refs/tags/cachyos-*'

new_base=${1:-$(git tag -l 'cachyos-*-slr' --sort=-v:refname | head -n1)}
git rev-parse -q --verify "refs/tags/$new_base" >/dev/null ||
    die "upstream tag '$new_base' not found"
[ "$new_base" != "$old_base" ] || die "already based on $new_base, nothing to do"

version=${new_base#cachyos-}
version=${version%-slr}
new_branch="xdg-portal-$version"
info "Current base: $old_base"
info "New base:     $new_base  (release version $version)"

git rev-parse -q --verify "refs/heads/$new_branch" >/dev/null &&
    die "branch '$new_branch' already exists; delete it or pass another tag"

# --- 2. Check the Wine patches against the new release's Wine commit --------
wine_sha=$(git ls-tree "$new_base" wine | awk '{print $3}')
[ -n "$wine_sha" ] || die "could not read the wine submodule commit from $new_base"
info "Upstream $version pins wine-cachyos at ${wine_sha:0:12}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init --quiet wine
git -C "$tmp/wine" fetch --quiet --depth 1 "$WINE_URL" "$wine_sha"
git -C "$tmp/wine" checkout --quiet FETCH_HEAD

info "Applying the portal patches the way Proton's build does (patch -Np1)"
failed=""
while IFS= read -r p; do
    if out=$(patch -d "$tmp/wine" -Np1 --no-backup-if-mismatch -i "$PWD/$p" 2>&1); then
        ok "$(basename "$p")"
    else
        printf '%s\n' "$out" | sed 's/^/      /'
        failed="$p"
        break
    fi
done < <(find patches/wine -name '*.patch' | sort)

if [ -n "$failed" ]; then
    die "$(basename "$failed") no longer applies to wine ${wine_sha:0:12}.
       Rebase the series in a wine-cachyos checkout at that commit, regenerate the
       files in patches/wine/, then run this script again."
fi

# winecfg string IDs share one table; a silent collision shows wrong labels
# instead of failing the build, so check it explicitly.
dups=$(grep -E '^#define[[:space:]]+IDS_[A-Z0-9_]+[[:space:]]+[0-9]+' \
           "$tmp/wine/programs/winecfg/resource.h" |
       awk '{print $3}' | sort | uniq -d)
[ -z "$dups" ] ||
    die "winecfg string ID collision after patching (IDs: $(echo $dups)).
       Renumber IDS_FILEDIALOG_PORTAL_* in the winecfg patch."
ok "no winecfg string ID collisions"

# --- 3. Rebuild the fork branch on top of the new release --------------------
# Earlier "rebase onto" commits only bump xdg-portal/BASE; skip them so the
# history doesn't grow one bookkeeping commit per upstream release.
fork_commits=""
for c in $(git rev-list --reverse "$old_base..$cur_branch"); do
    [ "$(git diff-tree --no-commit-id --name-only -r "$c")" = "xdg-portal/BASE" ] && continue
    fork_commits="$fork_commits $c"
done
fork_commits=${fork_commits# }
[ -n "$fork_commits" ] || die "found no fork commits between $old_base and $cur_branch"

info "Creating $new_branch from $new_base and replaying $(echo $fork_commits | wc -w) fork commit(s)"
git switch --quiet -c "$new_branch" "$new_base"
for c in $fork_commits; do
    if ! git cherry-pick --allow-empty "$c" >/dev/null; then
        die "cherry-pick of $(git log -1 --format='%h %s' "$c") hit a conflict
       (usually upstream changed .github/workflows). Resolve it, run
       'git cherry-pick --continue', then cherry-pick the remaining commits:
       $(echo $fork_commits)"
    fi
done

echo "$new_base" > xdg-portal/BASE
if ! git diff --quiet -- xdg-portal/BASE; then
    git commit --quiet -m "xdg-portal: rebase onto $new_base" -- xdg-portal/BASE
fi
ok "branch $new_branch is ready"

cat <<EOF

Next steps:
  git push -u origin $new_branch
  git tag -a $version -m "Proton-CachyOS-XDG-portal $version"
  git push origin $version        # starts the release build on GitHub

The release will be named Proton-CachyOS-XDG-portal-$version-x86_64.
EOF
