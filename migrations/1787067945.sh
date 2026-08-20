echo "Switch ligolo-ng-git to the ligolo-ng package the Monarch repo actually builds"

# monarch-base.packages asked pacman for `ligolo-ng-git`, a name the Monarch
# repo no longer produces: pkgbuilds/ligolo-ng builds `ligolo-ng` (0.9) with
# provides=('ligolo-ng') and conflicts=(... 'ligolo-ng-git'), so as far as
# pacman is concerned they are two different packages and the -git name
# resolves to nothing. Installs kept working only because the repo still served
# a stale ligolo-ng-git-0.8.2 artifact built before the rename — once that is
# cleaned out, the base package list breaks on fresh installs.

# Only swap once the new package is actually reachable. A machine whose sync db
# predates the promotion would otherwise end up with neither: the drop below
# succeeds and the add finds nothing. No `pacman -Sy` here — refreshing one db
# behind the user's back is how partial upgrades start.
if ! pacman -Si ligolo-ng &>/dev/null; then
  echo "ligolo-ng is not in the synced repos yet — leaving ligolo-ng-git in place."
elif monarch-pkg-present ligolo-ng; then
  echo "Already on ligolo-ng — nothing to do."
else
  # Drop first: the conflicts entry makes pacman refuse to install ligolo-ng
  # while ligolo-ng-git is present, and --noconfirm answers that prompt with
  # the default "no" — the whole transaction would abort.
  monarch-pkg-drop ligolo-ng-git
  monarch-pkg-add ligolo-ng
fi
