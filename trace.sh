#!/usr/bin/env bash
# Trace exactly what sshd passes to crypt() and gets back during a real deploy
# login. An LD_PRELOAD shim wraps crypt(); a one-shot debug sshd on :2223 runs
# under it; we drive one password login as deploy from inside the container.
#   usage: ./trace.sh [container_name]
set -uo pipefail
NAME="${1:-sshhole-lab}"

docker exec -i "$NAME" sh <<'INNER'
set -e
apk add --no-cache build-base >/dev/null 2>&1 || true

# 1) crypt() logger (LD_PRELOAD)
cat > /tmp/cryptlog.c <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>
char *crypt(const char *key, const char *salt){
    static char *(*real)(const char*,const char*);
    if(!real) real = dlsym(RTLD_NEXT,"crypt");
    char *r = real(key,salt);
    fprintf(stderr,"[cryptlog] crypt(keylen=%zu, salt=\"%s\") = \"%s\"\n",
            strlen(key), salt, r?r:"(NULL)");
    fflush(stderr);
    return r;
}
EOF
cc -shared -fPIC -o /tmp/cryptlog.so /tmp/cryptlog.c -ldl 2>/dev/null \
  || cc -shared -fPIC -o /tmp/cryptlog.so /tmp/cryptlog.c

# 2) askpass that emits exactly 300 'A' (no newline)
cat > /tmp/ap.sh <<'EOF'
#!/bin/sh
awk 'BEGIN{for(i=0;i<300;i++)printf "A"}'
EOF
chmod +x /tmp/ap.sh

# 3) one-shot debug sshd on :2223, under the crypt logger
rm -f /tmp/sshd.log
LD_PRELOAD=/tmp/cryptlog.so /usr/sbin/sshd -ddd -e -p 2223 >/tmp/sshd.log 2>&1 &
SSHD_PID=$!
sleep 1

# 4) drive one password login as deploy, from inside the container
SSH_ASKPASS=/tmp/ap.sh SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
  ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -p 2223 deploy@localhost 'echo GOT_SHELL_AS_DEPLOY; id' 2>/tmp/ssh_client.log || true

sleep 1
kill "$SSHD_PID" 2>/dev/null || true

echo "===== crypt() calls sshd actually made (THE answer) ====="
grep '\[cryptlog\]' /tmp/sshd.log || echo "(none -- sshd rejected the account before ever hashing)"
echo
echo "===== sshd auth decision ====="
grep -Ei 'Accepted|Failed|authentic|invalid user|illegal|locked|expired|PAM' /tmp/sshd.log | tail -n 15
echo
echo "===== client side ====="
tail -n 3 /tmp/ssh_client.log
INNER
