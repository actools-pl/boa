# Hetzner Cloud / Drupal 11: compatibility track

**Status: FORK-AWARE SOURCE PINNING IMPLEMENTED; Hetzner end-to-end installation not yet tested.**

This branch starts from BOA's free `5.x-lts` source. Its purpose is to make a **minimal, reviewable** change set for one Hetzner Cloud KVM VPS, installing BOA and then Drupal 11. The original `5.x-lts` and `5.x-dev` branches must remain unchanged. Do not use this branch for a production installation until the acceptance tests below pass on a disposable server.

## Detailed fork installation and required code changes

Read **[INSTALL_FROM_FORK.md](INSTALL_FROM_FORK.md)** before testing. It now contains a disposable-server install procedure based on `bootstrap.sh --prepare`, source pinning, original BOA component paths, and exact unverified acceptance criteria.

## Supported test target

- A *fresh* Hetzner **Cloud KVM** VPS, x86-64, with **Debian 13 (Trixie)**. BOA's `autoinit` converts Trixie to **Devuan Excalibur**; it does **not** continue running Debian.
- At least BOA's documented 4 GiB RAM and 2 CPUs; prefer 8 GiB RAM and 4 CPUs for initial testing.
- Root SSH access by a tested **ed25519 key**, plus verified access to the Hetzner web/rescue console. BOA may disable password SSH and modify network/boot settings.
- Public IPv4, correct permanent FQDN, working wildcard A record, and inbound 22/80/443. IPv6 is not currently supported by upstream BOA.
- Outbound 53/80/443. **Outgoing TCP/25 may be blocked**; SMTP delivery will be handled separately using an authenticated external service on TCP/587.

**Do not run BOA on a VPS with existing websites, databases, or important data. Snapshot the disposable VPS before conversion, and verify rescue-console access.**

## Read-only preflight

Run on the *target* fresh Debian VM, from a checkout of this working branch:

```bash
git clone --branch hetzner-drupal11 https://github.com/actools-pl/boa.git
bash boa/hetzner/preflight.sh server.example.com
# Optional: test TCP reachability to an SMTP submission provider on port 587
bash boa/hetzner/preflight.sh server.example.com smtp.example.net
```

This checker makes **no changes** to the server. It checks prerequisites but **cannot** prove that the Debian-to-Devuan conversion will preserve networking or that BOA will install successfully.

## Required installer behaviour

1. Continue using the **LTS** edition only. Do not change source files in `5.x-lts`.
2. Start from Debian 13. Upstream BOA selects **Percona 8.4** on Devuan Excalibur, which meets BOA's requirement for Drupal 11.
3. Use the documented `nodns` argument to *skip BOA's initial DNS/SMTP tests* if port 25 is blocked. This does **not** repair DNS or send any messages.
4. Set up authenticated SMTP via an external provider on port 587. Upstream `_SMTP_RELAY_HOST` alone supports a simple **unauthenticated** relay, not SMTP AUTH; do not embed mail credentials in the public repository.
5. Do not depend on welcome mail to obtain access. With root SSH and a completed Octopus installation, check `/data/disk/o1/log/setupmail.txt` (sensitive; local only), or generate an Ægir one-time admin login URL:
   `su -s /bin/bash o1 -c "drush @hm uli"`
6. Do **not** reboot during BOA's chained installation or unfinished post-install updates. Follow the upstream completion check (`boa info | grep -c Percona` should report **3** lines) before the final reboot.

## Fork-aware source and update paths: implemented, awaiting live test

**Cloning this branch alone does not select it as BOA's installation source.** First run `hetzner/bootstrap.sh --prepare` to create a verified root-owned pin; then run `/opt/boa-fork/source/BOA.sh.txt`. This is a **test candidate** and has not been verified on Hetzner.

The implemented source-selection changes must now be verified to:

- Select `https://github.com/actools-pl/boa.git` at branch `hetzner-drupal11` for the BOA source tree, **without** diverting Debian/Devuan package archives or third-party dependencies.
- Make fork selection explicit, testable, and fail-closed (no silent fall-back to a different BOA tree).
- Ensure the initial installer, Barracuda upgrades, Octopus upgrades, and automatic refreshes don't overwrite Hetzner patches.
- Keep tracking upstream `5.x-lts` changes in reviewable commits, with shell syntax checks and a disposable-VPS installation test.

**Static tests have passed, but live installation has not.** Use the fork-aware test procedure below only on a disposable Hetzner Cloud instance. The official BOA command shown without the preparatory steps is not a fork install.

```bash
# Upstream BOA reference only, after host/domain checks and autoinit:
boa in-lts public server.example.com client@example.com o1 nodns
```

## Fork-based test-install candidate

On an empty, snapshotted Hetzner Debian 13 amd64 VPS with verified Rescue access and correct DNS, connect directly as root:

```bash
git clone --branch hetzner-drupal11 --single-branch https://github.com/actools-pl/boa.git
cd boa
bash hetzner/preflight.sh server.example.com
bash hetzner/bootstrap.sh --prepare
screen
bash /opt/boa-fork/source/BOA.sh.txt
boa in-lts public server.example.com client@example.com o1 nodns
```

This is an **unverified disposable-server procedure**. Running `bootstrap.sh` alone only stages a pinned copy and does not install BOA. SMTP authentication on port 587, real Drupal 11 provisioning, snapshot/restore and reboot verification remain to be tested. See [the full runbook](INSTALL_FROM_FORK.md) for non-negotiable safety steps. Do not use example domains or email addresses literally.

## Acceptance checklist (not yet completed)

- [ ] Preflight on a real Hetzner Debian 13 Cloud instance (report saved without secrets).
- [ ] Debian 13 -> Devuan Excalibur conversion; SSH + network survive.
- [ ] Root/administrator credentials can be recovered locally without external email.
- [ ] Port 25 remains blocked throughout; no installer deadlock.
- [ ] Fork-selected BOA sources used for initial install, Barracuda/Octopus updates, and maintenance.
- [ ] Percona 8.4, supported PHP, Nginx, Ægir and Octopus functioning.
- [ ] A real Drupal 11 site installed, verified, HTTPS enabled and backup/restore smoke-tested.
- [ ] Authenticated SMTP port 587 verified with an actual test message.
- [ ] Full BOA completion check passes **before** reboot; networking, sites, and admin access survive reboot.
- [ ] Negative/failure-path tests and source-identity verification; no secret or credential committed.

## Source documents

- Upstream [BOA installation documentation](https://github.com/omega8cc/boa/blob/5.x-lts/docs/INSTALL.md)
- Upstream [Drupal 11 platforms](https://github.com/omega8cc/boa/blob/5.x-lts/docs/PLATFORMS.md)
- Upstream [license/branch notes](https://github.com/omega8cc/boa/blob/5.x-lts/DUALLICENSE.md)

Do not merge this testing branch into `5.x-lts` or `5.x-dev` automatically.
