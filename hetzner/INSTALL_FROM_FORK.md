# Installing BOA / Drupal 11 on Hetzner Cloud from actools-pl/boa

**Version:** 2026-10-13 · **Repository:** https://github.com/actools-pl/boa · **Working branch:** `hetzner-drupal11` · **Base:** upstream free `5.x-lts`

> **STATUS: DESIGN / INSTALLATION HANDOVER — NOT INSTALL-READY.** The fork exists and the `hetzner-drupal11` branch contains `hetzner/preflight.sh` and `hetzner/README.md`. As of this note, no fork-aware bootstrap or update patches have been implemented, and no end-to-end installation on Hetzner has been demonstrated. Merely cloning the branch or executing its unmodified `BOA.sh.txt` **does not ensure the fork's code is installed**. Do not use it for production yet.

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

## 3. Commands that are safe to use NOW (checkout and read-only preflight)

From your workstation, inspect the branch:

~~~bash
git clone --branch hetzner-drupal11 --single-branch https://github.com/actools-pl/boa.git
cd boa
git status --short
git log -1 --oneline
cat hetzner/README.md
~~~

On a **fresh** Hetzner Debian 13 VM, after direct `root` login, use the existing read-only checker **without first installing Git or changing system packages**:

~~~bash
wget -q -O /root/boa-hetzner-preflight.sh \
  https://raw.githubusercontent.com/actools-pl/boa/hetzner-drupal11/hetzner/preflight.sh
less /root/boa-hetzner-preflight.sh
bash /root/boa-hetzner-preflight.sh server.example.com
# Optional: test only TCP reachability to a prospective submission relay
bash /root/boa-hetzner-preflight.sh server.example.com smtp.example.net
~~~

The preflight does not install BOA, configure SMTP, change firewall/networking, or convert Debian. A `PASS` result is necessary but not sufficient. It cannot verify that the Hetzner kernel/network survives the Debian-to-Devuan transition.

**STOP after preflight today.** There is **no verified install command that loads and retains this fork's modified sources yet**. Do not infer that `bash BOA.sh.txt` from a clone installs the GitHub branch; its code still contains mirror-based fetches.

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

## 5. Exactly what must be changed in actools-pl/boa

### P0 — a fork-aware, persistent BOA source identity (mandatory)

Implement a **root-owned, persistent source manifest**, for example `/root/.boa-source.conf` (mode 0600), with explicit **BOA repository** `https://github.com/actools-pl/boa.git`, source branch `hetzner-drupal11` and **pinned tested commit SHA**. This is a *design proposal*, **not an existing upstream file or implemented option**.

A fork bootstrap must use that manifest consistently across:
1. Initial `BOA.sh.txt` setup (including the Debian `autoinit` restart/resume sequence).
2. Barracuda/Octopus installer and settings fetches.
3. Source-tree staging in both Barracuda and Octopus phases.
4. Scheduled launcher/tool refreshes and manual `up-lts` upgrades.
5. Post-reboot operation and recovery.

Use an explicit **source identity** such as `BOA_SOURCE=fork`, separate from the **edition** `_tRee=lts`. Do not change edition to `dev` merely because our working Git branch has a custom name. On any missing source, missing ref, invalid archive/hash or unexpected upstream provenance, **fail closed** with a helpful error instead of silently replacing fork code with the official mirror release.

Prefer *pinning immutable Git commit SHAs for a test deployment* and promoting deliberately tested commits. Branch names alone can move between checks. Preserve HTTPS verification; do not execute unverified downloaded bytes or hardcode credentials.

### P0 — patch only the BOA loader/updater chain

Specific files/functions to inspect and patch narrowly:

| File / component | Why it needs inspection or change |
| --- | --- |
| `BOA.sh.txt` | Initial meta-bootstrap and `_update_boa_tools`/`_update_agents` fetch mirror-provided files. Must load/persist fork source across `autoinit` and update checks. |
| `aegir/tools/bin/boa` | Computes `_bRnh=5.x-lts` and `_rgUrl=https://files.boa.io/versions/lts/boa`, then fetches Barracuda/Octopus scripts and settings. Add fork-aware source resolution. |
| `aegir/tools/bin/barracuda` and `aegir/tools/bin/octopus` | On manual upgrades, select vendor `_rgUrl`, compare release stamps and refresh scripts. Must be consistent with the fork. |
| `BARRACUDA.sh.txt` and `OCTOPUS.sh.txt` | Entry scripts set GitHub defaults and source the settings/build tree. Maintain LTS semantics and dispatch selected BOA source. |
| `lib/settings/barracuda.sh.cnf` and `lib/settings/octopus.sh.cnf` | The `_download_helpers_libs` path defaults to `_DL_MODE=BATCH`; Git clone uses `_BRANCH_BOA` / `_BOA_REPO_GIT_URL`. Provide separate fork BOA-code selector and checksum/commit checks. |
| `lib/functions/dns.sh.inc::_check_git_repos` | In GIT mode it resets `_BOA_REPO_GIT_URL` to omega8cc GitHub/GitLab. Must not overwrite an approved fork override. |
| `aegir/tools/system/clear.sh`; `autoupboa`; cron/update paths | Scheduled self-updates fetch vendor `BOA.sh.txt` and launchers from mirrors, **even while several normal update options are off**. Must preserve fork source or stop safely. |
| `hetzner/` (new files) | Add a small reviewed installer/bootstrap wrapper, source-identity audit, and Hetzner network smoke tests. |

