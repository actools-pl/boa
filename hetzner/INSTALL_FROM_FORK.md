# Installing BOA / Drupal 11 on Hetzner Cloud from actools-pl/boa

**Version:** 2026-10-15 · **Repository:** https://github.com/actools-pl/boa · **Working branch:** `hetzner-drupal11` · **Base:** upstream free `5.x-lts`

> **STATUS: WORKING REPAIRED REFERENCE; CLEAN RERUN PENDING.** The operator's Hetzner reference converted Debian 13 to Devuan, survived reboot, hosted Drupal 11 and passed same-server restore and system/Drupal mail delivery tests. It was migrated to a Composer platform on Drupal 11.4.10. The source guards and later fixes have CI coverage, but a fresh install from the corrected branch, upgrade/relay persistence and replacement-server restore remain unproven. See [the dated acceptance record](ACCEPTANCE_2026-10-15.md). Fresh-installer use remains limited to an empty disposable VM with tested recovery access.

## 1. Objective and minimal-change principle

Install **BOA Barracuda + Octopus + Ægir** and a working **Drupal 11** site on a **fresh Hetzner Cloud KVM** server, with outgoing TCP/25 blocked, while keeping all project-specific BOA changes in `actools-pl/boa` rather than modifying the official repository.

Retain upstream BOA as far as possible. Specifically:

- Keep the BOA **LTS** edition, not the licence-gated DEV/PRO release trees.
- Keep BOA's existing Debian-to-Devuan `autoinit` conversion, rather than trying to run it on systemd/Debian after installation.
- Keep BOA's Nginx, PHP-FPM, Ægir, Octopus and Percona setup logic.
- Keep upstream's Ægir/Provision/Hostmaster forks and their BATCH packages unless an actual incompatibility is demonstrated; **forking BOA does not require forking all of them**.
- Change only how **BOA's own code** is sourced, pinned, verified and updated, plus small Hetzner-specific network and SMTP handling where necessary.
- Leave `5.x-lts` and `5.x-dev` unchanged; changes and tests go into `hetzner-drupal11`.

### Present capability versus required changes

| Requirement | Upstream BOA today | What our fork needs |
| --- | --- | --- |
| Debian 13 image | Converts Trixie to **Devuan Excalibur** | Hetzner-specific boot/network checks and recovery tests |
| Drupal 11 | Supported | Ensure **Percona 8.4**, supported PHP, enabled Drupal 11 platform |
| Hetzner blocks outbound TCP/25 | `nodns` bypasses initial DNS/SMTP checks | Configure authenticated SMTP submission on TCP/587 separately; keep real DNS working |
| Welcome email never arrives | Local welcome file and Drush one-time login | Document private recovery; perhaps automate nonsecret existence checks |
| Forked BOA source | `_DL_MODE=GIT` exists but defaults and release-branch pins target upstream | **Mandatory:** explicit source selector and branch/commit pin for BOA code |
| Installer wrappers | Download versioned pieces from `files.boa.io` | **Mandatory:** fork-aware bootstrap, wrappers and configuration payloads |
| Automatic updates | Periodically refresh BOA code and tools from official mirrors | **Mandatory:** persist fork identity and prevent overwrite or silent upstream fallback |
| Hetzner Cloud network | General KVM supported | Validate public IPv4, cloud-init/`hc-utils`, DHCP/default route, GRUB and reboots |

**Key conclusion:** Drupal 11 compatibility itself does not require a major BOA rewrite. **The source/update delivery chain is the difficult mandatory patch.** Hetzner boot survival must then be proven on a disposable VM.

## 2. Target server and safety conditions

Use **Hetzner Cloud**, not bare-metal Hetzner dedicated hardware, for the first test. A dedicated host would need a guest VM.

