# Manual drive password changes

This contract covers `bin/monarch-drive-password`, its dedicated privileged helper `install/drive-password/rekey.sh`, and the read-only metadata adapter `install/drive-password/metadata.py`. It does not define factory-reset or owner-provisioning transitions. User-facing instructions belong in GitBook and must be updated before delivery; no GitBook publication is authorized by this development change.

## Privilege and secret boundaries

The user command retains drive selection and confirmed GUM input for the new password. It invokes only `/usr/bin/bash -p /usr/share/monarch/install/drive-password/rekey.sh` through sudo. The installed helper and its ancestors must be root-owned and not writable by unprivileged users. Never replace this fixed path with a session-selected runtime or execute a development checkout as root.

The helper requires privileged Bash and root, fixes PATH and locale, and revalidates the selected block device and LUKS UUID. Privileged Bash suppresses inherited startup files and exported functions before execution. The new password travels over stdin; the current password is read without echo from `/dev/tty`. Cryptsetup receives passwords through file descriptors, never argv, environment variables or journal data. Tracing, verbose input and automatic variable export are disabled before secret input.

The read-only adapter is also invoked by a fixed installed path, using `/usr/bin/python3 -I /usr/share/monarch/install/drive-password/metadata.py`. Isolated Python ignores user-controlled Python paths and startup configuration. Both helper files must ship together in the root-owned runtime package.

Passphrase proofs target a specific key slot with `open --test-passphrase --key-slot` and `--token-type passphrase-only`, preventing an automatic TPM, FIDO or keyring token from substituting for the supplied password. Exit status 2 is treated as an incorrect passphrase; other cryptsetup failures stop the transition as tool errors. Each cryptsetup invocation has a 120-second deadline.

## Durable journal and transitions

The helper holds `/run/monarch-drive-password.lock` before reading journal or slot state. Its descriptor remains open during child operations. Journals are stored at `/var/lib/monarch-drive-password/<UUID>.json` in a root-only 0700 directory, with mode 0600. Symlinks, unexpected permissions, invalid JSON, an unknown schema or a mismatched UUID are rejected rather than discarded or sourced.

The versioned journal records the UUID, the initial key-slot metadata, the selected old slot, an explicitly allocated free target slot and one of two phases. The existing version-1 LUKS2 journal representation is unchanged; LUKS1 entries have a distinct `luks1` type and cannot be mistaken for LUKS2 entries:

- `prepared`: durable before adding the new key. Every initial slot must retain its metadata. The helper must prove the current password on the recorded old slot before proceeding.
- `verified`: durable after proving the new password on the target slot and recording that slot's metadata, but before retiring the old slot. The target must retain its recorded metadata and pass a fresh password proof. The old slot may already be absent if deletion completed before an interruption.

Publication writes a private temporary file in the journal directory, synchronizes it with `sync -f`, renames it atomically over the journal and synchronizes the directory before the next destructive operation. The journal is removed and the directory synchronized only after the old slot is absent and the new password passes final verification. An uncatchable interruption can leave private metadata-only temporary files; the helper does not broadly purge residual files.

Only the recorded old slot can be retired. Recovery slots are not reduced to a provisioning invariant such as “one owner slot.” Baseline slot replacement or disappearance is rejected, except for old-slot disappearance in `verified`. Additional independent slots outside the selected target are preserved.

## Format-specific metadata

For LUKS2, the binary header identifies the format and cryptsetup's `luksDump --dump-json-metadata` supplies the key-slot objects. Existing key-slot objects and the verified target object must retain their recorded values.

