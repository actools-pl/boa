# Hetzner Cloud email via authenticated SMTP on TCP/587

**Post-install only.** Hetzner ordinarily blocks outbound TCP/25 and TCP/465;
TCP/587 supports external SMTP submission. BOA's `nodns` bypasses installation
checks, but does not configure delivery.

The reference test delivered both a queued Octopus report through Postfix and
Drupal test/password-reset mail through the SMTP module. These are two delivery
paths. Relay persistence through BOA maintenance/reboot is still an acceptance
gate; see [the dated record](ACCEPTANCE_2026-10-15.md).

## BOA controls and the two mail paths

- Postfix submission handles backend/system mail.
- BOA restricts hosted sites' local `/usr/sbin/sendmail` by default. A working
  root Postfix test therefore does not prove Drupal mail works.
- `_SMTP_RELAY_HOST` alone selects an unauthenticated relay; it carries no
  SMTP credentials. Leave it empty for the manually configured authenticated
  setup below.
- Setting `_ALLOW_SENDMAIL=YES` or creating
  `/etc/boa/.allow.sendmail.cnf` reopens local sendmail for hosted sites and
  BOA's SMTP check clears Postfix's relayhost. Do not enable that switch to
  connect Drupal to this authenticated system relay.
- Configure Drupal's SMTP module directly against the provider. This bypasses
  local sendmail and does not require changing BOA's mail permission controls.

