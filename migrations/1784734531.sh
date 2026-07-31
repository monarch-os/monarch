echo "Restore root ownership of /opt, which the old SecOps installer handed to the user"

# monarch-install-secops used to run `sudo chown $USER:$USER /opt` so that it
# could create /opt/secops without sudo. That leaves a package-owned directory
# writable by the user: any process running as them can drop in or replace a
# binary under /opt, including the root-installed trees other installers put
# there (/opt/BurpSuiteCommunity, /opt/BurpSuitePro, and packages such as
# arduino-ide-bin or beeper-bin). pacman reports the deviation as
# "filesystem: /opt (UID mismatch)".
#
# Only /opt itself is corrected, never its contents: the directories inside it
# legitimately belong to the packages that own them, so a recursive chown would
# break them instead.

if [[ -d /opt ]]; then
  opt_owner=$(stat -c '%U:%G' /opt 2>/dev/null)

  if [[ -n $opt_owner && $opt_owner != "root:root" ]]; then
    echo "  /opt is owned by $opt_owner; resetting it to root:root 755"
    sudo chown root:root /opt
    sudo chmod 755 /opt
  fi

  unset opt_owner
fi
