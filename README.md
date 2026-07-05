# Ubuntu GNU Coreutils Switch

Switch Ubuntu's selectable coreutils implementation back to GNU coreutils.

Ubuntu 25.10 and newer can expose selector packages such as
`coreutils-from-uutils` and `coreutils-from-gnu`. This script installs the GNU
selector, removes installed non-GNU selectors in the same apt transaction, and
verifies representative commands report `GNU coreutils`.

## Usage

```bash
bash install-gnu-coreutils.sh
```

or:

```bash
chmod +x install-gnu-coreutils.sh
./install-gnu-coreutils.sh
```

The script uses `sudo` when it is not already running as root.

## What It Does

- Installs `coreutils`, `coreutils-from-gnu`, and `gnu-coreutils` when Ubuntu's implementation selector packages are available.
- Removes installed non-GNU selector packages in the same apt transaction: `coreutils-from-uutils`, `coreutils-from-busybox`, `coreutils-from-toybox`, and `rust-coreutils`.
- Uses `--allow-remove-essential` only for that selector swap because Ubuntu marks the active coreutils implementation as essential.
- Falls back to reinstalling the regular `coreutils` package on Debian and older Ubuntu releases where `coreutils` is already GNU coreutils.
- Verifies `ls`, `cp`, `sort`, and `date` report `GNU coreutils`.

## Safety Notes

The active coreutils implementation is an essential package. The script allows
essential-package removal only for the apt transaction that installs the GNU
replacement at the same time.

Review the apt transaction before continuing on systems you care about. A VM,
snapshot, or recent backup is recommended because this changes commands that are
part of the base operating system.

If apt cannot complete that selector swap, the script records the failure,
skips any separate non-GNU cleanup, verifies the current command versions, and
exits non-zero.

## Requirements

- Ubuntu or another Debian-based apt system
- Bash
- `apt-get`, `apt-cache`, and `dpkg-query`
- `sudo` access when not running as root

## Verification

For syntax and shell lint checks:

```bash
bash -n install-gnu-coreutils.sh
shellcheck install-gnu-coreutils.sh
```

## License

MIT. See [`LICENSE`](./LICENSE).
