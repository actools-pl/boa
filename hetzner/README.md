# Hetzner Cloud BOA LTS / Drupal 11 installer

**State: a repaired Hetzner reference installation passed operational tests; a clean install from the corrected fork is still pending.** The reference converted Debian 13 to Devuan, survived reboot, hosted Drupal 11, completed same-server backup/restore, and delivered system and Drupal mail. It later migrated to a Composer platform on Drupal 11.4.10. This does not prove a repair-free install, upgrade/relay persistence or replacement-server recovery. See the dated [acceptance record](ACCEPTANCE_2026-10-15.md). Run the fresh installer only on a disposable empty VM.

Repository: [actools-pl/boa](https://github.com/actools-pl/boa) · branch: `hetzner-drupal11` (based on free upstream `5.x-lts`).

## Same-server clean rerun

The operator will reuse the reference VPS at night because no spare box is
available. This means a recovery snapshot and verified off-server copies must
preserve the working reference before a manual Debian 13 rebuild. See the
[same-server reinstall plan](SAME_SERVER_REINSTALL.md). Run the fresh installer
only after the VPS has a clean Debian image; it is not an in-place upgrade of
the working BOA installation.

## Target and prerequisites

1. A disposable, freshly provisioned **Hetzner Cloud KVM x86-64 Debian 13 (Trixie)** VPS (not Ubuntu, not ARM, not a dedicated bare-metal host); 8 GiB RAM and 4 CPUs are preferred for the first trial.
2. A **provider Snapshot**, and independently tested Hetzner Console/Rescue access. Set a root console password and test an ed25519 **SSH key** before running BOA. Nothing in this script verifies your Snapshot or Rescue access; the confirmation flag is your explicit acknowledgement.
3. Public IPv4 attached to the VM; valid DNS **A records** for both `server.example.com` and `*.server.example.com` pointed **directly** to that IPv4. Cloudflare proxy/CDN should be disabled for the first test. Inbound TCP 22, 80 and 443 must be allowed; outbound DNS/HTTP/HTTPS must work.
4. Direct `root` shell. BOA will **convert Debian 13 to Devuan Excalibur** and use **Percona 8.4** (needed by Drupal 11). BOA cannot be kept running on Debian/systemd.
5. Git, curl, wget and SSH networking. The fork pins a real Git checkout, unlike the stock installer. If `git` is absent, it must be installed explicitly on the *disposable/snapshotted* Debian VM. This is a deliberate exception to BOA's stock 'untouched image' guidance and itself needs real-VM validation. Do **not** run a general `apt upgrade` before BOA.

Outgoing TCP ports 25 and 465 may remain blocked by Hetzner. The installer chooses BOA's upstream `nodns` option to bypass **initial** mail/DNS checks; that does **not** enable outbound email or replace working public DNS. Configure an authenticated external SMTP provider over 587 after installing BOA.

## Debian /etc/hosts versus public DNS

A clean Debian 13 image may contain `127.0.1.1 server.example.com server` in `/etc/hosts` because cloud-init maintains the machine's local hostname. This is normal and **does not prove the public A record is incorrect**. The preflight explicitly queries the `dns` NSS service (`getent -s dns ahostsv4`) so the local hostname entry cannot shadow published DNS. **Do not modify /etc/hosts or cloud-init merely to satisfy this preflight.**

To check published resolver answers without the local hosts entry, run:

```bash
getent -s dns ahostsv4 server.example.com | awk '{print $1}' | sort -u
getent -s dns ahostsv4 boa-preflight-check.server.example.com | awk '{print $1}' | sort -u
```

Both must include the IPv4 actually assigned to the VPS. If the direct hostname's DNS answer is different, correct its **public DNS A record** at the domain provider; retain the working wildcard.

## Commands: prepare, install, verify

Replace **every** example hostname/email/site domain with your real values. Run directly as root, on an empty snapshotted VM.

### Phase A — prepare the pinned source and BOA tools

~~~bash
# Only if Git is not already installed on the disposable Debian VPS:
command -v git || { apt-get update && apt-get install -y --no-install-recommends git; }

git clone --branch hetzner-drupal11 --single-branch https://github.com/actools-pl/boa.git
cd boa

# This runs preflight, pins the exact fork commit, records root-only network
# recovery facts, sets the FQDN and installs the pinned BOA meta-tools.
bash hetzner/install.sh prepare server.example.com --snapshot-and-rescue-confirmed
~~~

This **does not** perform the Debian-to-Devuan conversion. Fix all preflight failures. The preparatory Git checkout remains under `/opt/boa-fork/source` and its exact SHA is recorded in `/root/.boa-fork-source.sha` (0600). Do not edit either in place. A root-only pre-conversion record is saved in `/root/.boa-hetzner-network-before.txt`.

### Phase B — launch the actual BOA installation

~~~bash
screen -S boa-install

# Now INSIDE GNU screen:
bash /opt/boa-fork/source/hetzner/install.sh install \
  server.example.com client@example.com --snapshot-and-rescue-confirmed
~~~

This runs the **fork's** pinned `boa in-lts public server.example.com client@example.com o1 nodns`. BOA may reboot by itself and resume from its recorded command. Check `/root/.autoinit.log` after Debian conversion and Barracuda/Octopus logs on failure; do not interrupt a running install. **Do not manually reboot** until all BOA phases finish.

Supply your actual monitored client/recipient address in place of `client@example.com`. This recipient is separate from the mailbox that will authenticate to an SMTP provider. The reference install needed a later placeholder-address correction.

### If non-root BOA tasks cannot execute `/bin/sh`

A Hetzner installer-wrapper bug was discovered on the first live installation: the wrapper used a private root `umask 077` and passed that into BOA's `mkdir -p /opt/local/bin`. It created both `/opt/local` and `/opt/local/bin` as root-owned `0700` directories. Although `/opt/local/bin/websh` itself was `0755`, the `o1` user could not traverse its parents; `/bin/sh` (a symlink to websh) returned permission denied, PHP `exec()` returned `-1`, and Ægir tasks remained queued despite working Percona credentials.

The wrapper now runs the **BOA install child** with `umask 022` while retaining its root-private source checkout and pin. For a server prepared with an earlier commit, do not change the pinned source or swap `/bin/sh`; restore traversal on **only** these two directories as root:

~~~bash
chmod 0711 /opt/local /opt/local/bin
su -s /bin/bash - o1 -c '/bin/sh -c "/bin/echo SHELL_OK"'
su -s /bin/bash - o1 -c 'php -r '\''exec("/bin/echo PHP_OK", $o, $rc); echo "exit=$rc\\n";'\'''
~~~

The mode `0711` allows directory traversal but **not listing or modification** by non-root users; no recursive permissions or symlink changes. Once the shell works, test `drush8 @hm sqlq "SELECT 1"`, then let the existing task queue process its queued items. Never reset queued task statuses or rerun a site installation blindly.

### Phase C — complete setup and verify

After all BOA passes report completion (fresh installs normally report **3** for `boa info | grep -c Percona`), reboot once as BOA directs, reconnect as root, then:

~~~bash
boa info | grep -c Percona

# BOA stack-only check: returns 2 because no Drupal site alias supplied yet.
bash /opt/boa-fork/source/hetzner/verify-install.sh server.example.com

# Recover the Ægir administrator login locally, without email:
su -s /bin/bash o1 -c 'drush @hm uli'
~~~

The Ægir control panel should be `https://o1.server.example.com`. **Do not publish the one-time login URL**. The sensitive on-server welcome information may exist at `/data/disk/o1/log/setupmail.txt`; inspect it privately as root only if needed.

## Install an actual Drupal 11 site

For an initial **throwaway compatibility test**, BOA's built-in `DE4` keyword provisions its Drupal 11.4 platform set. The reference control directory was owned by `o1.ftp:o1` with mode `2755`, so writing these files as `o1` failed. Install only the requested files as root; do not widen the directory permissions:

~~~bash
(
  set -e
  umask 077
  boa_platform_request="$(mktemp)"
  trap 'rm -f "$boa_platform_request"' EXIT
  printf 'DE4\n' > "$boa_platform_request"
  install -o o1.ftp -g o1 -m 0644 "$boa_platform_request" /data/disk/o1/static/control/platforms.info
  install -o o1.ftp -g o1 -m 0644 /dev/null /data/disk/o1/static/control/run-upgrade.pid
)
~~~

The control file **replaces** the default platform selection; keep other desired keywords if this is not a throwaway instance. Monitor the Octopus upgrade/Verify queue in Ægir. Create a site in Ægir using the verified Drupal 11 platform, then verify its version with the **actual site alias** (list aliases using BOA's Drush tools):

~~~bash
bash /opt/boa-fork/source/hetzner/verify-install.sh \
  server.example.com @example.com
~~~

**Exit code 0 requires the alias to report Drupal 11** and all required stack checks to pass. Exit code 2 means BOA was checked but a Drupal site was not verified; exit 1 means a required check failed.

For **production Drupal 11**, do not depend on BOA's bundled Drupal 8+ demonstration platforms: build your own versioned, Composer-managed Drupal 11 project under `~/static/platforms/`, register it via Ægir **Platforms → Add platform**, and deploy sites on that. See [BOA's deploying-code guide](https://docs.boa.io/cheat-sheets/deploying-code).

### Composer platform and module workflow

Run Composer in the `o1.ftp` account shell, before registering the platform. The
reference used Composer 2.10.3, PHP 8.4.26, SMTP 1.4.0 and Drush 13.8.0. Choose a
currently supported Drupal release and audit its dependencies. As of the dated
reference test, Drupal 11.4.9 failed the security audit and 11.4.10 fixed the
three reported core advisories.

~~~bash
# From the root shell, enter the account's actual BOA limited shell:
su - o1.ftp
# Then run these individually; stop if a build/check fails:
composer --version
mkdir -p ~/static/platforms
cd ~/static/platforms
composer create-project drupal/recommended-project:11.4.10 site-d11-smtp-01 --no-interaction --no-dev
cd site-d11-smtp-01
composer require 'drupal/smtp:^1.4' 'drush/drush:^13' --no-interaction
composer install --no-dev --optimize-autoloader --no-interaction
composer validate --no-check-publish
composer check-platform-reqs --no-dev
composer audit --no-dev
composer show --direct
~~~

Once the checks pass, register the codebase in Aegir with the full path
`/data/disk/o1/static/platforms/site-d11-smtp-01/web`. Confirm the saved
**Publish Path** before running Verify: `/platforms/site-d11-smtp-01/web` alone
is the wrong absolute path. Leave the makefile field empty.

Add all modules/themes the site needs before registration. After platform Verify
passes, take a full site-files/classic-mysqldump backup, confirm no database updates
are pending, then use Migrate Site to select the new platform under the same site
domain. Check the version, content, uploaded files and login after migration.
For production, rehearse the move on a clone first. Build a fresh platform for
later code changes rather than running Composer against one serving sites.

Aegir's site Backup does not include this shared platform code. Preserve the
project manifest, lock and any custom code, or a protected copy of the completed
build, as well as the site archive before attempting replacement-server recovery.

## Outbound email and maintenance

Hetzner normally blocks outbound TCP/25 and TCP/465, not TCP/587. `nodns` permits BOA installation without emailing the initial password. To send actual system/Drupal messages, use an external **authenticated submission relay** with STARTTLS over 587. Do not place SMTP passwords, token URLs, or welcome-mail contents in Git or CI logs.

Postfix relay configuration handles backend/system mail. BOA restricts hosted
sites' local sendmail by default, so Drupal also needs a site SMTP module/provider
configuration. Enabling BOA's local-sendmail control can clear Postfix's relayhost;
it is not the way to connect the two paths. See [SMTP_587.md](SMTP_587.md).

The source pin is deliberately not self-advancing. Do **not** run stock `wget https://files.boa.io/BOA.sh.txt | bash` over your pinned fork; do **not** assume an upstream BOA upgrade preserves the pin without verification. A safe reviewed repin/rollback procedure and actual upgrade acceptance tests remain necessary before production use.

## Further reference and tests

- [INSTALL_FROM_FORK.md](INSTALL_FROM_FORK.md) — architecture, source/update patches, risks, test gates and troubleshooting.
- [preflight.sh](preflight.sh) — read-only host/DNS checks.
- [install.sh](install.sh) — guarded two-phase installer (clean rerun from the corrected fork pending).
- [verify-install.sh](verify-install.sh) — read-only BOA and Drupal version checks.
- [tests](tests/) — CI syntax, source mapping, first-install/replacement staging, pin drift refusal.
- [SMTP submission guide](SMTP_587.md) — optional post-install delivery setup.
- [Reference acceptance record](ACCEPTANCE_2026-10-15.md) — operator-reported passes, live repairs and remaining gates.
- [Upstream BOA installation guide](https://docs.boa.io/self-hosting/install-boa).

Keep `5.x-lts` and `5.x-dev` untouched. Complete the clean-install, upgrade/relay
persistence and replacement-restore gates before promoting this test candidate.