- Image: clean **Debian 13 (Trixie)** on **x86-64/amd64**. Exclude ARM/CAX from this acceptance target.
- Size: upstream minimum **4 GiB RAM / 2 vCPU**; choose **8 GiB / 4 vCPU** for the first trial. Prefer 40 GiB or more free/usable disk with backup headroom.
- Network: **public IPv4**, inbound TCP **22, 80, 443**; appropriate UDP 443 if using HTTP/3; outbound DNS/HTTP/HTTPS working. Provider-level SMTP port **25 and 465 remain blocked**; **587** is available for external authenticated SMTP.
- FQDN: e.g. `server.example.com`, with working public A records for `server.example.com` and `*.server.example.com` resolving to the assigned IPv4. A valid real domain is needed for public TLS. Do not substitute `example.com` literally.
- Recovery: load and test a **root ed25519 SSH public key** before starting, set a strong local root password with `passwd` for the Hetzner console, confirm that the Hetzner Console and Rescue System can be used, and take a **Hetzner Snapshot before conversion**.
- Start from a plain server. Follow upstream's rule **do not run apt upgrade, install another web/DB stack, or apply unrelated hardening** before BOA.
- Before conversion, save boot/network evidence: output of `ip -br a`, `ip -4 route`, `cat /etc/os-release`, `lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS`, and note whether `cloud-init` and `hc-utils` manage networking. Save to a root-only location, **not to GitHub**.
- Do **not** blindly remove cloud-init, rename interfaces, replace DHCP with a generic static recipe, or assume the boot disk is `/dev/sda`. Hetzner images and interface types vary.

Hetzner documents that private interfaces may be managed by cloud-init or `hc-utils`; BOA removes systemd as part of conversion. The correct network treatment must be based on the actual image. Do not try an unattended conversion on a machine without verified rescue access.

## 3. Read-only inspection and prerequisite checks

From your workstation, inspect the branch:

~~~bash
git clone --branch hetzner-drupal11 --single-branch https://github.com/actools-pl/boa.git
cd boa
git status --short
git log -1 --oneline
cat hetzner/README.md
~~~

On a **fresh** Hetzner Debian 13 VM, after direct `root` login, you can inspect the read-only checker before cloning:

~~~bash
wget -q -O /root/boa-hetzner-preflight.sh \
  https://raw.githubusercontent.com/actools-pl/boa/hetzner-drupal11/hetzner/preflight.sh
less /root/boa-hetzner-preflight.sh
bash /root/boa-hetzner-preflight.sh server.example.com
# Optional: test only TCP reachability to a prospective submission relay
bash /root/boa-hetzner-preflight.sh server.example.com smtp.example.net
~~~

The preflight does not install BOA, configure SMTP, change firewall/networking, or convert Debian. **It requires Git to be available for the pinned fork preparation; if Git is absent, first take a provider Snapshot, then explicitly install only Git on the disposable Debian VPS. This is an exception to the untouched stock BOA image recommendation that needs a live test.** A `PASS` result is necessary but not sufficient. It cannot verify that the Hetzner kernel/network survives the Debian-to-Devuan transition.

**Source selection is implemented and the reference pin/installed launchers were verified.** A fresh runtime test of the corrected branch remains required. Use `hetzner/bootstrap.sh --prepare` to pin the source before running the local BOA meta-installer. Downloading the official BOA installer directly from `files.boa.io` is a **different, upstream** installation and does not exercise our fork.

## 4. Reference: how standard upstream BOA is installed (NOT a fork install)

