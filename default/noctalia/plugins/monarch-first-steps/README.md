# First steps

An optional guide to getting started with Monarch, offered once at the first
login after a fresh installation. The panel currently uses French labels;
quoted labels below match the interface.

## Opening the guide

Open **monarch-menu → Documentation → Premiers pas**, or run:

```bash
monarch setup first-steps
```

Open the menu with **Win + Alt + Space**. The guide resumes at the last visited
step. To start again from the welcome page:

```bash
monarch setup first-steps reset
```

## Walkthrough

1. **Network connection** ("Se connecter"): network status for Wi-Fi or Ethernet
   and the Monarch network panel (`monarch/network:panel`), also used by the bar.
   Closing that panel returns to the guide and refreshes the connection status.
   The return path also follows its QR-code and speed-test subpanels, but leaves
   unrelated panels alone.
2. **System updates** ("Mettre Monarch à jour"): repository and AUR checks run
   when entering the step, returning from the terminal, or reconnecting. The
   guide displays the available update count or "Système à jour" (up to date),
   and offers package installation only when an update is found. A network or
   repository failure displays "Vérification impossible" (check failed), never
   a false up-to-date result. "Vérifier à nouveau" starts another check.
   If only the AUR check fails, verified repository updates remain available,
   with "Au moins N mises à jour" (at least N updates) and "AUR : non vérifié"
   (AUR not checked). The updater explains this limitation before confirmation
   and skips AUR updates for that transaction. Without any known updates, the
   incomplete check remains an error.
   A repository-check failure also offers "Vérifier dans le terminal". The
   updater can then offer to refresh signing keys and retry the check once;
   simply opening the guide never triggers privileged repair.
   Checks use a temporary package database, without sudo or changes to the
   system database. A recorded successful update neither replaces a fresh check
   nor prevents later updates from being offered.
   The guide calls `monarch-update-available --all --json`; exit code 1 means
   packages are current, not that the check failed.
   Installation uses the existing update command in a terminal. `monarch update`
   checks availability again before confirmation. If packages are already
   current, it resumes only configuration finalization and post-update tasks.
   The guide hides while the terminal is open and returns after the result is
   acknowledged, provided the desktop is available and unlocked.
   The result remains visible in the guide, and cancelled or failed attempts
   can be retried. If packages are current after an unsuccessful attempt,
   "Finaliser la mise à jour" remains available to resume unfinished tasks.
   "Plus tard" lets users continue without a network connection or an update.
3. **Getting around** ("Se repérer"): the actual configured shortcuts and their
   complete list.
4. **Appearance** ("Choisir son style"): the existing theme picker and wallpapers.
5. **Software and cybersecurity tools** ("Logiciels et outils cyber"): the general
   Software catalog, Software → Cyber, and installation of Burp Suite, RF Swift
   and SecLists.

The general documentation link and monarch-menu shortcut remain visible.
Caido and Exegol are included with Monarch. Closing an explored panel returns
to the same step in the guide.

Clicking "Installer" starts an installation in a terminal where progress is
visible. Burp Suite offers Community or Pro. Installed tools show "✓ Installé";
an active installation shows "En cours". Only one installation can run at a time.
The lock follows the installation processes. After interruption or reboot, stale
state is recovered on the next status check or launch. Detailed errors remain
available in the terminal.

Clicking outside the guide or pressing Escape leaves it open. The close button,
"Passer" and "C’est parti" close it. The surrounding desktop remains usable.

## First login and state

`monarch-provision-user` prepares the automatic offer only when initializing a
new user. `monarch-provision-first-run`, started by Niri at session startup,
opens the guide after setup and Noctalia plugin activation.
Networking and updates are offered through the guide only; they no longer
produce competing first-login notifications.

The guide waits for an available, unlocked desktop. The plugin confirms that
it opened before the first offer is consumed. If Noctalia is not ready, the
desktop remains busy, or opening fails, the offer stays pending and is retried
at the next login without repeating setup.

State is stored in `$XDG_STATE_HOME/monarch/first-steps`, which defaults to
`~/.local/state/monarch/first-steps`:

- `pending`: first offer awaiting a confirmed opening;
- `shown`: guide already displayed, automatically or manually;
- `progress`: last visited step;
- state and result of the last tool installation;
- `update-result.json`: update result, retained across subsequent tool
  installations. Updates share the installation lock to prevent concurrent
  jobs launched from the guide.

Closing or skipping the guide does not remove `shown`. The `reset` command
restarts the walkthrough manually without rearming its automatic startup offer.
Existing users retain menu access without an automatic offer during upgrades.

```bash
monarch setup first-steps state
```

The installed runtime can remain read-only: the guide uses the plugins shipped
with Monarch and writes only to user state.

## Validation

Isolated tests cover opening from the actual first-login entry point, the
one-time offer, manual resumption, locked or unavailable desktops, unconfirmed
opens, concurrent attempts, and installation lifecycles with substitute
installers.

Visual validation covers the welcome page, five steps and conclusion, visits to
existing panels, and closing behaviour. Real installations use the existing
Monarch scripts.
