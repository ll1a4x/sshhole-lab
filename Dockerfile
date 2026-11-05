# ============================================================================
#  *sshhole / CVE-2026-123158 — vulnerable lab
#  Password-auth bypass in sshd on musl libc without PAM.
#
#  Alpine's packaged openssh (9.6_p1-r3 on the 3.19 branch) carries the
#  backported fix, so we build UPSTREAM OpenSSH 9.6p1 from source instead.
#  That binary has the unpatched comparison, so crypt()'s "*" error marker
#  collides with a locked "*" account and authentication succeeds.
#
#  Mechanism:
#    - deploy's /etc/shadow field is "*" (locked / key-only, no password).
#    - On login, sshd finds no real hash for deploy, so pick_salt() borrows
#      another account's salt (alice) and calls crypt(password, salt).
#    - musl returns the string "*" on crypt failure: a $6$ salt fails for any
#      password > 256 bytes; a pick_salt-mangled bcrypt salt fails always.
#    - sshd compares "*" (crypt result) with "*" (deploy's field) -> match.
# ============================================================================
FROM alpine:3.19

RUN apk add --no-cache build-base openssl-dev zlib-dev linux-headers \
                       wget apache2-utils

WORKDIR /build
# Upstream 9.6p1 tarball. Mirror if the CDN is slow/blocked:
#   https://mirror.leaseweb.net/pub/OpenBSD/OpenSSH/portable/openssh-9.6p1.tar.gz
RUN wget -q https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.6p1.tar.gz \
 && tar xzf openssh-9.6p1.tar.gz

# Privilege-separation prerequisites: the 'sshd' user and a root-owned /var/empty.
# The base image may already ship an 'sshd' user, so creating it is best-effort.
RUN (id sshd >/dev/null 2>&1 || adduser -D -H -s /sbin/nologin sshd) \
 && mkdir -p /var/empty && chown root:root /var/empty && chmod 755 /var/empty

WORKDIR /build/openssh-9.6p1
# --without-pam is the crux: it forces the musl crypt() verification path.
RUN ./configure --prefix=/usr --sysconfdir=/etc/ssh --without-pam >/dev/null \
 && make -j"$(nproc)" >/dev/null \
 && make install >/dev/null
RUN ssh-keygen -A

# ---- Accounts --------------------------------------------------------------
# alice: a NORMAL account with a real password. sshd borrows her salt.
#        (bcrypt here; a $6$ sha512 account works identically.)
RUN adduser -D alice \
 && H="$(htpasswd -nbB x correcthorsebatterystaple | cut -d: -f2)" \
 && echo "alice:$H" | chpasswd -e

# deploy: the TARGET. shadow field forced to a bare "*" (locked, key-only).
RUN adduser -D deploy \
 && sed -i 's/^deploy:[^:]*:/deploy:*:/' /etc/shadow

# ---- sshd config (all Alpine defaults, pinned for clarity) -----------------
RUN printf '\nPasswordAuthentication yes\nPermitRootLogin no\n' >> /etc/ssh/sshd_config

COPY check.sh /check.sh
RUN chmod +x /check.sh

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
