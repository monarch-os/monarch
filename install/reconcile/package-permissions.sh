set -euo pipefail

if ((EUID == 0)); then
  system_root=/
  trusted_uid=0
  package_paths=$(/usr/bin/pacman -Qql monarch)
  if /usr/bin/pacman -Qq monarch-settings >/dev/null 2>&1; then
    package_paths+=$'\n'$(/usr/bin/pacman -Qql monarch-settings)
  fi
else
  system_root=${MONARCH_PACKAGE_PERMISSIONS_TEST_ROOT:?}
  trusted_uid=$EUID
  package_paths=$(cat "${MONARCH_PACKAGE_PERMISSIONS_TEST_PATHS:?}")
fi

# Pacman keeps existing directory modes; old ISO packages shipped 777/666.
/usr/bin/python3 -I - "$system_root" "$trusted_uid" 3<<<"$package_paths" <<'PY'
import errno
import os
import stat
import sys

root, uid = sys.argv[1], int(sys.argv[2])
flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
root_fd = os.open(root, flags | os.O_DIRECTORY)
try:
    if os.fstat(root_fd).st_uid != uid:
        raise PermissionError('untrusted system root')
    with os.fdopen(3) as entries:
        paths = sorted(set(entries.read().splitlines()), key=lambda p: (p.count('/'), p))
    for path in paths:
        parts = path.strip('/').split('/')
        if not path.startswith('/') or any(part in ('', '.', '..') for part in parts):
            continue
        parent_fd = os.dup(root_fd)
        target_fd = None
        try:
            for part in parts[:-1]:
                next_fd = os.open(part, flags | os.O_DIRECTORY, dir_fd=parent_fd)
                os.close(parent_fd)
                parent_fd = next_fd
                if os.fstat(parent_fd).st_uid != uid:
                    break
            else:
                metadata = os.stat(parts[-1], dir_fd=parent_fd, follow_symlinks=False)
                if not (stat.S_ISDIR(metadata.st_mode) or stat.S_ISREG(metadata.st_mode)):
                    continue
                target_fd = os.open(parts[-1], flags, dir_fd=parent_fd)
                metadata = os.fstat(target_fd)
                if metadata.st_uid != uid:
                    continue
                mode = stat.S_IMODE(metadata.st_mode)
                if stat.S_ISDIR(metadata.st_mode) and mode == 0o777:
                    os.fchmod(target_fd, 0o755)
                elif stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1:
                    if mode in (0o666, 0o777):
                        os.fchmod(target_fd, mode & ~0o022)
        except OSError as error:
            if error.errno not in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
                raise
            # Missing files and symlinked paths are not repair targets.
        finally:
            if target_fd is not None:
                os.close(target_fd)
            os.close(parent_fd)
finally:
    os.close(root_fd)
PY
