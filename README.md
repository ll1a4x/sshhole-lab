# sshhole-lab

A self-contained, local reproduction lab for **CVE-2026-123158** (*“*sshhole”*) —
a password-authentication bypass in `sshd` on Linux systems that use **musl
libc without PAM** (most notably Alpine Linux).

The lab builds a deliberately vulnerable container, verifies every precondition,
lets you land a shell on a locked account, and ships instrumentation that proves
the mechanism end-to-end at the `crypt()` level.

> **Authorized use only.** This repository exists for defensive security
> research, detection engineering, and remediation testing in an isolated,
> non-production environment you own. Everything runs locally in Docker and
> targets only the throwaway container it creates. Do not point the exploit at
> any host you are not explicitly authorized to test.

---

## The vulnerability in one paragraph

Without PAM, `sshd` checks passwords with the C library’s `crypt()`. For an
account whose `/etc/shadow` field is a bare `*` (locked / key-only / many
directory-service users), there is no real hash to compare against, so after the
CVE-2016-6210 timing mitigation `sshd` **borrows another account’s salt** via
`pick_salt()` and calls `crypt(password, borrowed_salt)`. On **musl**, `crypt()`
returns the literal string `"*"` on failure — a `$6$` sha512 salt fails for any
password longer than 256 bytes, and a `pick_salt`-mangled bcrypt salt fails
always. `sshd` then compares `"*"` (the crypt result) with `"*"` (the stored
field), they match, and authentication succeeds. Net effect: a locked `*`
account accepts **any password between 257 and 1024 bytes**.

- **Fixed in:** OpenSSH **10.6p2** (2026-11-05) and backported Alpine packages
  on every supported branch (e.g. `openssh-9.6_p1-r3` on Alpine 3.19).
- **Not affected:** glibc systems, anything going through PAM, Dropbear, OpenBSD.

Because current Alpine packages are already patched, the lab compiles **upstream
OpenSSH 9.6p1 from source** so the bug is actually present.

---

## Requirements

- Docker (Docker Desktop on macOS/Windows, or Docker Engine on Linux).
- `python3` and `expect` on the host — both ship with macOS. `expect` gives the
  exploit script an interactive shell; without it the script falls back to
  `SSH_ASKPASS`.
- Works on Apple Silicon and x86-64; the bug is architecture-independent.

---

## Quick start

```sh
chmod +x *.sh
./run.sh            # build the vulnerable image, start it, print the checks
./exploit.sh        # log into 'deploy' with a 300-char password -> shell
./cleanup.sh        # tear it all down when finished
```

Confirm the hit:

```sh
docker logs sshhole-lab | grep deploy
# -> Accepted password for deploy   (an account with '*' just authenticated)
```

That `Accepted password` line for a `*` account is the exact compromise
indicator from the disclosure.

---

## Files

| File | What it does |
|------|--------------|
| `Dockerfile`  | Alpine 3.19 base; compiles **upstream OpenSSH 9.6p1** `--without-pam`; creates `alice` (bcrypt borrow account) and `deploy` (shadow field forced to `*`). |
| `check.sh`    | Runs **inside** the container; verifies musl, the from-source (unpatched) build, no-PAM, password auth, and the `*`/borrow accounts. |
| `run.sh`      | Build + run + verify. Uses name `sshhole-lab` on port `2222`. |
| `exploit.sh`  | The attack: logs into the locked account with a 300-byte password. `expect` path yields an interactive shell; `SSH_ASKPASS` fallback otherwise. |
| `probe.sh`    | Diagnostic: calls `crypt()` directly inside the container across candidate borrowed-salts and key lengths, so you can see exactly what musl returns (look for `-> *`). |
| `trace.sh`    | Diagnostic: `LD_PRELOAD` shim logs every `crypt()` call `sshd` actually makes during a live login — arguments and return value — alongside the auth decision. |
| `cleanup.sh`  | Stops/removes the container(s) and image(s). |
| `LICENSE`     | Apache License 2.0. |
| `NOTICE`      | Attribution. |

All scripts take an optional container-name argument and default to
`sshhole-lab` (exploit/run also take an optional port, default `2222`):

```sh
./run.sh            [port]
./exploit.sh        [port] [user]
./probe.sh          [container]
./trace.sh          [container]
./cleanup.sh
```

---

## How it works, step by step

1. **`run.sh`** builds the image (compiling OpenSSH 9.6p1, ~1–2 min) and starts
   `sshd` in the foreground inside the container, mapped to `localhost:2222`.
2. **`check.sh`** confirms the five preconditions: musl libc, the unpatched
   from-source build, no PAM, `PasswordAuthentication yes`, a target account
   with a `*` field (`deploy`), and a borrow account with a real hash (`alice`).
3. **`exploit.sh`** sends a 300-byte password (inside the 257–1024 window) to
   `deploy`. `sshd` borrows `alice`’s salt, `crypt()` returns `"*"`, it matches
   `deploy`’s `"*"`, and you get a shell.
4. **`probe.sh`** / **`trace.sh`** are optional evidence: `probe.sh` shows the
   raw `crypt()` behavior; `trace.sh` shows `sshd` making that exact call during
   authentication.

### Expected evidence

`probe.sh` shows musl returning `*` for over-length `$6$` and for mangled
`$2y$05`:

```
   256 A | "$6$CvhFSGk3AHl4k36J" -> $6$...            (real hash)
   257 A | "$6$CvhFSGk3AHl4k36J" -> *                 (trigger)
    10 A | "$2y$05"              -> *                 (mangled bcrypt, any length)
```

`trace.sh` against the vulnerable image shows the call and the acceptance:

```
[cryptlog] crypt(keylen=300, salt="$2y$05") = "*"
Accepted password for deploy ...
```

---

## Remediation (what to put in a report)

```sh
# Update and restart the daemon (upgrading the package alone is not enough).
apk upgrade -U openssh && rc-service sshd restart

# Or, if you cannot update yet, disable password auth entirely:
echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/00-no-passwords.conf
rc-service sshd restart
```

Real-world exposure is limited to musl-based, PAM-less hosts and container
images **built or last patched before 2026-11-05**; a current `apk add openssh`
on a supported branch already pulls the fixed package.

**Detection:** in `sshd` auth logs, an `Accepted password` for an account whose
`/etc/shadow` field is `*` (should be password-login-impossible) indicates prior
exploitation.

---

## References

- Alpine Linux advisory — <https://alpinelinux.org/posts/2026-11-05-openssh-password-authentication-bypass/>
- CVE-2026-123158 and per-branch fixed versions — <https://www.ionix.io/blog/sshhole-cve-2026-123158-and-how-ionix-is-helping-you-respond/>
- Original disclosure — <https://sshhole.com>

---

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](./LICENSE) and
[`NOTICE`](./NOTICE). OpenSSH is downloaded from the upstream project at build
time and is covered by its own license; it is not redistributed here.
