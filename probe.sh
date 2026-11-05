#!/usr/bin/env bash
# Directly probe what musl's crypt() returns INSIDE the lab container, for the
# exact salts sshd's pick_salt() would borrow and the exact key lengths.
# This replaces all guesswork: whichever (salt,length) makes crypt() return
# "*" is the trigger, because that is what collides with deploy's "*" field.
#   usage: ./probe.sh [container_name]
set -euo pipefail
NAME="${1:-sshhole-lab}"

docker exec -i "$NAME" sh <<'INNER'
set -e
apk add --no-cache build-base >/dev/null 2>&1 || true
cat > /tmp/probe.c <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <crypt.h>

static void t(int n, const char *salt){
    char key[4096];
    if (n > 4094) n = 4094;
    memset(key, 'A', n); key[n] = 0;
    char *r = crypt(key, salt);
    printf("  %4d A | \"%-28s\" -> %s\n", n, salt, r ? r : "(NULL)");
}
int main(void){
    const char *salts[] = {
        "$6$CvhFSGk3AHl4k36J",            /* valid sha512 salt ($6$ borrow acct) */
        "$6$abc",                         /* short sha512 salt                   */
        "$2y$05",                         /* TRUNCATED bcrypt (pick_salt mangle) */
        "$2y$05$NiolY0k0NShKjUezZdrZku",  /* fuller bcrypt setting               */
        "xx",                             /* DES fallback salt                   */
        "*",                              /* the target field itself             */
    };
    for (unsigned i = 0; i < sizeof(salts)/sizeof(*salts); i++){
        int lens[] = {10, 256, 257, 300, 1024};
        for (unsigned j = 0; j < sizeof(lens)/sizeof(*lens); j++) t(lens[j], salts[i]);
        printf("\n");
    }
    return 0;
}
EOF
# musl keeps crypt() in libc; -lcrypt is harmless if present, so try both.
cc -O0 -o /tmp/probe /tmp/probe.c -lcrypt 2>/dev/null || cc -O0 -o /tmp/probe /tmp/probe.c
echo "=== musl crypt() return values (look for any row ending in  -> * ) ==="
/tmp/probe
echo "musl version: $(apk list --installed 2>/dev/null | grep -i '^musl-[0-9]' || true)"
INNER
