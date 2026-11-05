#!/bin/sh
# Runs INSIDE the container. Confirms the build is the vulnerable one and that
# every precondition for CVE-2026-123158 holds.
echo "----- *sshhole / CVE-2026-123158 preconditions -----"
printf  "libc:           "; ldd /bin/sh 2>&1 | grep -qi musl && echo "musl  (candidate)" || echo "glibc (SAFE)"
printf  "sshd build:     "; ssh -V 2>&1
if apk info -e openssh >/dev/null 2>&1; then
  echo  "openssh source: apk package present -> $(apk info -v 2>/dev/null | grep '^openssh-[0-9]')  (if r3+, PATCHED)"
else
  echo  "openssh source: built from upstream tarball, no apk patch -> UNPATCHED"
fi
printf  "PAM:            "; sshd -T 2>/dev/null | grep -i '^usepam' || echo "no PAM (built --without-pam) -> EXPOSED"
printf  "passwordauth:   "; sshd -T 2>/dev/null | grep -i '^passwordauthentication'
echo    "'*' target(s):  $(awk -F: '$2=="*"{print $1}' /etc/shadow | tr '\n' ' ')"
echo    "borrow acct(s): $(awk -F: '$2 ~ /^\$/{print $1}' /etc/shadow | tr '\n' ' ')"
echo    "---------------------------------------------------"