For LUKS1, the adapter reads exactly the 1024-byte binary header, not localized `luksDump` text or a guessed JSON fallback. The layout comes from the official [cryptsetup LUKS1 header definition](https://gitlab.com/cryptsetup/cryptsetup/-/blob/main/lib/luks1/luks.h) and [header validation/key management implementation](https://gitlab.com/cryptsetup/cryptsetup/-/blob/main/lib/luks1/keymanage.c): network byte order, a 208-byte common prefix, eight 48-byte key-slot entries and padding. Validation checks magic/version, the expected UUID, terminated cipher/hash fields, key size and digest iterations, recognized activation markers, active-slot iterations, AF stripes, area offsets, non-overlap and data-boundary constraints. Cryptsetup still validates and authenticates the volume; this parser does not replace its cryptographic checks or read decrypted keys.

Each active LUKS1 slot is represented by SHA-256 fingerprints of the common prefix and its complete binary entry. The entry includes activation state, PBKDF2 iterations, its 32-byte random password salt, material offset and AF stripes. Ordinary cryptsetup re-enrollment generates a fresh salt, so reusing an old slot number for an independent recovery key changes its identity and stops the resume before deletion. Global header changes likewise invalidate every recorded slot. Fingerprints cover metadata, not the encrypted AF material: ciphertext corruption with unchanged metadata is detected for the selected old/new slots by password proofs, not by a global recovery-key integrity check. An administrator who directly rewrites ciphertext while deliberately retaining all metadata is not serialized by this helper.

LUKS1 allocates only slots 0–7 and uses its supported PBKDF2 KDF, preserving the volume's existing hash; LUKS2 allocates within slots 0–31 and uses Argon2id. Both retain the 2000 ms enrollment cost, journal transitions, per-slot passphrase-only proofs and explicit confirmations. A full slot table is rejected without an unjournaled in-place key change or automatic conversion. The [official luksAddKey manual](https://gitlab.com/cryptsetup/cryptsetup/-/blob/main/man/cryptsetup-luksAddKey.8.adoc) specifies the LUKS1 shared PBKDF/hash constraint.

## Resume and explicit choices

Rerunning the command for the same UUID resumes its journal. Supply the password intended for the new slot when prompted for the new password. A wrong password or a tool error does not authorize deletion.

If the target slot exists while the journal is still `prepared`, its number alone does not establish ownership. The helper first proves the new password on that target, rejects a new password opening another existing slot, and proves the current password on the old slot. It then requires the exact terminal confirmation `ADOPT <UUID> <slot>`, warning that the target must belong to this interrupted change rather than an independent recovery enrollment. Refusing confirmation leaves both slots and the journal intact. A target holding a different recovery password fails the proof and is left untouched.

If the current password opens multiple slots on a fresh attempt, the user must choose one matching slot and type `REPLACE <slot>` after an explicit warning. Only that slot is replaced. **The old password remains valid through every other copy that was preserved.** This operation does not claim global revocation of a duplicated secret.

Once `verified`, a resume rechecks the recorded target's metadata and password. If the old slot is still present, its current-password proof is required before deletion. If it is already absent, the new password alone can complete the journal; the revoked secret is not required. There is no automatic rollback to the old password. Ambiguous or invalid state requires manual review rather than inferred slot ownership or automatic journal removal.

## Validation limits

Both LUKS1 and LUKS2 are supported by the journaled path; there is no fallback to unjournaled `luksChangeKey`. Unknown, malformed or truncated headers stop before modification. The adapter does not attempt header repair or format conversion. LUKS1 has no redundant transactional metadata header: a torn sector/header write, or interruption during cryptsetup's internal key-material wipe before its header update, may require manual recovery. A still-listed old slot that no longer accepts its old password is not deleted by guessing; the verified new slot and journal are retained. Resume guarantees apply when the header remains structurally readable and the recorded identities can be proved, not to recovery from arbitrary media corruption.

Factory reset and provisioning rekey also acquire this lock before inspecting or mutating their disk transitions. A manual change refuses unfinished first-boot provisioning, including its residual journal; a completed provisioning journal permits later manual changes and independent recovery slots. Reset/provisioning refuse a pending manual journal for the same UUID. Direct administrator cryptsetup calls do not automatically honor the lock. UUID and slot rechecks detect observed changes but cannot make a multi-command transition atomic against another root tool ignoring it.

`test/monarch-drive-password-test.sh` executes the same behavioral matrix for LUKS1 and LUKS2 with host boundaries replaced by fixtures: interrupted add/delete and journal publication, durability errors, invalid journals and permissions, slot/format replacement, recovery enrollment, full slot tables, passphrase/token separation, duplicated secrets, lock exclusion and secret transport. LUKS1 scenarios run the actual binary parser against constructed headers, including malformed fields and reused slot salts; LUKS2 retains the JSON adapter coverage. These are not real-volume or power-loss acceptance tests.

Before delivery, validate the installed package ownership and fixed helper paths, real LUKS1/LUKS2 cryptsetup and descriptor semantics, actual persistence across power loss, header-capacity failures, recovery keys, and enrolled TPM/FIDO/keyring behavior in a disposable system. No destructive host test or VM validation is established by the fixture suite. Publish the corresponding GitBook user guidance only with separate authorization before delivery.