The following commands are useful as a **control experiment on a separate disposable Hetzner VM**, using *official* BOA, not `actools-pl/boa`. Read and follow [upstream BOA install guidance](https://docs.boa.io/self-hosting/install-boa) and make sure DNS, root SSH, console access and a snapshot are ready.

~~~bash
# Log in directly as root; use a screen session so a dropped SSH link is safe.
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
boa help
# On Debian 13 -> Devuan Excalibur, BOA selects Percona 8.4.
# 'nodns' is the ONE optional installer choice here and bypasses initial DNS/SMTP tests.
boa in-lts public server.example.com client@example.com o1 nodns
~~~

Do **not** assume the above command installs from our fork. BOA may automatically restart while running `autoinit` and resume the recorded command. After the visible Barracuda/Octopus phases, BOA also runs a background finishing phase. **Do not issue an extra/manual reboot during the chain.**

On a successful *fresh* install, upstream documents:

~~~bash
# Expect 3 on a fresh completed installation (more is possible after later upgrades).
boa info | grep -c Percona

# Run only after BOA's completion criterion is satisfied.
boa reboot

# Once the machine is back and SSH works:
cat /etc/os-release
su -s /bin/bash o1 -c "drush @hm uli"
~~~

The control panel should be `https://o1.server.example.com`. Run the one-time login command locally as root and **do not paste the resulting URL into public logs, tickets or GitHub**.

For an installation where email never arrived, `/data/disk/o1/log/setupmail.txt` is the locally saved welcome information on a completed instance, **if the setup created it**:

~~~bash
test -f /data/disk/o1/log/setupmail.txt && echo "Welcome information exists (sensitive)"
# Read privately as root, only if needed; do not upload or paste its contents.
~~~

If a run aborts during conversion, inspect `/root/.autoinit.log` and `/root/.autoinit-verbose.log`; if a BOA phase aborts, inspect corresponding Barracuda/Octopus logs. Do not rerun destructive recovery steps blindly. If networking or boot fails, use the pre-conversion Hetzner Snapshot / Rescue System.

## 5. Fork modifications implemented and requirements remaining

### P0 — a fork-aware, persistent BOA source identity (mandatory)

**Implemented; the reference pin/entrypoint comparisons passed:** `hetzner/bootstrap.sh --prepare` checks out the source into `/opt/boa-fork/source` and records its exact 40-character commit SHA in `/root/.boa-fork-source.sha`, root-owned and mode 0600. BOA entrypoints verify the SHA, repository origin and checkout cleanliness before modifying the host. The pinned source remains fixed until a separately reviewed promotion procedure updates it.

The fork loader is wired into these paths; the clean rerun and upgrade tests must establish the entire chain, beyond the working reference's entrypoint comparisons:
1. Initial `BOA.sh.txt` setup (including the Debian `autoinit` restart/resume sequence).
2. Barracuda/Octopus installer and settings fetches.
3. Source-tree staging in both Barracuda and Octopus phases.
4. Scheduled launcher/tool refreshes and manual `up-lts` upgrades.
5. Post-reboot operation and recovery.

The implementation uses **`BOA_FORK_MODE=YES`** as source identity, separate from the free-LTS **edition** `_tRee=lts`. Do not change edition to `dev` merely because our working Git branch has a custom name. On any missing source, missing ref, invalid archive/hash or unexpected upstream provenance, **fail closed** with a helpful error instead of silently replacing fork code with the official mirror release.

Prefer *pinning immutable Git commit SHAs for a test deployment* and promoting deliberately tested commits. Branch names alone can move between checks. Preserve HTTPS verification; do not execute unverified downloaded bytes or hardcode credentials.

### P0 — patch only the BOA loader/updater chain

The patched files and outstanding verification points are:

| File / component | Implemented change / remaining verification |
| --- | --- |
| `BOA.sh.txt` | Initial meta-bootstrap and `_update_boa_tools`/`_update_agents` fetch mirror-provided files. Must load/persist fork source across `autoinit` and update checks. |
| `aegir/tools/bin/boa` | Computes `_bRnh=5.x-lts` and `_rgUrl=https://files.boa.io/versions/lts/boa`, then fetches Barracuda/Octopus scripts and settings. Add fork-aware source resolution. |
| `aegir/tools/bin/barracuda` and `aegir/tools/bin/octopus` | On manual upgrades, select vendor `_rgUrl`, compare release stamps and refresh scripts. Must be consistent with the fork. |
| `BARRACUDA.sh.txt` and `OCTOPUS.sh.txt` | Entry scripts set GitHub defaults and source the settings/build tree. Maintain LTS semantics and dispatch selected BOA source. |
| `lib/settings/barracuda.sh.cnf` and `lib/settings/octopus.sh.cnf` | The `_download_helpers_libs` path defaults to `_DL_MODE=BATCH`; Git clone uses `_BRANCH_BOA` / `_BOA_REPO_GIT_URL`. Provide separate fork BOA-code selector and checksum/commit checks. |
| `lib/functions/dns.sh.inc::_check_git_repos` | Not modified: its GIT mirror detection is bypassed for pinned BOA code by the fork staging path; verify that future changes cannot override the pin. |
| `aegir/tools/system/clear.sh`; `autoupboa`; cron/update paths | Scheduled self-updates fetch vendor `BOA.sh.txt` and launchers from mirrors, **even while several normal update options are off**. Must preserve fork source or stop safely. |
| `hetzner/` (new files) | Add a small reviewed installer/bootstrap wrapper, source-identity audit, and Hetzner network smoke tests. |

**Do not simply replace every occurrence of `files.boa.io` with `raw.githubusercontent.com`.** Vendor paths such as `versions/lts/boa/...` and `dev/lts/boa.tar.gz` do not match GitHub repository paths. The mirror also supplies packages and third-party artefacts we should continue consuming from its signed/verified upstream release surface.

**Implemented: the separate pinned “BOA code from this fork” path retains `_DL_MODE=BATCH` for upstream Ægir packages.** Changing `_DL_MODE=GIT` globally also switches Hostmaster/Provision/Hosting staging to live omega8cc Git clones; it does **not** by itself select our GitHub branch. It may enlarge the patch unnecessarily.

### P0 — Hetzner conversion/boot checks (test before invasive patches)

`autoinit` already migrates Trixie to Devuan Excalibur. First test upstream on an expendable Hetzner image and capture:

- Whether `cloud-init` or `hc-utils` controls the NIC/default route and how that changes after systemd removal.
- Whether actual interface names, IPv4 DHCP, DNS and outbound 443 survive automatic conversion reboots.
- Which disk/EFI/GRUB layout is present and whether the machine boots again after BOA completion.
- Whether BOA's CSF firewall allows your management SSH address, and whether the Let's Encrypt HTTP-01 challenge reaches inbound TCP/80.
- Whether Hetzner Rescue can restore network/boot when the experiment fails.

Only if a specific failure is demonstrated, add a narrowly scoped and reversible Hetzner fix in the fork. **Never assume all Hetzner Cloud images need a GRUB, cloud-init, or network rewrite.**

### P0/P1 — blocked port 25, real mail delivery and password recovery

- `nodns` is already an upstream option, so **no blanket patch to disable all network validation** is needed. The real A records must still work; skipping a check is not a DNS workaround.
- For the Debian 13 / Devuan Excalibur track, BOA already forces **Percona 8.4**. This solves the single-optional-token conflict: choose `nodns` rather than `percona-8.4` and then independently verify the installed database version.
- Configure **Postfix SMTP AUTH on TCP/587** after BOA installation, with STARTTLS and appropriate CA validation. Use a supported external relay and keep credentials in local root-only files (e.g. `/etc/postfix/sasl_passwd`, 0600, plus protected map); never in public Git, shell command history, uploaded logs, or BOA welcome records.
- Upstream `_SMTP_RELAY_HOST` alone configures a simple **unauthenticated** relay; it does **not** replace the SMTP AUTH/TLS settings required by a normal port-587 provider.
- BOA's local-sendmail permission switch also clears Postfix's relayhost. Keep the authenticated system relay separate from Drupal's direct SMTP module configuration; see [SMTP_587.md](SMTP_587.md).
- An *optional later patch* can add an idempotent, secret-free template/reapply hook so upgrades do not undo SMTP submission settings. Test an actual delivered email, not just an open TCP socket.
- Do not depend on email for initial access: use `drush @hm uli` from root and verify `setupmail.txt` privately. A failed/incomplete Octopus install may have neither.

### P1 — Drupal 11 platform install and production readiness

After BOA is installed and **Percona 8.4 is positively verified**, request a current Drupal 11 platform from the `o1` account. BOA's documented symbols presently include `DE4` for Drupal 11.4 and `CMS` for Drupal CMS. **Symbols are versioned; check `/data/disk/o1/static/control/README.txt` on the installed release.**

For a *new, disposable test instance* only, where replacing its default platform selection is acceptable:

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

`platforms.info` **replaces**, rather than extends, the selected platform list. If other platforms matter, preserve their symbols instead of writing `DE4` alone. The root-only file installation above addresses the reference's control-directory ownership: `o1.ftp:o1`, mode `2755`. It preserves that directory's permissions. After the platform builds and verifies, create a Drupal 11 site in Ægir and test login, a database write, cache/cron, TLS, backups and restoration.

**Important upstream qualification:** built-in Drupal 8+ platform builds are intended for demonstration/compatibility testing with best-effort security updates. For a **production** Drupal 11 website, build and maintain your **own Composer-managed platform under the tenant's `~/static`**, following BOA's “Adding your own platform” guidance, rather than relying on built-in testing platforms.

The reference moved from the bundled 11.4.9 development platform to a custom
11.4.10 Composer platform with SMTP 1.4.0 and Drush 13.8.0. The build's initial
11.4.9 dependency audit found three core advisories; the fixed build's audit was
clean before platform registration. See the Composer build/migration steps in
[README.md](README.md) and check current supported releases for each new build.
The site-version verifier does not replace `composer audit`.

## 6. Two-phase fork installation candidate (DISPOSABLE HETZNER VM ONLY)

The pinned fork loader and BOA staging pass static GitHub Actions tests plus **root staging integration tests**. A repaired reference completed the Hetzner Debian/Devuan conversion; a clean installation of the corrected fork is still pending. Use the fresh installer **only** on an empty, snapshotted Debian 13 amd64 Hetzner Cloud VPS with verified SSH keys, Hetzner Console/Rescue and public IPv4/WILDCARD DNS matching the VM.

~~~bash
# Log in DIRECTLY as root. Do this only if Git is missing:
command -v git || { apt-get update && apt-get install -y --no-install-recommends git; }

git clone --branch hetzner-drupal11 --single-branch https://github.com/actools-pl/boa.git
cd boa

# This preflights, writes a root-only network snapshot, stages the full SHA pin,
# sets the hostname and installs the pinned BOA meta-tools. No OS conversion.
bash hetzner/install.sh prepare server.example.com --snapshot-and-rescue-confirmed

# New GNU screen session for BOA's destructive conversion + installation:
screen -S boa-install
bash /opt/boa-fork/source/hetzner/install.sh install \
  server.example.com client@example.com --snapshot-and-rescue-confirmed
~~~

The `install` phase invokes BOA's existing `in-lts public <fqdn> <client-email> o1 nodns` with the pinned fork source. It may automatically reboot during `autoinit` and resume the recorded command. **Do not manually reboot** until BOA's completion criterion passes, and never use placeholder domains/emails literally.

After BOA and Octopus finish and the final instructed reboot:

~~~bash
boa info | grep -c Percona
# Stack-only check returns 2 (incomplete) before a Drupal site is verified.
bash /opt/boa-fork/source/hetzner/verify-install.sh server.example.com
# Get an Ægir admin login without any outgoing email:
su -s /bin/bash o1 -c 'drush @hm uli'
~~~

For a **throwaway Drupal 11 platform** on the test server, BOA's keyword `DE4` requests its Drupal 11.4 platform set:

~~~bash
# As root; create only the requested control files, without changing the directory:
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

This replaces the account's default platform selection, so preserve other desired keywords if needed. After that platform is verified, create a **real Drupal 11 site** in Ægir and verify it using its actual Drush alias:

~~~bash
bash /opt/boa-fork/source/hetzner/verify-install.sh server.example.com @example.com
~~~

**Exit 0** means a complete stack and Drupal 11 site were verified; **exit 2** means the stack may be ready but no site alias was verified; **exit 1** reports a failed required check. For **production**, build and register your own Composer-managed Drupal 11 platform under `~/static/platforms`; upstream BOA's Drupal 8+ built-in platforms are demonstration/compatibility builds only.

Authenticating an external Postfix relay on outbound TCP/587 is a **separate post-install operation**. See [SMTP_587.md](SMTP_587.md). Installation with `nodns` works without an email to recover the admin password, provided root SSH works and Octopus installation succeeds.

The completed code modifications are intended to:
1. Verify a root-owned, clean, commit-pinned checkout of `actools-pl/boa` and refuse source drift.
2. Load the BOA code tree from that pin, leaving external package and Ægir dependency downloads upstream.
3. Use pinned code for BOA wrappers, installer settings, static tools and the scheduled `clear.sh` self-update.
4. Refuse missing/unsafe fork files instead of silently falling back to the official BOA code.
5. Preserve the original BOA free-LTS branch semantics and existing Drupal 11/Percona 8.4 implementation.

**Still not demonstrated:** a repair-free clean install from the corrected branch, an operator-safe repin/rollback workflow, full runtime upgrade/source-refresh coverage, authenticated relay persistence through maintenance, and replacement-server restore. Never edit the pin file in place while BOA is running.

## 7. Acceptance tests / definition of done

- [x] Pinned BOA code-source hooks and static GitHub Actions source-safety tests implemented.
- [x] Reference setup completed after SSH-key/DNS corrections, with snapshot and recovery access confirmed by the operator.
- [x] Reference Debian -> Devuan Excalibur conversion completed; root SSH, IPv4, DNS and boot survived reboot.
- [x] Reference source pin and installed boa/barracuda/octopus/autoinit comparisons passed.
- [x] Reference reached three Percona completion lines; Percona 8.4.11-11, PHP 8.4.26, Nginx, panel and Drupal bootstrap worked.
- [x] Private local initial access recovery, HTTPS enforcement, content, image derivatives and anonymous access checks passed.
- [x] Reference cron ran with Drupal's page-triggered cron disabled and Aegir's hourly schedule configured.
- [x] Full site backup and same-server restore preserved original content/files and removed a temporary edit.
- [x] Reference reboot survival passed before SMTP setup and the final platform migration.
- [x] Authenticated system SMTP on 587 delivered mail; the queue emptied. Drupal SMTP test mail and password reset also worked.
- [x] Custom Composer platform build/audit and migration to Drupal 11.4.10 passed; post-migration full backup was green.

The checked runtime items above apply to the repaired reference, not a clean run
of every correction now on this branch. Detailed evidence and limits are in
[ACCEPTANCE_2026-10-15.md](ACCEPTANCE_2026-10-15.md).

- [ ] Corrected JSON site-version probe passes against the actual reference runtime; standalone post-mail-change site Verify is confirmed.
- [ ] Corrected fork completes a clean Hetzner Debian 13 install without manual directory/DNS repairs.
- [ ] Fork source identity is observed across every fresh-install/resumption and upgrade stage while bundled upstream dependencies retain their intended provenance.
- [ ] Source remains pinned after manual BOA upgrades and scheduled source refresh; actual-runtime negative/fallback tests fail closed. Offline CI coverage already exists.
- [ ] Authenticated SMTP submission survives BOA maintenance and reboot.
- [ ] An operator-safe pin promotion/rollback procedure is demonstrated.
- [ ] Custom platform code and full site backup restore onto a disposable replacement box.
- [ ] Separate vendor-control install and wider boot/network/ACME/source fault-injection tests are completed.
- [ ] Applicable lint, source assertions and security review pass for the final promotion candidate; `5.x-lts` and `5.x-dev` remain untouched.

## 8. Recommended implementation sequence

1. **H01 — Source mapping inventory:** document all mirror/site/fork fetch paths including `BOA.sh.txt`, `clear.sh` and `dns.sh.inc`; create a test that detects unreviewed official BOA-code fetches.
2. **H02 — Fork bootstrap and update source pin:** implement persistent manifest, fork-aware wrappers and fail-closed provenance verification. Keep upstream dependencies.
3. **H03 — Hetzner VM baseline:** run the existing preflight and a separate upstream-control test; change OS/network code only on demonstrated failures.
4. **H04 — Real fork install:** provision a clean Debian 13 image; exercise the new fork-aware bootstrap, BOA + Drupal 11 verification, SMTP 587 and reboot.
5. **H05 — Adversarial retest:** missing source, broken network after Devuan conversion, dropped SSH, broken ACME, changed fork SHA, Cron/SKYNET overwrite attempt, recovery and restore.
6. **H06 — Review then promote:** keep `5.x-lts` untouched; PR the changes for review against `hetzner-drupal11` and preserve a tested commit reference for each installation.

## 9. Authoritative source references

- Fork: https://github.com/actools-pl/boa/tree/hetzner-drupal11
- Preflight and initial boundaries: https://github.com/actools-pl/boa/tree/hetzner-drupal11/hetzner
- BOA upstream installation: https://docs.boa.io/self-hosting/install-boa
- BOA upstream preparation: https://docs.boa.io/self-hosting/before-you-install
- BOA developer architecture: https://docs.boa.io/developing/overview/architecture
- BOA fork/GIT/BATCH model: https://docs.boa.io/developing/overview/fork-model
- BOA release update pipeline: https://docs.boa.io/developing/release-model/serial-pipeline
- BOA platform keywords: https://docs.boa.io/operating/control-files-ini/octopus-cnf
- BOA platform production caveat: https://docs.boa.io/using/sites-and-platforms/platforms
- Hetzner SMTP port restrictions: https://docs.hetzner.com/cloud/servers/faq/
- Hetzner network configuration: https://docs.hetzner.com/networking/networks/server-configuration/
- Hetzner Snapshots: https://docs.hetzner.com/cloud/servers/backups-snapshots/overview/

**Final position:** The repaired reference demonstrates a functioning BOA/Drupal stack, reboot survival, same-server restore and real email delivery. It does not establish that the corrected fresh installer needs no repairs, that upgrades preserve the source/relay, or that a replacement server can restore the site. Complete those remaining gates before claiming production readiness.