See [BOA's mailing controls](https://docs.boa.io/operating/security/mailing-policy).

## Prerequisites for the system relay

1. Finish BOA installation; verify Postfix, CA certificates, a Postfix hash map
   backend and an SMTP client SASL mechanism are available. The reference used
   `libsasl2-modules`, `ca-certificates`, `postconf -m` and `postconf -A`.
2. Obtain the provider's SMTP host, full mailbox username and mailbox password
   privately. Configure SPF/DKIM/DMARC as the provider instructs.
3. Review `mailq` privately. If existing messages are queued, hold the identified
   messages you intend to deliver with `postsuper -h QUEUE_ID` before activating
   the relay. Do not release unrelated mail without reviewing it.
4. Check for existing sender/credential mappings before changing them. The
   example refuses an existing mapping rather than overwriting it.
5. Confirm trusted STARTTLS and hostname validation. For the tested Hostinger
   native-email service:

~~~bash
timeout 20 openssl s_client -starttls smtp -connect smtp.hostinger.com:587 -servername smtp.hostinger.com -verify_hostname smtp.hostinger.com -verify_return_error -CAfile /etc/ssl/certs/ca-certificates.crt -brief </dev/null
~~~

Proceed only when verification succeeds. This checks TLS, not mailbox
authentication or actual delivery.

## Hostinger system relay example

Run as root in a private terminal. This targets the exact local system sender
`root@<server-fqdn>` and a mailbox you supply interactively. Confirm that sender
matches your queued report before using it. Other providers need their own
verified host/certificate and sender policies.

The subshell contains the private umask and credentials. The root-only backup
also protects any existing credential maps. The password/hash files are
protected plaintext credentials, not encrypted storage.

~~~bash
(
  set +x
  set -e
  if test -e /etc/boa/.allow.sendmail.cnf ||
     grep -Eq '^_ALLOW_SENDMAIL=.*YES' /root/.barracuda.cnf ||
     grep -Eq '^_SMTP_RELAY_HOST="[^"]+"' /root/.barracuda.cnf; then
    echo "STOP: review BOA mail controls before configuring this relay."
    exit 1
  fi
  for smtp_parameter in sender_canonical_maps smtp_generic_maps smtp_sasl_password_maps; do
    smtp_existing="$(postconf -h "$smtp_parameter")"
    if test -n "$smtp_existing"; then
      echo "STOP: existing $smtp_parameter needs operator review."
      exit 1
    fi
  done

  umask 077
  smtp_backup="/root/postfix-before-hostinger-$(date -u +%Y%m%d-%H%M%S)"
  mkdir -m 0700 "$smtp_backup"
  cp -a /etc/postfix/main.cf "$smtp_backup/main.cf"
  for smtp_file in hostinger_sasl hostinger_sasl.db hostinger_sender hostinger_sender.db; do
    if test -f "/etc/postfix/$smtp_file"; then
      cp -a "/etc/postfix/$smtp_file" "$smtp_backup/"
    fi
  done
  echo "Backup: $smtp_backup"

  read -r -p 'Full Hostinger sending mailbox: ' smtp_mailbox </dev/tty
  [[ "$smtp_mailbox" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
  read -r -s -p 'Mailbox password: ' smtp_password </dev/tty
  printf '\n'
  test -n "$smtp_password"
  printf '[smtp.hostinger.com]:587 %s:%s\n' "$smtp_mailbox" "$smtp_password" > /etc/postfix/hostinger_sasl
  unset smtp_password
  postmap hash:/etc/postfix/hostinger_sasl
  chown root:root /etc/postfix/hostinger_sasl /etc/postfix/hostinger_sasl.db
  chmod 0600 /etc/postfix/hostinger_sasl /etc/postfix/hostinger_sasl.db

  umask 022
  printf 'root@%s %s\n' "$(hostname -f)" "$smtp_mailbox" > /etc/postfix/hostinger_sender
  postmap hash:/etc/postfix/hostinger_sender
  chmod 0644 /etc/postfix/hostinger_sender /etc/postfix/hostinger_sender.db
  postconf -e \
    'relayhost = [smtp.hostinger.com]:587' \
    'smtp_sasl_auth_enable = yes' \
    'smtp_sasl_password_maps = hash:/etc/postfix/hostinger_sasl' \
    'smtp_sasl_security_options = noanonymous' \
    'smtp_sasl_tls_security_options = noanonymous' \
    'smtp_tls_wrappermode = no' \
    'smtp_tls_security_level = secure' \
    'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt' \
    'smtp_tls_secure_cert_match = nexthop' \
    'smtp_tls_servername = smtp.hostinger.com' \
    'smtp_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1' \
    'sender_canonical_maps = hash:/etc/postfix/hostinger_sender' \
    'sender_canonical_classes = envelope_sender, header_sender'
  if ! postfix check; then
    cp -a "$smtp_backup/main.cf" /etc/postfix/main.cf
    echo "STOP: Postfix check failed; original main.cf restored."
    exit 1
  fi
  postfix reload
  postconf relayhost smtp_sasl_auth_enable smtp_tls_security_level sender_canonical_maps
)
~~~

The sender map rewrites only the specified system identity to the authenticated
mailbox. It does not rewrite recipient addresses or every tenant's sender.
Postfix's `secure` policy requires a trusted certificate and hostname match;
do not disable verification to make delivery work.

### Delivery check and held queue

After setup, requeue the reviewed held message with `postsuper -r QUEUE_ID`.
Requeue processes it through cleanup again, applying the new sender mapping.
Merely releasing it with `postsuper -H` does not provide that reprocessing.

Verify the message arrives in the intended inbox with the authenticated mailbox
as sender, then check `mailq`. Inspect the relevant queue's error/log lines on
failure; never print the SASL map or query its password value into a log.

## Drupal SMTP configuration and test

Add `drupal/smtp:^1.4` with Composer while assembling a **new** platform, before
registration. If the current platform lacks the module, build and migrate to
another platform; do not modify a platform serving sites in place. See
[README.md](README.md) for the build, audit, Verify and migration sequence.

1. In Drupal's Extend page, enable **SMTP Authentication Support**.
2. Set the site email in Basic site settings to the authenticated sending mailbox.
3. Open `/admin/config/system/smtp`, switch SMTP on, and configure:

| Setting | Hostinger native-email value |
| --- | --- |
| SMTP server | `smtp.hostinger.com` |
| Port | `587` |
| Encryption | TLS / STARTTLS |
| Username | Full sending mailbox address |
| Password | Mailbox password, entered privately in the form |
| Email from address | Same sending mailbox |
| Delivery | On, if this control is present |
| Debugging | Off |

Keep certificate verification enabled. Save and send a module test message to
an inbox you control. Then request a normal Drupal password-reset message for
your own registered account from a private browser window. Confirm actual
receipt and the sender; the generic reset confirmation alone proves neither.
Keep the reset URL private.

The SMTP module's password is sensitive Drupal configuration. Protect the site
database/backups and do not commit a configuration export containing that secret.
Keep system/client recipient addresses separate from the authenticated sender.

## Maintenance and recovery gates

- Verify relay settings and delivery after a BOA upgrade/maintenance pass and
  reboot on a disposable VM. Do not declare persistence based on initial delivery.
- After migration/email setup, run site Verify and a fresh full site-files/classic
  mysqldump Backup. Preserve platform code separately for replacement recovery.
- Initial access recovery does not require SMTP: inspect the sensitive local
  welcome file privately or generate a panel login as root:

~~~bash
su -s /bin/bash o1 -c 'drush @hm uli'
~~~

Never publish that URL, welcome contents, SMTP passwords or reset/cron keys.

## Provider and implementation references

- [Hostinger native-email settings](https://www.hostinger.com/support/1575756-how-to-get-email-account-configuration-details-for-hostinger-email/)
- [Postfix SMTP authentication](https://www.postfix.org/SASL_README.html)
- [Postfix TLS policy](https://www.postfix.org/TLS_README.html)
- [Postfix queue maintenance](https://www.postfix.org/postsuper.1.html)
- [Drupal SMTP module](https://www.drupal.org/project/smtp)
- [BOA mailing policy](https://docs.boa.io/operating/security/mailing-policy)