**Do not simply replace every occurrence of `files.boa.io` with `raw.githubusercontent.com`.** Vendor paths such as `versions/lts/boa/...` and `dev/lts/boa.tar.gz` do not match GitHub repository paths. The mirror also supplies packages and third-party artefacts we should continue consuming from its signed/verified upstream release surface.

**Prefer a distinct “BOA code from this fork” path while retaining `_DL_MODE=BATCH` for upstream Ægir packages.** Changing `_DL_MODE=GIT` globally also switches Hostmaster/Provision/Hosting staging to live omega8cc Git clones; it does **not** by itself select our GitHub branch. It may enlarge the patch unnecessarily.

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
- An *optional later patch* can add an idempotent, secret-free template/reapply hook so upgrades do not undo SMTP submission settings. Test an actual delivered email, not just an open TCP socket.
- Do not depend on email for initial access: use `drush @hm uli` from root and verify `setupmail.txt` privately. A failed/incomplete Octopus install may have neither.

### P1 — Drupal 11 platform install and production readiness

After BOA is installed and **Percona 8.4 is positively verified**, request a current Drupal 11 platform from the `o1` account. BOA's documented symbols presently include `DE4` for Drupal 11.4 and `CMS` for Drupal CMS. **Symbols are versioned; check `/data/disk/o1/static/control/README.txt` on the installed release.**

For a *new, disposable test instance* only, where replacing its default platform selection is acceptable:

~~~bash
su -s /bin/bash o1 -c 'printf "DE4\n" > ~/static/control/platforms.info'
su -s /bin/bash o1 -c 'touch ~/static/control/run-upgrade.pid'
~~~

`platforms.info` **replaces**, rather than extends, the selected platform list. If other platforms matter, preserve their symbols instead of writing `DE4` alone. After the platform builds and verifies, create a Drupal 11 site in Ægir and test login, a database write, cache/cron, TLS, backups and restoration.

**Important upstream qualification:** built-in Drupal 8+ platform builds are intended for demonstration/compatibility testing with best-effort security updates. For a **production** Drupal 11 website, build and maintain your **own Composer-managed platform under the tenant's `~/static`**, following BOA's “Adding your own platform” guidance, rather than relying on built-in testing platforms.

## 6. Planned fork installation flow (after P0 is implemented and reviewed)

The following is an **interface proposal, not an available command**:

~~~text
# NOT IMPLEMENTED — do not execute:
# hetzner/install.sh --fqdn server.example.com --email client@example.com
~~~

That script should:
1. Verify `root`, Debian 13 x86-64, correct FQDN and wildcard DNS, SSH key, root console access, free resources, IPv4/boot/network expectations and a recorded snapshot.
2. Verify the signed/hashed/pinned **actools-pl/boa source SHA**; create persistent fork source config and a root-only log without secrets.
3. Launch BOA's existing `in-lts public ... o1 nodns` path with an installer chain that always fetches its BOA components from the **pinned fork**. Let BOA's `autoinit` and its automatic reboots run without manually intervening.
4. Verify source identity again after `autoinit` and at each installer phase; refuse source drift.
5. Wait for BOA's normal three-pass completion gate before the final manual `boa reboot`.
6. Validate network, SSH, Nginx, database 8.4, PHP, Ægir/Octopus and an installed Drupal 11 site; verify the selected fork survives a manual upgrade and scheduled updater pass.
7. Configure SMTP AUTH 587 separately using locally supplied credentials and verify delivery.
8. Save a **redacted** test report and exit nonzero if any required step is not proven.

**Never turn this into an unattended “one-liner” before the conversion/rollback test passes.**

## 7. Acceptance tests / definition of done

- [ ] `hetzner/preflight.sh` succeeds on an actual clean Hetzner **Debian 13 amd64** VM; snapshot and recovery access confirmed.
- [ ] Vendor-control install (separate disposable VM) establishes what works with no fork patches.
- [ ] Debian -> Devuan Excalibur conversion completes, with root SSH, IPv4, DNS and boot surviving its reboots.
- [ ] Fork bootstrap uses the expected pinned `actools-pl/boa` commit during every phase, including post-conversion resumption.
- [ ] Barracuda/Octopus receive fork-selected BOA code while upstream Ægir bundled dependencies remain unmodified.
- [ ] Negative test: missing SHA/source or attempted fallback to the official BOA versioned path **fails closed**, no silent fork replacement.
- [ ] Source remains pinned after a manual `barracuda up-lts` / `octopus up-lts` and after scheduled self-update logic.
- [ ] Port 25 blocked; initial BOA installation completes with `nodns`; public DNS and ACME certs still work.
- [ ] Percona 8.4, supported PHP, Nginx, Ægir panel and a Drupal 11 site all work.
- [ ] Local welcome information/one-time admin link recovered without external email; no passwords or one-time links leaked.
- [ ] Authenticated SMTP submission on 587 delivers a message and survives maintenance.
- [ ] `boa info | grep -c Percona` reaches the documented fresh-install completion threshold before final reboot; all services survive reboot.
- [ ] Site backup + restore to a disposable replacement box is tested before declaring production-readiness.
- [ ] Lint (`bash -n`, ShellCheck where available), source-origin assertions and security review pass; only `hetzner-drupal11` is modified.

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

**Final position:** It is feasible to pursue a **small BOA fork diff**, but a truly fork-based installation is **not yet executable**. The hard requirement is source selection that survives installers, Debian conversion, upgrades and scheduled self-updates; test that before advertising a Hetzner installation command.
